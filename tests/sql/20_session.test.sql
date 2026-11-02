-- Tests des RPC de session (suite de 10_phase1 : réutilise le schéma test et ses données).
\set ON_ERROR_STOP on
set client_min_messages = notice;

-- Un employé créé d'avance, sans compte lié, se connecte pour la première fois
insert into public.employes(id, email, prenom, nom, role, succursale_code)
  values ('00000000-0000-0000-0000-000000000099', 'Nouveau@Test', 'Nouveau', 'Vendeur', 'Vendeur', 'ST');
insert into auth.users(id, email) values ('00000000-0000-0000-0000-0000000000aa', 'nouveau@test');

set role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000aa","email":"nouveau@test","role":"authenticated"}', false);
select test.ok((select public.hvac_session() ->> 'id' = '00000000-0000-0000-0000-000000000099'),
               'premier login : compte lié à la fiche par courriel (insensible à la casse)');
select test.ok((select public.hvac_session() ->> 'role' = 'Vendeur'), 'session : rôle retourné');
select test.echec($$select public.hvac_impersonation('00000000-0000-0000-0000-00000000000c')$$,
                  'un vendeur ne peut pas impersonner', 'réservée');

-- Compte Auth sans fiche employé : aucune session
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000bb","email":"inconnu@test"}', false);
select test.ok((select public.hvac_session() is null), 'compte sans fiche employé : aucune session');

-- Admin tout impersonne un vendeur : journalisé
select test.comme('00000000-0000-0000-0000-00000000000a');
select test.ok((select public.hvac_impersonation('00000000-0000-0000-0000-00000000000c') ->> 'email' = 'vro@test'),
               'Admin tout peut impersonner');
reset role;
select test.ok((select count(*) = 1 from public.journal_audit where action = 'impersonation'), 'impersonation journalisée');

reset request.jwt.claims;
set role anon;
select test.echec($$select public.hvac_session()$$, 'anon ne peut pas appeler hvac_session', 'permission denied');
reset role;

\echo 'TESTS SESSION PASSÉS'
