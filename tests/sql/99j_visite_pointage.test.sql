-- Visite planifiée dans Pointage : la date arrive seule dans le lead, sans double saisie (ADR-086)
\set ON_ERROR_STOP on
set client_min_messages = notice;
insert into public.leads (id, succursale_code, source, contact_nom, contact_tel, assigne_a) values
  ('1e000000-0000-0000-0000-0000000000e1', 'RO', 'facebook', 'Annie Ouimet', '(450) 555-0133', '00000000-0000-0000-0000-00000000000c'),
  ('1e000000-0000-0000-0000-0000000000e2', 'RO', 'google', 'Paul Ouimet', '450-555-0177', '00000000-0000-0000-0000-00000000000c'),
  ('1e000000-0000-0000-0000-0000000000e3', 'RO', 'google', 'Jean Ouimet', '450 555 0177', '00000000-0000-0000-0000-00000000000c');

grant usage on schema test to service_role;
grant execute on all functions in schema test to service_role;
-- Le navigateur (vendeur) ne peut pas appeler la fonction du webhook
set role authenticated;
select test.comme('00000000-0000-0000-0000-00000000000c');
select test.echec($$select public.hvac_visite_pointage('{"lead_ref":"1e000000-0000-0000-0000-0000000000e1","pointage_ref":"PI-1","visite_le":"2026-11-03T14:00:00Z"}')$$,
  'vendeur qui imite Pointage', 'permission');
select test.echec($$insert into public.lead_activites (lead_id, type, visite_le, source, employe_id) values
  ('1e000000-0000-0000-0000-0000000000e1', 'visite_planifiee', now(), 'pointage', '00000000-0000-0000-0000-00000000000c')$$, 'activité « Pointage » forgée', 'row-level security');
update public.leads set visite_pointage_ref = 'X' where id = '1e000000-0000-0000-0000-0000000000e1';
select test.ok((select visite_pointage_ref is null from public.leads where id = '1e000000-0000-0000-0000-0000000000e1'), 'référence Pointage forgée : ignorée');
reset role;

-- Le webhook (serveur) : visite planifiée par la référence du lead
set role service_role;
select test.ok((select (public.hvac_visite_pointage('{"lead_ref":"1e000000-0000-0000-0000-0000000000e1","pointage_ref":"PI-1","visite_le":"2026-11-03T14:00:00Z"}')->>'change')::boolean),
               'visite reçue de Pointage');
reset role;
select test.ok((select statut = 'inspection_planifiee' and visite_prevue_le = '2026-11-03T14:00:00Z' and visite_pointage_ref = 'PI-1' and pris_en_charge_le is not null
                  from public.leads where id = '1e000000-0000-0000-0000-0000000000e1'), 'lead : date de Pointage, statut Visite planifiée, pris en charge');
select test.ok((select employe_id = '00000000-0000-0000-0000-00000000000c' and source = 'pointage' from public.lead_activites
                  where lead_id = '1e000000-0000-0000-0000-0000000000e1' and type = 'visite_planifiee'), 'journal : source Pointage, au nom du vendeur du lead');
set role service_role;
-- Même envoi rejoué : rien en double ; date déplacée : suivie
select test.ok((select not (public.hvac_visite_pointage('{"lead_ref":"1e000000-0000-0000-0000-0000000000e1","pointage_ref":"PI-1","visite_le":"2026-11-03T14:00:00Z"}')->>'change')::boolean),
               'même envoi rejoué : rien en double');
select public.hvac_visite_pointage('{"pointage_ref":"PI-1","visite_le":"2026-11-05T13:30:00Z"}');
reset role;
select test.ok((select visite_prevue_le = '2026-11-05T13:30:00Z' from public.leads where id = '1e000000-0000-0000-0000-0000000000e1'), 'visite déplacée : retrouvée par sa référence, nouvelle date');
select test.ok((select count(*) = 2 from public.lead_activites where lead_id = '1e000000-0000-0000-0000-0000000000e1' and type = 'visite_planifiee'), 'journal : 2 entrées (planifiée, déplacée)');
set role service_role;
-- Annulation : le lead revient à Contacté ou Pris en charge, plus de date
select public.hvac_visite_pointage('{"pointage_ref":"PI-1","annulee":true}');
reset role;
select test.ok((select statut = 'pris_en_charge' and visite_prevue_le is null and visite_pointage_ref is null from public.leads where id = '1e000000-0000-0000-0000-0000000000e1'),
               'visite annulée : plus de date, statut revenu');
set role service_role;
-- Par téléphone : un seul lead ouvert, sinon refusé
select public.hvac_visite_pointage('{"telephone":"450.555.0133","pointage_ref":"PI-2","visite_le":"2026-11-10T15:00:00Z"}');
select test.echec($$select public.hvac_visite_pointage('{"telephone":"4505550177","pointage_ref":"PI-3","visite_le":"2026-11-10T15:00:00Z"}')$$, 'téléphone ambigu', 'Plusieurs leads');
select test.echec($$select public.hvac_visite_pointage('{"telephone":"5145550000","pointage_ref":"PI-4","visite_le":"2026-11-10T15:00:00Z"}')$$, 'lead introuvable', 'introuvable');
reset role;
select test.ok((select visite_pointage_ref = 'PI-2' from public.leads where id = '1e000000-0000-0000-0000-0000000000e1'), 'trouvé par le téléphone (format différent)');
select test.ok((select visite_pointage_ref = 'PI-2' and visite_prevue_le is not null from public.leads_v where id = '1e000000-0000-0000-0000-0000000000e1'), 'leads_v montre la référence Pointage');
select test.ok((select count(*) > 0 from public.crm_rapidite_v), 'vues de rapidité recréées');

-- Une fois Pointage branché : le vendeur ne saisit plus la date
update public.parametres set valeur = 'true' where cle = 'visites_pointage_seulement';
set role authenticated;
select test.comme('00000000-0000-0000-0000-00000000000c');
select test.echec($$insert into public.lead_activites (lead_id, type, visite_le, employe_id) values
  ('1e000000-0000-0000-0000-0000000000e2', 'visite_planifiee', now(), '00000000-0000-0000-0000-00000000000c')$$, 'saisie manuelle quand Pointage est branché', 'row-level security');
reset role;
update public.parametres set valeur = 'false' where cle = 'visites_pointage_seulement';
\echo 'TESTS VISITE POINTAGE PASSÉS'
