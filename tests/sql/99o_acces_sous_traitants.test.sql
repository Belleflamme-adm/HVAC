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
\echo 'TESTS ACCÈS DES SOUS-TRAITANTS PASSÉS'
