-- Facture finale conforme LogisVert : AHRI ou ENERGY STAR, licence RBQ, date d'installation, « Payé » (ADR-092)
\set ON_ERROR_STOP on
set client_min_messages = notice;
grant usage on schema test to service_role;
grant execute on all functions in schema test to service_role;
insert into public.leads (id, succursale_code, source, contact_nom, contact_tel, contact_courriel) values
  ('1e000000-0000-0000-0000-000000000201', 'HO', 'google', 'Guy Charron', '450-555-0201', 'guy@exemple.invalid');
set role authenticated;
select test.comme('00000000-0000-0000-0000-00000000000a');
create temp table t_fc as select public.hvac_projet_signe('{"lead_id":"1e000000-0000-0000-0000-000000000201","devis_numero_mike":"121601"}') as id;
grant select on t_fc to service_role;
update public.projets set statut = 'termine' where id = (select id from t_fc);
select test.ok((select cardinality(app.facture_logisvert_manques((select id from t_fc))) = 3), 'il manque : numéro, « Payé », vérification (RBQ et date présentes)');
select test.echec($$update public.projets set statut = 'facture' where id = (select id from t_fc)$$, 'facturé refusé : facture non conforme', 'non conforme');
select test.echec($$select public.hvac_facture_verifiee((select id from t_fc))$$, 'vérification refusée tant que les données manquent', 'Impossible de confirmer');
-- ENERGY STAR suffit (pas besoin de l'AHRI) ; facture payée (manuel d'ici la greffe)
select public.hvac_job_energy_star((select id from t_fc), '2412345');
select test.echec($$select public.hvac_facture_payee_manuel((select id from t_fc), ' ')$$, 'numéro de facture requis', 'requis');
select public.hvac_facture_payee_manuel((select id from t_fc), 'F-2026-0042');
select public.hvac_facture_verifiee((select id from t_fc));
select test.ok((select facture_manques = 0 and facture_verifiee_le is not null from public.projets_macro_v where id = (select id from t_fc)), 'Macro : facture conforme');
update public.projets set statut = 'facture' where id = (select id from t_fc);
select test.ok((select statut = 'facture' from public.projets where id = (select id from t_fc)), 'facturé une fois la facture conforme');
-- Le guide LogisVert part à « Facturé » (pas à « Terminé »)
reset role;
select test.ok((select count(*) = 0 from public.executions x join public.regles r on r.id = x.regle_id
                 where r.code = 'logisvert_client' and x.projet_id = (select id from t_fc) and x.cle like '%:termine'), 'pas de guide à « Terminé »');
select test.ok((select count(*) = 1 from public.executions x join public.regles r on r.id = x.regle_id
                 where r.code = 'logisvert_client' and x.projet_id = (select id from t_fc)), 'guide armé à « Facturé »');
-- Un vendeur ne marque ni payé ni vérifié ; le webhook de Mike marque payé (une fois par paiement)
set role authenticated;
select test.comme('00000000-0000-0000-0000-00000000000c');
select test.echec($$select public.hvac_facture_payee_manuel((select id from t_fc), 'X')$$, 'vendeur : pas de facture payée', 'Réservé');
select test.echec($$select public.hvac_facture_verifiee((select id from t_fc))$$, 'vendeur : pas de vérification', 'Réservé');
reset role;
set role service_role;
select test.ok((select (public.hvac_facture_payee('{"devis_numero_mike":"121601","paiement_ref":"PAY-F1","facture_numero_mike":"F-2026-0042"}')->>'change')::boolean), 'facture payée reçue de Mike');
select test.ok((select not (public.hvac_facture_payee('{"devis_numero_mike":"121601","paiement_ref":"PAY-F1"}')->>'change')::boolean), 'même paiement rejoué : rien');
reset role;
\echo 'TESTS FACTURE LOGISVERT PASSÉS'
