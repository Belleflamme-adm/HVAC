-- Registre des versions de la liste de prix (ADR-065)
\set ON_ERROR_STOP on
set client_min_messages = notice;
create temp table t_reg as select
  (select id from public.types_travaux where code = 'SERV-HEURE') as heure,
  (select id from public.types_travaux where code = 'INST-CENTRAL-NEUF') as autre,
  (select coalesce(max(numero), 0) from public.listes_prix_versions where fournisseur_id = 'f2000000-0000-0000-0000-000000000001') as v0;
grant select on t_reg to authenticated;
set role authenticated;

-- Belleflamme confie un travail : nouvelle version, changement « ajout »
select test.comme('00000000-0000-0000-0000-00000000000a');
select test.ok((select (public.hvac_confier_travaux('f2000000-0000-0000-0000-000000000001', array[heure], '{}')->>'version')::int = v0 + 1 from t_reg),
               'travail confié : nouvelle version au registre');
select test.ok((select changements @> '[{"type":"ajout","code":"SERV-HEURE"}]' and not par_sous_traitant and auteur_nom = 'Simon Cardinal'
                  from public.listes_prix_versions where fournisseur_id = 'f2000000-0000-0000-0000-000000000001' order by numero desc limit 1),
               'version : changement « ajout », auteur Simon, pas le sous-traitant');
select test.ok((select public.hvac_confier_travaux('f2000000-0000-0000-0000-000000000001', array[heure], '{}')->>'version' is null from t_reg),
               'aucun changement : pas de nouvelle version');

-- Le sous-traitant met son prix : version par le sous-traitant, avant / après
select test.comme('00000000-0000-0000-0000-0000000000c1');
select test.ok((select (public.hvac_maj_mes_prix(jsonb_build_array(jsonb_build_object('type_travail_id', heure, 'cout_cents', 9000)))->>'version')::int = v0 + 2 from t_reg),
               'prix du sous-traitant : nouvelle version');
select test.ok((select par_sous_traitant and changements @> '[{"type":"prix","code":"SERV-HEURE","apres":9000}]'
                       and empreinte = encode(sha256(convert_to(lignes::text, 'UTF8')), 'hex')
                  from public.listes_prix_versions where fournisseur_id = 'f2000000-0000-0000-0000-000000000001' order by numero desc limit 1),
               'version : faite par le sous-traitant, prix avant / après, empreinte SHA-256 juste');
select test.ok((select count(*) > 0 from public.listes_prix_versions), 'le sous-traitant voit son registre');
select test.ok((select count(*) = 0 from public.listes_prix_versions where fournisseur_id <> 'f2000000-0000-0000-0000-000000000001'),
               'le sous-traitant ne voit pas le registre des autres');
select test.echec($$select public.hvac_confier_travaux('f2000000-0000-0000-0000-000000000001', '{}', '{}')$$, 'le sous-traitant ne confie pas de travaux', 'planification');

-- Changements à répétition : alerte à Simon et Mike
select null from (select public.hvac_maj_mes_prix(jsonb_build_array(jsonb_build_object('type_travail_id', heure, 'cout_cents', 9500))) from t_reg) s;
select null from (select public.hvac_maj_mes_prix(jsonb_build_array(jsonb_build_object('type_travail_id', heure, 'cout_cents', 9900))) from t_reg) s;

-- Un vendeur ne voit pas le registre
select test.comme('00000000-0000-0000-0000-00000000000c');
select test.ok((select count(*) = 0 from public.listes_prix_versions), 'un vendeur ne voit pas le registre');

-- Belleflamme met un prix sur un travail non confié : confié du même coup, versionné
select test.comme('00000000-0000-0000-0000-00000000000a');
select test.ok((select (public.hvac_maj_mes_prix(jsonb_build_array(jsonb_build_object('type_travail_id', autre, 'cout_cents', 500000)), 'f2000000-0000-0000-0000-000000000001')->>'version') is not null from t_reg),
               'prix mis par Belleflamme : version au registre');
select test.ok((select count(*) = 1 from public.travaux_sous_traitants, t_reg where fournisseur_id = 'f2000000-0000-0000-0000-000000000001' and type_travail_id = autre),
               'un prix mis par Belleflamme confie le travail');
select test.echec($$insert into public.listes_prix_versions(fournisseur_id, numero, auteur_nom, motif, lignes, changements, nb_lignes, nb_changements, empreinte)
                   values ('f2000000-0000-0000-0000-000000000001', 999, 'x', 'x', '[]', '[]', 0, 0, 'x')$$, 'personne n''écrit directement au registre');
reset role;
select test.ok((select count(*) > 0 from public.notifications where type = 'liste_prix_frequente'), 'alerte : liste modifiée 3 fois ou plus en 30 jours');
select test.echec($$update public.listes_prix_versions set motif = 'retouché'$$, 'une version archivée ne se modifie pas', 'archivée');
select test.echec($$delete from public.listes_prix_versions$$, 'une version archivée ne s''efface pas', 'archivée');
\echo 'TESTS REGISTRE DES LISTES DE PRIX PASSÉS'
