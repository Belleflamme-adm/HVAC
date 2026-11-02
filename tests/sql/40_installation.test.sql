-- Installation : coût du sous-traitant + marge sur le prix de vente.
\set ON_ERROR_STOP on
set client_min_messages = notice;

insert into public.fournisseurs(id, nom, type) values ('f1000000-0000-0000-0000-000000000001','ST Test','sous-traitant');
insert into public.types_travaux(id, code, nom) values ('71000000-0000-0000-0000-000000000001','INST-MUR','Installation murale');
insert into public.tarifs_sous_traitants(fournisseur_id, type_travail_id, cout_cents, en_vigueur_du) values
  ('f1000000-0000-0000-0000-000000000001','71000000-0000-0000-0000-000000000001', 90000, '2020-01-01'),
  ('f1000000-0000-0000-0000-000000000001','71000000-0000-0000-0000-000000000001',100000, current_date);

select test.ok((select app.prix_avec_marge(100000, 3000) = 142857), 'marge 30 % sur 1 000 $ : prix 1 428,57 $ (et non 1 300 $)');
select test.ok((select public.hvac_cout_installation('f1000000-0000-0000-0000-000000000001','71000000-0000-0000-0000-000000000001') = 100000),
               'grille : le tarif le plus récent en vigueur');
select test.echec($$update public.tarifs_sous_traitants set cout_cents = 1$$, 'modifier un tarif (on en ajoute un nouveau)');

insert into public.devis(id, succursale_code, client_id, vendeur_id) values
  ('42000000-0000-0000-0000-000000000001','RO','30000000-0000-0000-0000-000000000003','00000000-0000-0000-0000-00000000000c');

-- Grille
insert into public.devis_lignes(id, devis_id, type_ligne, type_travail_id, sous_traitant_id, description, prix_unitaire_cents, cout_cents, marge_bp)
  values ('52000000-0000-0000-0000-000000000001','42000000-0000-0000-0000-000000000001','installation',
          '71000000-0000-0000-0000-000000000001','f1000000-0000-0000-0000-000000000001','Installation murale', 1, 1, 9000);
select test.ok((select cout_cents = 100000 and marge_bp = 2500 and prix_unitaire_cents = 133333 and source_cout = 'grille'
                  from public.devis_lignes where id = '52000000-0000-0000-0000-000000000001'),
               'grille : coût 1 000 $, marge par défaut 25 %, prix 1 333,33 $, imposés par la base');

-- Marge figée sur la ligne
update public.parametres set valeur = '3500' where cle = 'marge_installation_bp';
update public.devis_lignes set quantite = 2, marge_bp = 100 where id = '52000000-0000-0000-0000-000000000001';
select test.ok((select marge_bp = 2500 and montant_cents = 266666 from public.devis_lignes where id = '52000000-0000-0000-0000-000000000001'),
               'changer la marge globale ne touche pas une ligne existante ; le vendeur ne peut pas la changer');
update public.parametres set valeur = '2500' where cle = 'marge_installation_bp';

-- Rabais sur l'installation : approbation obligatoire
update public.devis_lignes set rabais_bp = 1 where id = '52000000-0000-0000-0000-000000000001';
select test.ok((select approbation_requise and plafond_bp = 0 from public.devis_lignes where id = '52000000-0000-0000-0000-000000000001'),
               'installation : tout rabais demande l''approbation de Simon ou Mike');

-- Soumission propre au job
select test.echec($$insert into public.devis_lignes(devis_id, type_ligne, type_travail_id, sous_traitant_id, description, prix_unitaire_cents, source_cout, cout_cents)
                    values ('42000000-0000-0000-0000-000000000001','installation','71000000-0000-0000-0000-000000000001','f1000000-0000-0000-0000-000000000001','X', 0, 'soumission', 50000)$$,
                  'soumission sans référence', 'référence');
select test.echec($$insert into public.devis_lignes(devis_id, type_ligne, type_travail_id, description, prix_unitaire_cents, source_cout, cout_cents, reference_soumission)
                    values ('42000000-0000-0000-0000-000000000001','installation','71000000-0000-0000-0000-000000000001','X', 0, 'soumission', 50000, 'S-1')$$,
                  'soumission sans sous-traitant (installation par sous-traitants seulement)', 'installation_chk');
insert into public.devis_lignes(id, devis_id, type_ligne, type_travail_id, sous_traitant_id, description, prix_unitaire_cents, source_cout, cout_cents, reference_soumission)
  values ('52000000-0000-0000-0000-000000000002','42000000-0000-0000-0000-000000000001','installation','71000000-0000-0000-0000-000000000001',
          'f1000000-0000-0000-0000-000000000001','Installation sur toit plat', 0, 'soumission', 175000, 'ST-2026-118');
select test.ok((select prix_unitaire_cents = 233333 from public.devis_lignes where id = '52000000-0000-0000-0000-000000000002'),
               'soumission 1 750 $ avec marge 25 % = 2 333,33 $');

-- Sans grille ni soumission
select test.echec($$insert into public.devis_lignes(devis_id, type_ligne, type_travail_id, sous_traitant_id, description, prix_unitaire_cents)
                    values ('42000000-0000-0000-0000-000000000001','installation','71000000-0000-0000-0000-000000000001','f0000000-0000-0000-0000-000000000099','X', 0)$$,
                  'installation sans prix dans la grille');

-- Les techniciens ne voient pas les coûts des sous-traitants
set role authenticated;
select test.comme('00000000-0000-0000-0000-00000000000e');
select test.ok((select count(*) = 0 from public.tarifs_sous_traitants), 'technicien : aucun accès à la grille des sous-traitants');
select test.comme('00000000-0000-0000-0000-00000000000c');
select test.ok((select count(*) = 2 from public.tarifs_sous_traitants), 'vendeur : lit la grille');
select test.echec($$insert into public.tarifs_sous_traitants(fournisseur_id, type_travail_id, cout_cents)
                    values ('f1000000-0000-0000-0000-000000000001','71000000-0000-0000-0000-000000000001', 1)$$,
                  'vendeur : ne modifie pas la grille');
update public.parametres set valeur = '0' where cle = 'marge_installation_bp';
select test.ok((select app.marge_installation_bp() = 2500), 'vendeur : ne change pas la marge (RLS, mise à jour ignorée)');
reset role;
reset request.jwt.claims;

\echo 'TESTS INSTALLATION PASSÉS'
