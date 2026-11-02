-- Mes jobs : projet signé chez le sous-traitant, machines à 0 $, ses prix seulement (ADR-080)
\set ON_ERROR_STOP on
set client_min_messages = notice;
create temp table t_j as select id as type_id from public.types_travaux where code = 'INST-MULTI-2T';
create temp table t_j2 as select id as type_id from public.types_travaux where code = 'INST-MULTI-4T';
grant select on t_j, t_j2 to authenticated;
insert into public.tarifs_sous_traitants(fournisseur_id, type_travail_id, cout_cents, en_vigueur_du)
  select 'f2000000-0000-0000-0000-000000000001', type_id, 210000, '2026-01-01' from t_j on conflict do nothing;
insert into public.travaux_sous_traitants(fournisseur_id, type_travail_id)
  select 'f2000000-0000-0000-0000-000000000001', type_id from t_j on conflict do nothing;
insert into public.leads (id, succursale_code, contact_nom, contact_tel, ville, type_demande) values
  ('1e000000-0000-0000-0000-0000000000a1', 'RO', 'Paul Côté', '450-555-0177', 'Blainville', 'mural_multi');
set role authenticated;

select test.comme('00000000-0000-0000-0000-00000000000a');
-- Un travail non confié à ce sous-traitant est refusé
select test.echec(format($$select public.hvac_projet_signe('{"lead_id":"1e000000-0000-0000-0000-0000000000a1","devis_numero_mike":"121001",
  "sous_traitant_id":"f2000000-0000-0000-0000-000000000001","lignes":[{"type_ligne":"installation","type_travail_id":"%s"}]}')$$,
  (select type_id from t_j2)), 'travail non confié', 'pas confié');
-- Installation sans sous-traitant : refusée
select test.echec(format($$select public.hvac_projet_signe('{"lead_id":"1e000000-0000-0000-0000-0000000000a1","devis_numero_mike":"121001",
  "lignes":[{"type_ligne":"installation","type_travail_id":"%s"}]}')$$, (select type_id from t_j)), 'installation sans sous-traitant', 'sans sous-traitant');

create temp table t_pj as select public.hvac_projet_signe(format($${"lead_id":"1e000000-0000-0000-0000-0000000000a1","devis_numero_mike":"121001",
  "montant_avant_taxes_cents":1125000,"sous_traitant_id":"f2000000-0000-0000-0000-000000000001",
  "lignes":[{"type_ligne":"machine","description":"Thermopompe multizone 2 têtes 18 000 BTU","quantite":1},
            {"type_ligne":"machine","description":"Tête murale 9 000 BTU","quantite":2},
            {"type_ligne":"installation","type_travail_id":"%s","quantite":1}]}$$, (select type_id from t_j))::jsonb) as id;
grant select on t_pj to authenticated;
select test.ok((select sous_traitant_id = 'f2000000-0000-0000-0000-000000000001' and cout_installation_cents = 210000
                  from public.projets_macro_v where id = (select id from t_pj)), 'Macro : sous-traitant et coût d''installation tirés de sa liste');

-- Le sous-traitant voit le projet dès « Signé, attente du dépôt »
select test.comme('00000000-0000-0000-0000-0000000000c1');
select test.ok((select count(*) = 1 from public.hvac_mes_projets() where id = (select id from t_pj)), 'le projet tombe chez le sous-traitant attitré');
select test.ok((select total_cents = 210000 from public.hvac_mes_projets() where id = (select id from t_pj)), 'total = son prix d''installation seulement');
select test.ok((select bool_and((x->>'prix_cents')::bigint = 0 and (x->>'total_cents')::bigint = 0)
                  from public.hvac_mes_projets() j, jsonb_array_elements(j.lignes) x where j.id = (select id from t_pj) and x->>'type_ligne' = 'machine'),
               'machines affichées à 0 $');
select test.ok((select not (to_jsonb(j) ?| array['montant_avant_taxes_cents','prix_unitaire_cents','marge'])
                  and not (j.lignes::text like '%1125000%') from public.hvac_mes_projets() j where j.id = (select id from t_pj)),
               'ni prix client, ni total de facture, ni marge');
select test.ok((select client_nom is null and client_telephone is null from public.hvac_mes_projets() where id = (select id from t_pj)),
               'Loi 25 : pas de nom ni de téléphone avant le dépôt');
select test.ok((select count(*) = 0 from public.projets where id = (select id from t_pj)), 'le sous-traitant ne lit pas la table des projets');
select test.ok((select count(*) = 0 from public.projet_lignes), 'le sous-traitant ne lit pas les lignes directement');

-- Après le dépôt : nom et téléphone pour faire la job
select test.comme('00000000-0000-0000-0000-00000000000a');
update public.projets set statut = 'a_planifier' where id = (select id from t_pj);
select test.comme('00000000-0000-0000-0000-0000000000c1');
select test.ok((select client_nom = 'Paul Côté' and client_telephone = '450-555-0177' from public.hvac_mes_projets() where id = (select id from t_pj)),
               'après le dépôt : nom et téléphone du client');

-- Annulé : disparaît de Mes jobs ; un vendeur n'a pas accès
select test.comme('00000000-0000-0000-0000-00000000000a');
update public.projets set statut = 'annule' where id = (select id from t_pj);
select test.comme('00000000-0000-0000-0000-0000000000c1');
select test.ok((select count(*) = 0 from public.hvac_mes_projets() where id = (select id from t_pj)), 'projet annulé : retiré de Mes jobs');
select test.comme('00000000-0000-0000-0000-00000000000c');
select test.echec($$select * from public.hvac_mes_projets()$$, 'un vendeur ne voit pas Mes jobs', 'Sous-traitant requis');
reset role;
\echo 'TESTS MES JOBS PASSÉS'
