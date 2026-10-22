-- Lot A : sous-traitants, territoires, principal, disponibilités, supplément de ville.
\set ON_ERROR_STOP on
set client_min_messages = notice;

insert into public.municipalites(code, nom, mrc, region) values
  ('T0001','Villeaccepte (TEST)','MRC Test','Laurentides'),
  ('T0002','Villesupplement (TEST)','MRC Test','Laurentides'),
  ('T0003','Villerefus (TEST)','MRC Test','Laurentides');
insert into public.fournisseurs(id, nom, type) values
  ('f2000000-0000-0000-0000-000000000001','ST Laurentides (TEST)','sous-traitant'),
  ('f2000000-0000-0000-0000-000000000002','ST Autre (TEST)','sous-traitant');
insert into auth.users(id, email) values ('00000000-0000-0000-0000-0000000000c1','st@test');
insert into public.employes(id, auth_user_id, email, prenom, nom, role, succursale_code, fournisseur_id) values
  ('00000000-0000-0000-0000-0000000000c1','00000000-0000-0000-0000-0000000000c1','st@test','Sous','Traitant','Sous-traitant','ST',
   'f2000000-0000-0000-0000-000000000001');
select test.echec($$insert into public.employes(email, prenom, nom, role, succursale_code) values ('x@test','X','Y','Sous-traitant','ST')$$,
                  'compte sous-traitant sans fournisseur');
insert into public.tarifs_sous_traitants(fournisseur_id, type_travail_id, cout_cents, en_vigueur_du) values
  ('f2000000-0000-0000-0000-000000000001','71000000-0000-0000-0000-000000000001', 60000, '2020-01-01'),
  ('f2000000-0000-0000-0000-000000000002','71000000-0000-0000-0000-000000000001', 70000, '2020-01-01');

-- Ce que voit un sous-traitant
set role authenticated;
select test.comme('00000000-0000-0000-0000-0000000000c1');
select test.ok((select count(*) = 1 from public.employes), 'sous-traitant : voit seulement sa propre fiche employé');
select test.ok((select count(*) = 1 from public.fournisseurs), 'sous-traitant : voit seulement son entreprise');
select test.ok((select count(*) = 0 from public.produits), 'sous-traitant : aucun produit ni coût');
select test.ok((select count(*) = 0 from public.parametres), 'sous-traitant : ne voit pas la marge');
select test.ok((select count(*) = 0 from public.clients), 'sous-traitant : aucun client');
select test.ok((select count(*) = 0 from public.devis), 'sous-traitant : aucun devis');
select test.ok((select count(*) = 1 from public.tarifs_sous_traitants), 'sous-traitant : voit seulement sa grille');
select test.ok((select count(*) = 3 from public.municipalites where code like 'T%'), 'sous-traitant : voit les municipalités');

-- Il remplit son territoire
insert into public.territoires_sous_traitants(fournisseur_id, municipalite_code, statut, supplement_cents) values
  ('f2000000-0000-0000-0000-000000000001','T0001','accepte', null),
  ('f2000000-0000-0000-0000-000000000001','T0002','supplement', 15000),
  ('f2000000-0000-0000-0000-000000000001','T0003','refuse', null);
select test.ok((select count(*) = 3 from public.territoires_sous_traitants), 'sous-traitant : remplit son territoire');
select test.echec($$insert into public.territoires_sous_traitants(fournisseur_id, municipalite_code, statut)
                    values ('f2000000-0000-0000-0000-000000000002','T0001','accepte')$$, 'sous-traitant : territoire d''un autre');
select test.echec($$update public.territoires_sous_traitants set supplement_cents = null where municipalite_code = 'T0002'$$,
                  'supplément sans montant');
select test.echec($$insert into public.principaux_municipalites(municipalite_code, fournisseur_id) values ('T0001','f2000000-0000-0000-0000-000000000001')$$,
                  'sous-traitant : se désigner principal');

-- Disponibilités
insert into public.disponibilites_sous_traitants(fournisseur_id, jour, statut) values
  ('f2000000-0000-0000-0000-000000000001', '2026-11-20', 'disponible'),
  ('f2000000-0000-0000-0000-000000000001', '2026-11-21', 'indisponible');
select test.ok((select count(*) = 2 from public.disponibilites_sous_traitants), 'sous-traitant : inscrit ses disponibilités');
select test.echec($$insert into public.disponibilites_sous_traitants(fournisseur_id, jour, statut) values ('f2000000-0000-0000-0000-000000000002','2026-11-20','disponible')$$,
                  'sous-traitant : disponibilités d''un autre');

-- Vendeur : lit, n'écrit pas
select test.comme('00000000-0000-0000-0000-00000000000c');
select test.ok((select count(*) = 2 from public.disponibilites_sous_traitants), 'vendeur : lit les disponibilités');
select test.echec($$insert into public.disponibilites_sous_traitants(fournisseur_id, jour, statut) values ('f2000000-0000-0000-0000-000000000001','2026-11-22','disponible')$$,
                  'vendeur : n''inscrit pas les disponibilités d''un sous-traitant');
select test.ok((select count(*) = 1 from public.hvac_sous_traitants_pour('T0002')), 'liste des sous-traitants qui desservent une ville');
select test.ok((select supplement_cents = 15000 from public.hvac_sous_traitants_pour('T0002')), 'ville avec supplément : 150 $');
select test.ok((select count(*) = 0 from public.hvac_sous_traitants_pour('T0003')), 'ville refusée : aucun sous-traitant');

-- Principal (Simon)
select test.comme('00000000-0000-0000-0000-00000000000a');
insert into public.principaux_municipalites(municipalite_code, fournisseur_id) values ('T0001','f2000000-0000-0000-0000-000000000001');
select test.ok((select principal from public.hvac_sous_traitants_pour('T0001')), 'Simon désigne le sous-traitant principal');
select test.echec($$insert into public.principaux_municipalites(municipalite_code, fournisseur_id) values ('T0003','f2000000-0000-0000-0000-000000000001')$$,
                  'principal dans une ville qu''il refuse', 'ne dessert pas');
reset role;
reset request.jwt.claims;

-- Le principal refuse ensuite la ville : la ville n'a plus de principal
update public.territoires_sous_traitants set statut = 'refuse' where municipalite_code = 'T0001';
select test.ok((select fournisseur_id is null from public.principaux_municipalites where municipalite_code = 'T0001'),
               'le principal refuse la ville : principal retiré, à redésigner');

-- Supplément dans le prix de l'installation : (coût + supplément) / (1 - marge)
insert into public.sites(id, client_id, adresse, ville, municipalite_code) values
  ('d9000000-0000-0000-0000-000000000002','30000000-0000-0000-0000-000000000003','1 rue Test','Villesupplement','T0002'),
  ('d9000000-0000-0000-0000-000000000003','30000000-0000-0000-0000-000000000003','2 rue Test','Villerefus','T0003');
insert into public.devis(id, succursale_code, client_id, site_id, vendeur_id) values
  ('45000000-0000-0000-0000-000000000002','RO','30000000-0000-0000-0000-000000000003','d9000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-00000000000c'),
  ('45000000-0000-0000-0000-000000000003','RO','30000000-0000-0000-0000-000000000003','d9000000-0000-0000-0000-000000000003','00000000-0000-0000-0000-00000000000c');
insert into public.devis_lignes(id, devis_id, type_ligne, type_travail_id, sous_traitant_id, description, prix_unitaire_cents) values
  ('55000000-0000-0000-0000-000000000002','45000000-0000-0000-0000-000000000002','installation','71000000-0000-0000-0000-000000000001',
   'f2000000-0000-0000-0000-000000000001','Installation murale', 0);
select test.ok((select cout_cents = 60000 and supplement_cents = 15000 and prix_unitaire_cents = 100000
                  from public.devis_lignes where id = '55000000-0000-0000-0000-000000000002'),
               'installation : (600 $ + supplément 150 $) avec marge 25 % = 1 000 $');
select test.echec($$insert into public.devis_lignes(devis_id, type_ligne, type_travail_id, sous_traitant_id, description, prix_unitaire_cents)
                    values ('45000000-0000-0000-0000-000000000003','installation','71000000-0000-0000-0000-000000000001','f2000000-0000-0000-0000-000000000001','X', 0)$$,
                  'installation par un sous-traitant qui refuse la ville', 'ne dessert pas');

\echo 'TESTS SOUS-TRAITANTS PASSÉS'
