-- Accès des sous-traitants : un compte, envoi du code, couper et rétablir, fiche désactivée, nouveau courriel (ADR-095)
\set ON_ERROR_STOP on
set client_min_messages = notice;
insert into auth.users(id, email) values ('00000000-0000-0000-0000-0000000000c2', 'autre@test.ca') on conflict do nothing;
insert into public.employes(id, auth_user_id, email, prenom, nom, role, succursale_code, fournisseur_id) values
  ('00000000-0000-0000-0000-0000000000c2', '00000000-0000-0000-0000-0000000000c2', 'autre@test.ca', 'Autre', 'ST', 'Sous-traitant', 'ST',
   'f2000000-0000-0000-0000-000000000002');
update public.fournisseurs set responsable_courriel = 'autre@test.ca' where id = 'f2000000-0000-0000-0000-000000000002';
select test.echec($$insert into public.employes(email, prenom, nom, role, succursale_code, fournisseur_id)
  values ('deux@test', 'Deux', 'ST', 'Sous-traitant', 'ST', 'f2000000-0000-0000-0000-000000000002')$$, 'un seul compte par sous-traitant', 'employes_un_compte_st');

set role authenticated;
-- Ni le sous-traitant ni un vendeur ne gèrent les accès
select test.comme('00000000-0000-0000-0000-0000000000c2');
select test.echec($$select public.hvac_st_acces_couper('f2000000-0000-0000-0000-000000000001')$$, 'un sous-traitant ne coupe pas d''accès', 'planification');
select test.comme('00000000-0000-0000-0000-00000000000c');
select test.echec($$select public.hvac_st_acces('f2000000-0000-0000-0000-000000000002')$$, 'un vendeur ne voit pas les accès', 'planification');

-- La planification envoie l'accès
select test.comme('00000000-0000-0000-0000-00000000000a');
select test.ok((select public.hvac_st_acces_envoyer('f2000000-0000-0000-0000-000000000002') = 'autre@test.ca'), 'envoi : rend le courriel du compte');
select test.ok((select (a->>'acces_envoye_le') is not null and (a->>'actif')::boolean and (a->>'connecte')::boolean
                  from public.hvac_st_acces('f2000000-0000-0000-0000-000000000002') a), 'état : envoyé, actif, connecté');

-- Couper : plus rien, sur-le-champ
select public.hvac_st_acces_couper('f2000000-0000-0000-0000-000000000002');
select test.comme('00000000-0000-0000-0000-0000000000c2');
select test.ok((select public.hvac_session() is null), 'accès coupé : plus de session');
select test.ok((select count(*) = 0 from public.fournisseurs), 'accès coupé : ne voit plus son entreprise');
select test.comme('00000000-0000-0000-0000-00000000000a');
select test.echec($$select public.hvac_st_acces_envoyer('f2000000-0000-0000-0000-000000000002')$$, 'pas d''envoi à un accès coupé', 'rétablis');
select public.hvac_st_acces_retablir('f2000000-0000-0000-0000-000000000002');
select test.comme('00000000-0000-0000-0000-0000000000c2');
select test.ok((select public.hvac_session()->>'fournisseur_id' = 'f2000000-0000-0000-0000-000000000002'), 'accès rétabli');

-- Sous-traitant désactivé : accès coupé aussi ; pas de rétablissement tant qu'il est inactif
select test.comme('00000000-0000-0000-0000-00000000000a');
update public.fournisseurs set actif = false where id = 'f2000000-0000-0000-0000-000000000002';
select test.ok((select not (a->>'actif')::boolean from public.hvac_st_acces('f2000000-0000-0000-0000-000000000002') a), 'fiche désactivée : accès coupé');
select test.echec($$select public.hvac_st_acces_retablir('f2000000-0000-0000-0000-000000000002')$$, 'pas de rétablissement si inactif', 'réactive');
update public.fournisseurs set actif = true where id = 'f2000000-0000-0000-0000-000000000002';
select public.hvac_st_acces_retablir('f2000000-0000-0000-0000-000000000002');

-- Nouveau responsable : le compte suit son courriel, l'ancienne personne n'entre plus
update public.fournisseurs set responsable_courriel = 'Nouveau@Test.ca' where id = 'f2000000-0000-0000-0000-000000000002';
select test.ok((select a->>'email' = 'nouveau@test.ca' and not (a->>'connecte')::boolean and a->>'acces_envoye_le' is null
                  from public.hvac_st_acces('f2000000-0000-0000-0000-000000000002') a), 'nouveau courriel : compte déplacé, lien défait');
select test.comme('00000000-0000-0000-0000-0000000000c2');
select test.ok((select public.hvac_session() is null), 'l''ancien responsable n''entre plus');

-- Partenariat (ADR-096) : depuis quand, compte créé, version active de la liste de prix
reset role;
update public.fournisseurs set partenaire_depuis = '2023-04-01' where id = 'f2000000-0000-0000-0000-000000000001';
set role authenticated;
select test.comme('00000000-0000-0000-0000-0000000000c1');
select test.ok((select p->>'partenaire_depuis' = '2023-04-01' and (p->>'version')::int = (select max(numero) from public.listes_prix_versions where fournisseur_id = 'f2000000-0000-0000-0000-000000000001')
                  from public.hvac_partenariat('f2000000-0000-0000-0000-000000000002') p), 'le sous-traitant voit SON partenariat (pas un autre) et sa version active');
select test.comme('00000000-0000-0000-0000-00000000000c');
select test.echec($$select public.hvac_partenariat('f2000000-0000-0000-0000-000000000001')$$, 'un vendeur ne voit pas le partenariat', 'introuvable');
select test.comme('00000000-0000-0000-0000-00000000000a');
select test.ok((select (p->>'version')::int >= 1 from public.hvac_partenariat('f2000000-0000-0000-0000-000000000001') p), 'Simon voit la version active');
-- Compte créé : inscrit à la première connexion du nouveau responsable
reset role;
insert into auth.users(id, email) values ('00000000-0000-0000-0000-0000000000c3', 'nouveau@test.ca');
set role authenticated;
select set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-0000-0000-0000000000c3', 'role', 'authenticated', 'email', 'nouveau@test.ca')::text, false);
select test.ok((select public.hvac_session()->>'fournisseur_id' = 'f2000000-0000-0000-0000-000000000002'), 'nouveau responsable : première connexion');
select test.ok((select (p->>'compte_cree_le')::timestamptz > now() - interval '1 minute' from public.hvac_partenariat() p), 'compte créé : date de la première connexion');
\echo 'TESTS ACCÈS DES SOUS-TRAITANTS PASSÉS'
