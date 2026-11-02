-- CRM des leads (ADR-056) : tour de rôle, vues, journal, rapidité, tableau de quantification.
\set ON_ERROR_STOP on
set client_min_messages = notice;

-- Un seul vendeur dans le board : il reçoit tout
insert into public.crm_vendeurs(employe_id, ordre) values ('00000000-0000-0000-0000-00000000000c', 1);
insert into public.leads(id, succursale_code, source, contact_nom, contact_tel) values
  ('a5000000-0000-0000-0000-000000000001','RO','google','Lead Un (FICTIF)','450-555-0101'),
  ('a5000000-0000-0000-0000-000000000002','RO','facebook','Lead Deux (FICTIF)','450-555-0102');
select test.ok((select count(*) = 2 from public.leads where assigne_a = '00000000-0000-0000-0000-00000000000c'
                 and id::text like 'a5%'), 'un seul vendeur : il reçoit tous les leads');

-- Deuxième et troisième vendeurs : tour de rôle 1, 2, 3, 1...
insert into public.crm_vendeurs(employe_id, ordre) values
  ('00000000-0000-0000-0000-00000000000d', 2), ('00000000-0000-0000-0000-00000000000e', 3);
insert into public.leads(id, succursale_code, source, contact_nom) values
  ('a5000000-0000-0000-0000-000000000003','RO','google','L3'),
  ('a5000000-0000-0000-0000-000000000004','RO','google','L4'),
  ('a5000000-0000-0000-0000-000000000005','RO','google','L5'),
  ('a5000000-0000-0000-0000-000000000006','RO','google','L6');
select test.ok((select array_agg(right(assigne_a::text, 1) order by id) = array['d','e','c','d']
                  from public.leads where id::text like 'a5%' and id > 'a5000000-0000-0000-0000-000000000002'),
               'trois vendeurs : tour de rôle c, d, e, c, d...');
-- Un vendeur retiré du board ne reçoit plus rien
update public.crm_vendeurs set actif = false where employe_id = '00000000-0000-0000-0000-00000000000e';
insert into public.leads(id, succursale_code, source, contact_nom) values
  ('a5000000-0000-0000-0000-000000000007','RO','google','L7'),
  ('a5000000-0000-0000-0000-000000000008','RO','google','L8');
select test.ok((select array_agg(right(assigne_a::text, 1) order by id) = array['c','d']
                  from public.leads where id in ('a5000000-0000-0000-0000-000000000007','a5000000-0000-0000-0000-000000000008')),
               'vendeur inactif sauté');
select test.ok((select count(*) = 8 from public.lead_activites where type = 'attribution' and lead_id::text like 'a5%'),
               'chaque attribution est journalisée');

-- Vues : le vendeur voit ses leads, le board principal voit tout
set role authenticated;
select test.comme('00000000-0000-0000-0000-00000000000c');
select test.ok((select count(*) = 4 from public.leads where id::text like 'a5%'), 'vue du vendeur : seulement ses leads');
select test.comme('00000000-0000-0000-0000-00000000000a');
select test.ok((select count(*) = 8 from public.leads where id::text like 'a5%'), 'board principal (Simon) : tous les leads');

-- Journal du vendeur et horodatage par la base
select test.comme('00000000-0000-0000-0000-00000000000c');
select test.echec($$insert into public.lead_activites(lead_id, type) values ('a5000000-0000-0000-0000-000000000003','prise_en_charge')$$,
                  'prendre en charge le lead d''un autre vendeur');
update public.leads set premier_contact_le = now() - interval '1 day' where id = 'a5000000-0000-0000-0000-000000000001';
reset role;
select test.ok((select premier_contact_le is null from public.leads where id = 'a5000000-0000-0000-0000-000000000001'),
               'le vendeur ne peut pas antidater son premier contact (horodatage de la base)');
update public.leads set recu_le = now() - interval '3 days' where id = 'a5000000-0000-0000-0000-000000000001';
select test.ok((select recu_le > now() - interval '1 minute' from public.leads where id = 'a5000000-0000-0000-0000-000000000001'),
               'l''heure d''arrivée ne se modifie pas');

-- Pour mesurer, on recule l'arrivée (triggers coupés, comme un import Monday daté)
set session_replication_role = replica;
update public.leads set recu_le = now() - interval '60 minutes' where id = 'a5000000-0000-0000-0000-000000000001';
update public.leads set recu_le = now() - interval '10 minutes' where id = 'a5000000-0000-0000-0000-000000000005';
set session_replication_role = origin;

set role authenticated;
select test.comme('00000000-0000-0000-0000-00000000000c');
insert into public.lead_activites(lead_id, type) values ('a5000000-0000-0000-0000-000000000001','prise_en_charge');
insert into public.lead_activites(lead_id, type, resultat, note) values ('a5000000-0000-0000-0000-000000000001','appel','joint','Intéressé, veut une visite');
insert into public.lead_activites(lead_id, type) values ('a5000000-0000-0000-0000-000000000005','texto');
select test.echec($$insert into public.lead_activites(lead_id, type) values ('a5000000-0000-0000-0000-000000000001','visite_planifiee')$$,
                  'visite sans date', 'Date de visite');
insert into public.lead_activites(lead_id, type, visite_le) values ('a5000000-0000-0000-0000-000000000001','visite_planifiee', now() + interval '3 days');
update public.lead_activites set note = 'retouche' where lead_id = 'a5000000-0000-0000-0000-000000000001';
reset role;
select test.ok((select count(*) = 0 from public.lead_activites where note = 'retouche'), 'le vendeur ne retouche pas son journal (RLS)');
select test.echec($$update public.lead_activites set note = 'retouche' where lead_id = 'a5000000-0000-0000-0000-000000000001'$$,
                  'même un administrateur de la base ne modifie pas le journal', 'ne se modifie pas');

select test.ok((select statut = 'inspection_planifiee' and premier_contact_canal = 'appel'
                       and minutes_premier_contact between 59 and 61 and visite_prevue_le > now()
                  from public.leads_v where id = 'a5000000-0000-0000-0000-000000000001'),
               'lead 1 : contacté par appel après 60 min, visite planifiée');
select test.ok((select statut = 'contacte' and premier_contact_canal = 'texto' and minutes_premier_contact between 9 and 11
                  from public.leads_v where id = 'a5000000-0000-0000-0000-000000000005'),
               'lead 5 : premier contact par texto après 10 min');
select test.echec($$insert into public.lead_activites(lead_id, type, employe_id) values ('a5000000-0000-0000-0000-000000000005','perdu','00000000-0000-0000-0000-00000000000c')$$,
                  'perdu sans raison', 'Raison');

-- Tableau de quantification : vide = non évalué ; rempli = bon / moyen / à améliorer
select test.ok((select bool_and(cote = 'non_evalue') from public.crm_evaluation_v
                 where employe_id = '00000000-0000-0000-0000-00000000000c'), 'seuils vides : vendeur non évalué');
select test.ok((select not en_retard from public.leads_v where id = 'a5000000-0000-0000-0000-000000000007'),
               'aucun seuil : aucun lead en retard');
update public.crm_objectifs set seuil_bon = 15, seuil_moyen = 45 where indicateur = 'minutes_premier_contact';
update public.crm_objectifs set seuil_bon = 80, seuil_moyen = 50 where indicateur = 'pct_premier_par_appel';
select test.ok((select valeur = 35 and cote = 'moyen' from public.crm_evaluation_v
                 where employe_id = '00000000-0000-0000-0000-00000000000c' and indicateur = 'minutes_premier_contact'),
               'médiane 35 min (10 et 60) : « moyen » entre 15 et 45');
select test.ok((select valeur = 50 and cote = 'moyen' from public.crm_evaluation_v
                 where employe_id = '00000000-0000-0000-0000-00000000000c' and indicateur = 'pct_premier_par_appel'),
               '50 % des premiers contacts par appel : « moyen »');
update public.crm_objectifs set seuil_bon = 5, seuil_moyen = 30 where indicateur = 'minutes_premier_contact';
select test.ok((select cote = 'a_ameliorer' from public.crm_evaluation_v
                 where employe_id = '00000000-0000-0000-0000-00000000000c' and indicateur = 'minutes_premier_contact'),
               'seuils resserrés : « à améliorer »');
select test.echec($$update public.crm_objectifs set seuil_bon = 60, seuil_moyen = 10 where indicateur = 'minutes_premier_contact'$$,
                  'seuil « bon » moins exigeant que « moyen »');
select test.ok((select app.cote(4, 'bas', 5, 30) = 'bon' and app.cote(90, 'haut', 80, 50) = 'bon'
                       and app.cote(20, 'haut', 80, 50) = 'a_ameliorer'), 'fonction de cote');

-- Seul le board principal modifie le tableau et réattribue
set role authenticated;
select test.comme('00000000-0000-0000-0000-00000000000c');
update public.crm_objectifs set seuil_bon = 999 where indicateur = 'pct_visites';
select test.echec($$update public.leads set assigne_a = '00000000-0000-0000-0000-00000000000d' where id = 'a5000000-0000-0000-0000-000000000005'$$,
                  'vendeur qui passe son lead à un autre', 'responsable du board');
select test.comme('00000000-0000-0000-0000-00000000000a');
update public.leads set assigne_a = '00000000-0000-0000-0000-00000000000d' where id = 'a5000000-0000-0000-0000-000000000001';
reset role;
reset request.jwt.claims;
select test.ok((select seuil_bon is null from public.crm_objectifs where indicateur = 'pct_visites'),
               'un vendeur ne change pas le tableau de quantification');
select test.ok((select assigne_a = '00000000-0000-0000-0000-00000000000d' from public.leads where id = 'a5000000-0000-0000-0000-000000000001'),
               'Simon réattribue un lead');

\echo 'TESTS CRM PASSÉS'
