-- Dépôt reçu dans l'app de Mike : le projet passe seul à « À céduler » (ADR-087)
\set ON_ERROR_STOP on
set client_min_messages = notice;
grant usage on schema test to service_role;
grant execute on all functions in schema test to service_role;
create temp table t_dt as select id as type_id from public.types_travaux where code = 'INST-MULTI-2T';
grant select on t_dt to authenticated;
insert into public.leads (id, succursale_code, contact_nom, contact_tel, ville, type_demande) values
  ('1e000000-0000-0000-0000-0000000000f1', 'RO', 'Sylvie Lauzon', '450-555-0111', 'Rosemère', 'mural_multi'),
  ('1e000000-0000-0000-0000-0000000000f2', 'RO', 'René Lauzon', '450-555-0112', 'Rosemère', 'mural_simple');
set role authenticated;
select test.comme('00000000-0000-0000-0000-00000000000a');
create temp table t_pd as select public.hvac_projet_signe(format($${"lead_id":"1e000000-0000-0000-0000-0000000000f1","devis_numero_mike":"121401",
  "sous_traitant_id":"f2000000-0000-0000-0000-000000000001","lignes":[{"type_ligne":"installation","type_travail_id":"%s"}]}$$,
  (select type_id from t_dt))::jsonb) as id;
create temp table t_pa as select public.hvac_projet_signe('{"lead_id":"1e000000-0000-0000-0000-0000000000f2","devis_numero_mike":"121402"}') as id;
grant select on t_pd, t_pa to service_role;
update public.projets set statut = 'annule' where id = (select id from t_pa);
-- Un employé ne peut pas imiter l'app de Mike
select test.echec($$select public.hvac_depot_recu('{"devis_numero_mike":"121401","paiement_ref":"PAY-1"}')$$, 'employé qui imite le paiement', 'permission');
reset role;

set role service_role;
select test.ok((select (public.hvac_depot_recu('{"devis_numero_mike":"#121401","paiement_ref":"PAY-1","montant_cents":336000}')->>'change')::boolean), 'dépôt reçu');
reset role;
select test.ok((select statut = 'a_planifier' and depot_montant_cents = 336000 and depot_ref = 'PAY-1' and depot_recu_le is not null
                  from public.projets where id = (select id from t_pd)), 'projet passé seul à À céduler, dépôt noté');
select test.ok((select count(*) >= 1 from public.notifications where type = 'depot_recu' and destinataire_employe_id is not null), 'avis à la planification');
select test.ok((select count(*) = 1 from public.notifications where type = 'depot_recu' and destinataire_fournisseur_id = 'f2000000-0000-0000-0000-000000000001'),
               'avis au sous-traitant attitré');
set role service_role;
select test.ok((select not (public.hvac_depot_recu('{"devis_numero_mike":"121401","paiement_ref":"PAY-1","montant_cents":336000}')->>'change')::boolean), 'même paiement rejoué : rien en double');
select test.ok((select public.hvac_depot_recu('{"devis_numero_mike":"121402","paiement_ref":"PAY-2"}')->>'raison' = 'étape : annule'), 'projet annulé : l''étape ne bouge pas');
select test.echec($$select public.hvac_depot_recu('{"devis_numero_mike":"999999","paiement_ref":"PAY-3"}')$$, 'soumission inconnue', 'introuvable');
select test.echec($$select public.hvac_depot_recu('{"devis_numero_mike":"121401"}')$$, 'sans référence de paiement', 'Référence');
reset role;
select test.ok((select statut = 'annule' and depot_ref = 'PAY-2' from public.projets where id = (select id from t_pa)), 'dépôt sur projet annulé : noté, statut gardé');
select test.ok((select count(*) = 1 from public.notifications where type = 'depot_projet_annule' and destinataire_employe_id = '00000000-0000-0000-0000-00000000000a'),
               'avis : dépôt sur un projet annulé');
select test.ok((select depot_montant_cents = 336000 from public.projets_macro_v where id = (select id from t_pd)), 'Macro : dépôt visible');
\echo 'TESTS DÉPÔT REÇU PASSÉS'
