-- Données de DÉMONSTRATION. Tout est fictif : clients, adresses, téléphones, marques, prix.
-- Les marques sont inventées pour qu'aucun prix ne soit confondu avec un vrai prix fournisseur.
-- Les vrais kits de thermopompes de Mike remplaceront ces kits quand l'accès Monday sera réglé (ADR-017).
--
-- Comptes : chaque employé se connecte avec un compte Supabase Auth créé par Simon
-- (Dashboard > Authentication > Invite). Au premier login, le compte est lié à la fiche
-- par courriel (public.hvac_session). Remplacer les courriels @exemple.invalid par les vrais
-- AVANT d'inviter les gens.

-- Employés ------------------------------------------------------------------
insert into public.employes (id, email, prenom, nom, role, succursale_code, peut_approuver_rabais) values
  ('e0000000-0000-0000-0000-000000000001', 'simon.cardinal@exemple.invalid', 'Simon', 'Cardinal', 'Admin tout', 'HO', true),
  ('e0000000-0000-0000-0000-000000000002', 'mike.maisonneuve@exemple.invalid', 'Mike', 'Maisonneuve', 'Admin tout', 'HO', true),
  ('e0000000-0000-0000-0000-000000000003', 'vendeur.ro@exemple.invalid', 'Annie', 'Lavoie (FICTIF)', 'Vendeur', 'RO', false),
  ('e0000000-0000-0000-0000-000000000004', 'vendeur.st@exemple.invalid', 'Jérôme', 'Bélanger (FICTIF)', 'Vendeur', 'ST', false),
  ('e0000000-0000-0000-0000-000000000005', 'vendeur.ga@exemple.invalid', 'Karine', 'Lefebvre (FICTIF)', 'Vendeur', 'GA', false),
  ('e0000000-0000-0000-0000-000000000006', 'gerant.dr@exemple.invalid', 'Patrick', 'Côté (FICTIF)', 'Gérant de succursale', 'DR', false),
  ('e0000000-0000-0000-0000-000000000007', 'coord@exemple.invalid', 'Sophie', 'Gauthier (FICTIF)', 'Coordonnateur', 'HO', false),
  ('e0000000-0000-0000-0000-000000000008', 'tech1@exemple.invalid', 'Maxime', 'Pelletier (FICTIF)', 'Technicien', 'RO', false),
  ('e0000000-0000-0000-0000-000000000009', 'tech2@exemple.invalid', 'Olivier', 'Bouchard (FICTIF)', 'Technicien', 'ST', false),
  ('e0000000-0000-0000-0000-000000000010', 'compta@exemple.invalid', 'Nathalie', 'Morin (FICTIF)', 'Comptabilité', 'HO', false);

insert into public.employe_succursales (employe_id, succursale_code) values
  ('e0000000-0000-0000-0000-000000000004', 'HO'),   -- vendeur de St-Sauveur couvre aussi Saint-Jérôme
  ('e0000000-0000-0000-0000-000000000007', 'RO'),
  ('e0000000-0000-0000-0000-000000000007', 'ST');

insert into public.certifications (employe_id, type, numero, emise_le, expire_le) values
  ('e0000000-0000-0000-0000-000000000008', 'halocarbures', 'FICTIF-H-1001', '2024-03-01', '2029-03-01'),
  ('e0000000-0000-0000-0000-000000000009', 'halocarbures', 'FICTIF-H-1002', '2021-05-15', '2026-05-15');  -- expirée : affichée, non bloquante

-- Fournisseurs et sous-traitants -------------------------------------------
insert into public.fournisseurs (id, nom, type, telephone) values
  ('f0000000-0000-0000-0000-000000000001', 'Distribution Boréal (FICTIF)', 'fournisseur', '450 555-0101'),
  ('f0000000-0000-0000-0000-000000000002', 'Nordika Canada (FICTIF)', 'fournisseur', '514 555-0102'),
  ('f0000000-0000-0000-0000-000000000003', 'Réfrigération Laurentides (FICTIF)', 'sous-traitant', '450 555-0103');

-- Compte limité du sous-traitant de démo (Lot A) : territoire et disponibilités seulement.
-- Son territoire se remplit une fois les limites municipales officielles chargées.
insert into public.employes (id, email, prenom, nom, role, succursale_code, fournisseur_id) values
  ('e0000000-0000-0000-0000-000000000011', 'st.laurentides@exemple.invalid', 'Éric', 'Paquette (FICTIF)', 'Sous-traitant', 'HO',
   'f0000000-0000-0000-0000-000000000003');

insert into public.marques (id, nom, fournisseur_id, escompte_fournisseur_bp, plafond_rabais_exception_bp) values
  ('a1000000-0000-0000-0000-000000000001', 'Boréal Climat (FICTIF)', 'f0000000-0000-0000-0000-000000000001', 4000, null),  -- plafond 5 %
  ('a1000000-0000-0000-0000-000000000002', 'Nordika (FICTIF)',       'f0000000-0000-0000-0000-000000000002', 4500, 800),   -- exception : 8 %
  ('a1000000-0000-0000-0000-000000000003', 'Ventimax (FICTIF)',      'f0000000-0000-0000-0000-000000000001', 3500, null);  -- plafond 0 %

-- Produits ------------------------------------------------------------------
insert into public.produits (id, sku, marque_id, nom, categorie, modele, ahri, energy_star, btu_nominal, btu_moins8,
                             climat_froid, logisvert_admissible, cout_cents, prix_cents, fictif) values
  ('b1000000-0000-0000-0000-000000000001','BOR-TPM-12','a1000000-0000-0000-0000-000000000001','Thermopompe murale 12 000 BTU climat froid','thermopompe_murale','BOR-12CF','FIC0000012','9000012',12000,10900,true,true, 180000, 300000,true),
  ('b1000000-0000-0000-0000-000000000002','BOR-TPM-18','a1000000-0000-0000-0000-000000000001','Thermopompe murale 18 000 BTU climat froid','thermopompe_murale','BOR-18CF','FIC0000018','9000018',18000,16400,true,true, 222000, 370000,true),
  ('b1000000-0000-0000-0000-000000000003','BOR-TPM-24','a1000000-0000-0000-0000-000000000001','Thermopompe murale 24 000 BTU climat froid','thermopompe_murale','BOR-24CF','FIC0000024','9000024',24000,20200,true,true, 270000, 450000,true),
  ('b1000000-0000-0000-0000-000000000004','NOR-TPC-36','a1000000-0000-0000-0000-000000000002','Thermopompe centrale 36 000 BTU','thermopompe_centrale','NOR-36C','FIC0000036','9000036',36000,29000,true,true, 495000, 900000,true),
  ('b1000000-0000-0000-0000-000000000005','NOR-FRN-60','a1000000-0000-0000-0000-000000000002','Fournaise électrique 20 kW','fournaise','NOR-F20',null,null,null,null,false,false, 132000, 240000,true),
  ('b1000000-0000-0000-0000-000000000006','VMX-ECH-150','a1000000-0000-0000-0000-000000000003','Échangeur d''air VRC 150 PCM','echangeur_air','VMX-150',null,null,null,null,false,false, 97500, 150000,true),
  ('b1000000-0000-0000-0000-000000000007','VMX-SUP-MUR','a1000000-0000-0000-0000-000000000003','Support mural et base antivibration','accessoire',null,null,null,null,null,false,false, 6500, 10000,true),
  ('b1000000-0000-0000-0000-000000000008','VMX-LIN-25','a1000000-0000-0000-0000-000000000003','Ensemble de lignes frigorifiques 25 pi','conduit',null,null,null,null,null,false,false, 16250, 25000,true);

-- Installation : coût du sous-traitant + marge (le prix n'est pas dans le catalogue)
insert into public.types_travaux (id, code, nom, description) values
  ('a2000000-0000-0000-0000-000000000001','INST-MUR','Installation thermopompe murale','Unité murale, lignes jusqu''à 25 pi, support'),
  ('a2000000-0000-0000-0000-000000000002','INST-CENT','Installation thermopompe centrale','Raccord à la fournaise existante, serpentin'),
  ('a2000000-0000-0000-0000-000000000003','INST-ECH','Installation échangeur d''air','VRC, conduits et sorties');

insert into public.tarifs_sous_traitants (fournisseur_id, type_travail_id, cout_cents, en_vigueur_du, notes) values
  ('f0000000-0000-0000-0000-000000000003','a2000000-0000-0000-0000-000000000001', 65000, '2026-01-01', 'Grille FICTIVE'),
  ('f0000000-0000-0000-0000-000000000003','a2000000-0000-0000-0000-000000000002',180000, '2026-01-01', 'Grille FICTIVE'),
  ('f0000000-0000-0000-0000-000000000003','a2000000-0000-0000-0000-000000000003', 90000, '2026-01-01', 'Grille FICTIVE');

insert into public.kits (id, code, nom, description, fictif) values
  ('c1000000-0000-0000-0000-000000000001','KIT-TPM-12','Kit thermopompe murale 12 000 BTU','Unité, support, lignes 25 pi (installation en sus)',true),
  ('c1000000-0000-0000-0000-000000000002','KIT-TPM-24','Kit thermopompe murale 24 000 BTU','Unité, support, lignes 25 pi (installation en sus)',true);

insert into public.kit_items (kit_id, produit_id, quantite) values
  ('c1000000-0000-0000-0000-000000000001','b1000000-0000-0000-0000-000000000001',1),
  ('c1000000-0000-0000-0000-000000000001','b1000000-0000-0000-0000-000000000007',1),
  ('c1000000-0000-0000-0000-000000000001','b1000000-0000-0000-0000-000000000008',1),
  ('c1000000-0000-0000-0000-000000000002','b1000000-0000-0000-0000-000000000003',1),
  ('c1000000-0000-0000-0000-000000000002','b1000000-0000-0000-0000-000000000007',1),
  ('c1000000-0000-0000-0000-000000000002','b1000000-0000-0000-0000-000000000008',1);


-- Clients (FICTIFS) ---------------------------------------------------------
insert into public.clients (id, prenom, nom, courriel, telephone, succursale_code, vendeur_id, est_proprietaire, nom_preuve_propriete) values
  ('d1000000-0000-0000-0000-000000000001','Julie','Tremblay','julie.tremblay@exemple.invalid','450 555-0201','RO','e0000000-0000-0000-0000-000000000003',true,'Julie Tremblay'),
  ('d1000000-0000-0000-0000-000000000002','Marc','Gagnon','marc.gagnon@exemple.invalid','450 555-0202','RO','e0000000-0000-0000-0000-000000000003',true,'Marc Gagnon'),
  ('d1000000-0000-0000-0000-000000000003','Isabelle','Roy','isabelle.roy@exemple.invalid','450 555-0203','ST','e0000000-0000-0000-0000-000000000004',true,'Isabelle Roy'),
  ('d1000000-0000-0000-0000-000000000004','Denis','Fortin','denis.fortin@exemple.invalid','819 555-0204','GA','e0000000-0000-0000-0000-000000000005',true,'Denis Fortin'),
  ('d1000000-0000-0000-0000-000000000005','Chantal','Girard','chantal.girard@exemple.invalid','819 555-0205','DR','e0000000-0000-0000-0000-000000000006',false,null),
  ('d1000000-0000-0000-0000-000000000006','Luc','Bergeron','luc.bergeron@exemple.invalid','450 555-0206','HO','e0000000-0000-0000-0000-000000000004',true,'Luc Bergeron');

insert into public.sites (id, client_id, adresse, ville, code_postal, type_habitation, annee_construction) values
  ('d2000000-0000-0000-0000-000000000001','d1000000-0000-0000-0000-000000000001','100, rue des Érables (FICTIF)','Rosemère','J7A 0A1','maison',1988),
  ('d2000000-0000-0000-0000-000000000002','d1000000-0000-0000-0000-000000000002','200, boulevard du Lac (FICTIF)','Rosemère','J7A 0A2','maison',2003),
  ('d2000000-0000-0000-0000-000000000003','d1000000-0000-0000-0000-000000000003','300, chemin des Pins (FICTIF)','Saint-Sauveur','J0R 0A3','maison',1975),
  ('d2000000-0000-0000-0000-000000000004','d1000000-0000-0000-0000-000000000004','400, rue Principale (FICTIF)','Gatineau','J8T 0A4','condo',2015),
  ('d2000000-0000-0000-0000-000000000005','d1000000-0000-0000-0000-000000000005','500, rue Lindsay (FICTIF)','Drummondville','J2B 0A5','multiplex',1962),
  ('d2000000-0000-0000-0000-000000000006','d1000000-0000-0000-0000-000000000006','600, rue de Martigny (FICTIF)','Saint-Jérôme','J7Y 0A6','maison',1999);

insert into public.leads (succursale_code, source, statut, client_id, contact_nom, besoin, assigne_a) values
  ('RO','site_web','qualifie','d1000000-0000-0000-0000-000000000002','Marc Gagnon','Thermopompe centrale, maison de 2003','e0000000-0000-0000-0000-000000000003'),
  ('ST','facebook','nouveau',null,'Prospect FICTIF','Climatiseur pour chalet','e0000000-0000-0000-0000-000000000004'),
  ('GA','telephone','contacte','d1000000-0000-0000-0000-000000000004','Denis Fortin','Remplacement plinthes par thermopompe murale','e0000000-0000-0000-0000-000000000005');

insert into public.inspections (succursale_code, client_id, site_id, inspecteur_id, prevue_le, realisee_le, statut, donnees) values
  ('RO','d1000000-0000-0000-0000-000000000001','d2000000-0000-0000-0000-000000000001','e0000000-0000-0000-0000-000000000003',
   now() - interval '10 days', now() - interval '10 days', 'realisee',
   '{"superficie_pi2": 1400, "panneau_amperes": 200, "emplacement_unite_ext": "côté cour", "notes": "FICTIF"}');

-- Devis : vrais numéros (séquence réelle), données fictives ------------------
insert into public.devis (id, succursale_code, client_id, site_id, vendeur_id, notes_client) values
  ('d3000000-0000-0000-0000-000000000001','RO','d1000000-0000-0000-0000-000000000001','d2000000-0000-0000-0000-000000000001',
   'e0000000-0000-0000-0000-000000000003','Démo : thermopompe murale 24 000 BTU installée');
insert into public.devis_lignes (devis_id, position, produit_id, description, quantite, prix_unitaire_cents, rabais_bp) values
  ('d3000000-0000-0000-0000-000000000001',1,'b1000000-0000-0000-0000-000000000003','Thermopompe murale 24 000 BTU climat froid',1,450000,500),
  ('d3000000-0000-0000-0000-000000000001',2,'b1000000-0000-0000-0000-000000000007','Support mural',1,10000,0),
  ('d3000000-0000-0000-0000-000000000001',3,'b1000000-0000-0000-0000-000000000008','Lignes frigorifiques 25 pi',1,25000,0);
insert into public.devis_lignes (devis_id, position, type_ligne, type_travail_id, sous_traitant_id, description, quantite, prix_unitaire_cents) values
  ('d3000000-0000-0000-0000-000000000001',4,'installation','a2000000-0000-0000-0000-000000000001','f0000000-0000-0000-0000-000000000003',
   'Installation thermopompe murale',1,0);
-- Le devis s'appuie sur la visite de pré-installation du vendeur (ADR-049)
update public.devis set inspection_id = (select id from public.inspections where client_id = 'd1000000-0000-0000-0000-000000000001' limit 1)
 where id = 'd3000000-0000-0000-0000-000000000001';
update public.devis set statut = 'envoye' where id = 'd3000000-0000-0000-0000-000000000001';
update public.devis set statut = 'accepte' where id = 'd3000000-0000-0000-0000-000000000001';

insert into public.devis (id, succursale_code, client_id, site_id, vendeur_id, notes_client) values
  ('d3000000-0000-0000-0000-000000000002','RO','d1000000-0000-0000-0000-000000000002','d2000000-0000-0000-0000-000000000002',
   'e0000000-0000-0000-0000-000000000003','Démo : centrale 36 000 BTU, rabais à approuver');
insert into public.devis_lignes (devis_id, position, produit_id, description, quantite, prix_unitaire_cents, rabais_bp) values
  ('d3000000-0000-0000-0000-000000000002',1,'b1000000-0000-0000-0000-000000000004','Thermopompe centrale 36 000 BTU',1,900000,1000);  -- 10 % > plafond 8 %

-- Projet, BT (brouillon) et BC (brouillons) : créés automatiquement à l'acceptation du devis 1.
-- Le BT reste « à planifier » : la date se place dans une journée disponible du sous-traitant.
insert into public.subventions (succursale_code, client_id, projet_id, mode_depot, montant_estime_cents) values
  ('RO','d1000000-0000-0000-0000-000000000001',(select id from public.projets where devis_id = 'd3000000-0000-0000-0000-000000000001'),'client', 242400);

-- Facture de dépôt 40 % émise et payée --------------------------------------
insert into public.factures (id, type, succursale_code, client_id, projet_id, devis_id) values
  ('d5000000-0000-0000-0000-000000000001','depot','RO','d1000000-0000-0000-0000-000000000001',
   (select id from public.projets where devis_id = 'd3000000-0000-0000-0000-000000000001'),'d3000000-0000-0000-0000-000000000001');
insert into public.facture_lignes (facture_id, description, prix_unitaire_cents)
  select 'd5000000-0000-0000-0000-000000000001', 'Dépôt 40 % sur devis ' || numero,
         round(sous_total_cents * 0.4)::bigint
    from public.devis where id = 'd3000000-0000-0000-0000-000000000001';
update public.factures set statut = 'emise' where id = 'd5000000-0000-0000-0000-000000000001';
insert into public.paiements (facture_id, montant_cents, mode, reference)
  select id, total_cents, 'carte', 'FICTIF-0001' from public.factures where id = 'd5000000-0000-0000-0000-000000000001';

-- Contrat d'entretien annuel -------------------------------------------------
insert into public.contrats_entretien (succursale_code, client_id, site_id, debut, prochain_entretien, prix_cents) values
  ('ST','d1000000-0000-0000-0000-000000000003','d2000000-0000-0000-0000-000000000003', current_date - 300, current_date + 65, 18900);
