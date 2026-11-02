-- Fiche du sous-traitant (ADR-064)
\set ON_ERROR_STOP on
set client_min_messages = notice;
set role authenticated;

-- Simon modifie la fiche
select test.comme('00000000-0000-0000-0000-00000000000a');
update public.fournisseurs set responsable_nom = 'Jean Tremblay', responsable_telephone = '450-555-0100',
  responsable_courriel = 'jean@exemple.invalid', proprietaire_nom = 'Luc Gagnon', licence_rbq = '1234-5678-90'
 where id = 'f2000000-0000-0000-0000-000000000001';
select test.ok((select responsable_nom = 'Jean Tremblay' and proprietaire_nom = 'Luc Gagnon' from public.fournisseurs
                 where id = 'f2000000-0000-0000-0000-000000000001'), 'Simon modifie la fiche du sous-traitant');
select test.echec($$update public.fournisseurs set licence_rbq = '12345' where id = 'f2000000-0000-0000-0000-000000000001'$$,
                  'numéro RBQ mal formé refusé', 'licence_rbq');
select test.echec($$update public.fournisseurs set responsable_courriel = 'pas-un-courriel' where id = 'f2000000-0000-0000-0000-000000000001'$$,
                  'courriel du responsable mal formé refusé', 'responsable_courriel');

-- Un vendeur et le sous-traitant lui-même ne modifient pas la fiche (la RLS ignore la mise à jour)
select test.comme('00000000-0000-0000-0000-00000000000c');
update public.fournisseurs set proprietaire_nom = 'Pirate' where id = 'f2000000-0000-0000-0000-000000000001';
select test.comme('00000000-0000-0000-0000-0000000000c1');
update public.fournisseurs set proprietaire_nom = 'Pirate' where id = 'f2000000-0000-0000-0000-000000000001';
select test.comme('00000000-0000-0000-0000-00000000000a');
select test.ok((select proprietaire_nom = 'Luc Gagnon' from public.fournisseurs where id = 'f2000000-0000-0000-0000-000000000001'),
               'vendeur et sous-traitant ne modifient pas la fiche');
reset role;
select test.ok((select count(*) > 0 from public.journal_audit where table_nom = 'fournisseurs' and action = 'update' and apres->>'proprietaire_nom' = 'Luc Gagnon'), 'modification de la fiche journalisée');
\echo 'TESTS FICHE SOUS-TRAITANT PASSÉS'
