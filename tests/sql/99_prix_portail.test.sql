-- Liste de prix gérée par le sous-traitant, engagements et renouvellement (ADR-062)
\set ON_ERROR_STOP on
set client_min_messages = notice;
update public.parametres set valeur = 'false' where cle = 'exiger_preinstallation';
create temp table t_ref as select id as type_id from public.types_travaux where code = 'INST-MULTI-3T';
create temp table t_autre as select id as type_id from public.types_travaux where code = 'SERV-HEURE';
grant select on t_ref, t_autre to authenticated;

insert into public.tarifs_sous_traitants(fournisseur_id, type_travail_id, cout_cents, en_vigueur_du)
  select 'f2000000-0000-0000-0000-000000000001', type_id, 100000, '2026-01-01' from t_ref;
insert into public.travaux_sous_traitants(fournisseur_id, type_travail_id)
  select 'f2000000-0000-0000-0000-000000000001', type_id from t_ref
  on conflict do nothing;

-- Un devis envoyé avec l'installation de ce sous-traitant (prix de la grille : 1 000 $)
insert into public.devis(id, succursale_code, client_id, vendeur_id) values
  ('4a000000-0000-0000-0000-000000000001','RO','30000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-00000000000c');
insert into public.devis_lignes(devis_id, type_ligne, type_travail_id, sous_traitant_id, description, prix_unitaire_cents)
  select '4a000000-0000-0000-0000-000000000001','installation', type_id, 'f2000000-0000-0000-0000-000000000001', 'Installation murale', 0 from t_ref;
update public.devis set statut = 'envoye' where id = '4a000000-0000-0000-0000-000000000001';

-- Le sous-traitant voit ses engagements, sans le nom du client
set role authenticated;
select test.comme('00000000-0000-0000-0000-0000000000c1');
select test.ok((select count(*) = 1 and min(cout_cents) = 100000 and min(honorer_jusqu) >= current_date
                  from public.hvac_mes_engagements(null, (select array_agg(type_id) from t_ref))), 'engagement : devis actif à honorer à 1 000 $ jusqu''à son échéance');

-- Il change son prix : effet sur les NOUVEAUX devis, le devis actif garde 1 000 $
select test.ok((select (public.hvac_maj_mes_prix(jsonb_build_array(jsonb_build_object('type_travail_id', type_id, 'cout_cents', 120000)))->>'changes')::int = 1
                  from t_ref), 'le sous-traitant modifie son prix lui-même');
select test.ok((select (public.hvac_maj_mes_prix(jsonb_build_array(jsonb_build_object('type_travail_id', type_id, 'cout_cents', 125000)))->>'changes')::int = 1
                  from t_ref), 'deuxième modification le même jour : remplace celle du jour');
select test.echec($$select public.hvac_maj_mes_prix(jsonb_build_array(jsonb_build_object('type_travail_id', (select type_id from t_autre), 'cout_cents', 5000)))$$,
                  'prix d''un travail non confié', 'pas confié');
reset role;
select test.ok((select public.hvac_cout_installation('f2000000-0000-0000-0000-000000000001', type_id) = 125000 from t_ref), 'nouveau prix en vigueur : 1 250 $');
select test.ok((select count(*) = 1 from public.tarifs_sous_traitants t join t_ref r on r.type_id = t.type_travail_id
                 where fournisseur_id = 'f2000000-0000-0000-0000-000000000001' and en_vigueur_du = (now() at time zone 'America/Toronto')::date),
               'un seul prix pour aujourd''hui');
select test.ok((select cout_cents = 100000 from public.devis_lignes where devis_id = '4a000000-0000-0000-0000-000000000001' and type_ligne = 'installation'),
               'le devis actif garde le prix d''origine (à honorer)');
select test.ok((select count(*) >= 1 from public.notifications where destinataire_employe_id = '00000000-0000-0000-0000-00000000000c' and type = 'prix_sous_traitant'),
               'le vendeur du devis actif est avisé');
select test.ok((select count(*) >= 1 from public.notifications where type = 'prix_sous_traitant' and titre = 'Liste de prix modifiée'),
               'Simon et Mike sont avisés');
select test.echec($$update public.tarifs_sous_traitants set cout_cents = 1 where fournisseur_id = 'f2000000-0000-0000-0000-000000000001'$$,
                  'modifier un prix directement', 'interdit');

-- Renouvellement : le nouveau devis prend le nouveau prix, le vendeur est avisé de l'écart
set role authenticated;
select test.comme('00000000-0000-0000-0000-00000000000c');
create temp table t_renouv as select public.hvac_dupliquer_devis('4a000000-0000-0000-0000-000000000001') as id;
reset role;
select test.ok((select cout_cents = 125000 from public.devis_lignes where devis_id = (select id from t_renouv) and type_ligne = 'installation'),
               'renouvellement : nouveau prix du sous-traitant attitré');
select test.ok((select count(*) = 1 from public.devis_ecarts_prix_v where devis_id = (select id from t_renouv) and ancien_cout_cents = 100000),
               'écart visible sur le devis renouvelé');
select test.ok((select count(*) = 1 from public.notifications where type = 'prix_renouvellement' and destinataire_employe_id = '00000000-0000-0000-0000-00000000000c'),
               'le vendeur est avisé de la nouvelle liste de prix');

-- Un vendeur ne change pas les prix ; Simon peut le faire pour un sous-traitant
set role authenticated;
select test.comme('00000000-0000-0000-0000-00000000000c');
select test.echec($$select public.hvac_maj_mes_prix('[]'::jsonb, 'f2000000-0000-0000-0000-000000000001')$$, 'vendeur qui change un prix', 'Sous-traitant requis');
reset role;
\echo 'TESTS PORTAIL DE PRIX PASSÉS'
