-- Macro HVAC : projet signé reçu, lead vendu, étapes (ADR-079)
\set ON_ERROR_STOP on
set client_min_messages = notice;
insert into public.leads (id, succursale_code, contact_nom, contact_tel, ville, type_demande) values
  ('1e000000-0000-0000-0000-000000000099', 'RO', 'Josée Tremblay', '450-555-0199', 'Blainville', 'mural_multi');
set role authenticated;

-- Un vendeur ne crée pas de projet
select test.comme('00000000-0000-0000-0000-00000000000c');
select test.echec($$select public.hvac_projet_signe('{"lead_id":"1e000000-0000-0000-0000-000000000099","devis_numero_mike":"120900"}')$$, 'un vendeur ne crée pas de projet', 'Réservé');

-- Le projet signé tombe dans le Macro ; le lead passe à Vendu ; le client est créé
select test.comme('00000000-0000-0000-0000-00000000000a');
create temp table t_p as select public.hvac_projet_signe('{"lead_id":"1e000000-0000-0000-0000-000000000099","devis_numero_mike":"120900","montant_avant_taxes_cents":985000}') as id;
select test.ok((select statut = 'attente_paiement' and code_projet is not null and type_systeme = 'mural_multi' and montant_avant_taxes_cents = 985000
                  from public.projets where id = (select id from t_p)), 'projet signé : étape « signé, attente du dépôt », code projet attribué');
select test.ok((select statut = 'converti' and client_id is not null from public.leads where id = '1e000000-0000-0000-0000-000000000099'), 'le lead passe à Vendu et reçoit son client');
select test.ok((select client_nom = 'Josée Tremblay' and ville = 'Blainville' from public.projets_macro_v where id = (select id from t_p)), 'vue Macro : client et ville');
select test.ok((select public.hvac_projet_signe('{"lead_id":"1e000000-0000-0000-0000-000000000099","devis_numero_mike":"120900"}') = id from t_p), 'même devis reçu deux fois : un seul projet');

-- Étapes
update public.projets set statut = 'planifie' where id = (select id from t_p);
select test.ok((select statut = 'planifie' from public.projets where id = (select id from t_p)), 'un projet avance de plusieurs étapes');
select test.echec($$update public.projets set statut = 'attente_paiement' where id = (select id from t_p)$$, 'un projet ne recule pas de deux étapes', 'recule');
update public.projets set statut = 'a_planifier' where id = (select id from t_p);
select test.ok((select statut = 'a_planifier' from public.projets where id = (select id from t_p)), 'un projet recule d''une étape');
-- « Facturé » exige une facture finale conforme LogisVert (ADR-092) : voir 99m ; ici on la prépare
select test.echec($$update public.projets set statut = 'facture' where id = (select id from t_p)$$, 'facturé sans facture conforme', 'non conforme');
update public.projets set statut = 'termine' where id = (select id from t_p);
select public.hvac_job_ahri((select id from t_p), '210555111');
select public.hvac_facture_payee_manuel((select id from t_p), 'F-2026-0001');
select public.hvac_facture_verifiee((select id from t_p));
update public.projets set statut = 'facture' where id = (select id from t_p);
select test.echec($$update public.projets set statut = 'annule' where id = (select id from t_p)$$, 'un projet facturé ne s''annule pas', 'facturé');
reset role;
\echo 'TESTS MACRO PASSÉS'
