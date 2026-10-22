-- Tests du schéma Phase 1. Exécutés par tests/sql/run.sh sur une base jetable.
\set ON_ERROR_STOP on
set client_min_messages = notice;

create schema test;
create function test.ok(p boolean, p_msg text) returns void language plpgsql as $$
begin
  if p is not true then raise exception 'ÉCHEC : %', p_msg; end if;
  raise notice 'ok | %', p_msg;
end $$;
create function test.echec(p_sql text, p_msg text, p_attendu text default null) returns void language plpgsql as $$
begin
  begin
    execute p_sql;
  exception when others then
    if p_attendu is not null and position(p_attendu in sqlerrm) = 0 then
      raise exception 'ÉCHEC : % (mauvaise erreur : %)', p_msg, sqlerrm;
    end if;
    raise notice 'ok | % (refusé : %)', p_msg, sqlerrm;
    return;
  end;
  raise exception 'ÉCHEC : % (aurait dû être refusé)', p_msg;
end $$;
create function test.comme(p_uid uuid) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated')::text, false)
$$;
grant usage on schema test to authenticated, anon;
grant execute on all functions in schema test to authenticated, anon;

-- ---------------------------------------------------------------------------
-- Données de test (superutilisateur : contourne la RLS)
-- ---------------------------------------------------------------------------
insert into auth.users(id, email) values
  ('00000000-0000-0000-0000-00000000000a','simon@test'),('00000000-0000-0000-0000-00000000000b','mike@test'),
  ('00000000-0000-0000-0000-00000000000c','vro@test'),('00000000-0000-0000-0000-00000000000d','vga@test'),
  ('00000000-0000-0000-0000-00000000000e','tech@test'),('00000000-0000-0000-0000-00000000000f','compta@test');

insert into public.employes(id, auth_user_id, email, prenom, nom, role, succursale_code, peut_approuver_rabais) values
  ('00000000-0000-0000-0000-00000000000a','00000000-0000-0000-0000-00000000000a','simon@test','Simon','Cardinal','Admin tout','HO',true),
  ('00000000-0000-0000-0000-00000000000b','00000000-0000-0000-0000-00000000000b','mike@test','Mike','Maisonneuve','Admin tout','HO',true),
  ('00000000-0000-0000-0000-00000000000c','00000000-0000-0000-0000-00000000000c','vro@test','Vendeur','Rosemère','Vendeur','RO',false),
  ('00000000-0000-0000-0000-00000000000d','00000000-0000-0000-0000-00000000000d','vga@test','Vendeur','Gatineau','Vendeur','GA',false),
  ('00000000-0000-0000-0000-00000000000e','00000000-0000-0000-0000-00000000000e','tech@test','Tech','Rosemère','Technicien','RO',false),
  ('00000000-0000-0000-0000-00000000000f','00000000-0000-0000-0000-00000000000f','compta@test','Compta','HO','Comptabilité','HO',false);

insert into public.marques(id, nom, escompte_fournisseur_bp) values
  ('10000000-0000-0000-0000-000000000001','MarqueFictive A', 4000);   -- escompte 40 % -> plafond 5 %
insert into public.produits(id, sku, marque_id, nom, categorie, modele, ahri, btu_nominal, prix_cents, cout_cents, fictif) values
  ('20000000-0000-0000-0000-000000000001','FIC-TP-24','10000000-0000-0000-0000-000000000001',
   'Thermopompe murale 24 000 BTU (FICTIF)','thermopompe_murale','FIC-24-EXT','999000001',24000, 450000, 270000, true);

insert into public.clients(id, nom, prenom, succursale_code, est_proprietaire, nom_preuve_propriete) values
  ('30000000-0000-0000-0000-000000000001','Tremblay','Julie','RO', true, 'Julie Tremblay'),
  ('30000000-0000-0000-0000-000000000002','Gagnon','Marc','GA', true, 'Marc Gagnon'),
  ('30000000-0000-0000-0000-000000000003','Roy','Line','RO', true, 'Line Roy');

-- ---------------------------------------------------------------------------
-- Taxes
-- ---------------------------------------------------------------------------
select test.ok((select tps = 500 and tvq = 998 from app.taxes(10000)), 'taxes sur 100,00 $ : TPS 5,00 $ et TVQ 9,98 $ (9,975 arrondi)');
select test.ok((select tps = 0 and tvq = 0 from app.taxes(1)), 'taxes sur 0,01 $ : 0 et 0');
select test.ok((select tps = 2250 and tvq = 4489 from app.taxes(45000)), 'taxes sur 450,00 $ : 22,50 $ et 44,89 $');
select test.ok((select tps = -500 and tvq = -998 from app.taxes(-10000)), 'taxes négatives symétriques (note de crédit)');
select test.ok((select tps = 0 and tvq = 998 from app.taxes(10000, current_date, true, false)), 'exemption TPS seulement');

-- ---------------------------------------------------------------------------
-- Numérotation sans trou
-- ---------------------------------------------------------------------------
insert into public.devis(id, succursale_code, client_id, vendeur_id) values
  ('40000000-0000-0000-0000-000000000001','RO','30000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-00000000000c');
select test.ok((select numero = 'D-' || to_char(current_date,'YYYY') || '-00001' from public.devis
                 where id = '40000000-0000-0000-0000-000000000001'), 'premier devis numéroté D-AAAA-00001');

-- Une transaction annulée ne consomme pas de numéro
begin;
insert into public.devis(succursale_code, client_id, vendeur_id) values
  ('RO','30000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-00000000000c');
rollback;
insert into public.devis(id, succursale_code, client_id, vendeur_id) values
  ('40000000-0000-0000-0000-000000000002','RO','30000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-00000000000c');
select test.ok((select numero like '%-00002' from public.devis where id = '40000000-0000-0000-0000-000000000002'),
               'après un rollback, le numéro suivant est 00002 (aucun trou)');

update public.devis set total_cents = 1 where id = '40000000-0000-0000-0000-000000000002';
select test.ok((select total_cents = 0 from public.devis where id = '40000000-0000-0000-0000-000000000002'),
               'un total de devis saisi à la main est ignoré');
select test.echec($$update public.compteurs set prochain = 1 where cle = 'devis'$$, 'décrément de compteur');
select test.echec($$delete from public.compteurs$$, 'suppression de compteur');
select test.echec($$update public.devis set numero = 'X' where id = '40000000-0000-0000-0000-000000000001'$$, 'modification d''un numéro de devis');
select test.echec($$delete from public.devis where id = '40000000-0000-0000-0000-000000000001'$$, 'suppression d''un devis');

-- ---------------------------------------------------------------------------
-- Rabais : plafond, approbation, délégation
-- ---------------------------------------------------------------------------
insert into public.devis_lignes(id, devis_id, produit_id, description, quantite, prix_unitaire_cents, rabais_bp) values
  ('50000000-0000-0000-0000-000000000001','40000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001',
   'Thermopompe 24k', 1, 450000, 500);
select test.ok((select plafond_bp = 500 and not approbation_requise and montant_cents = 427500
                  from public.devis_lignes where id = '50000000-0000-0000-0000-000000000001'),
               'escompte 40 % : plafond 5 %, rabais de 5 % accepté sans approbation');
select test.ok((select sous_total_cents = 427500 and rabais_cents = 22500 and tps_cents = 21375 and tvq_cents = 42643
                       and total_cents = 491518 and depot_cents = 196607
                  from public.devis where id = '40000000-0000-0000-0000-000000000001'),
               'totaux du devis : 4 275,00 $ + TPS 213,75 $ + TVQ 426,43 $ = 4 915,18 $, dépôt 40 % = 1 966,07 $');

update public.devis set depot_bp = 5000 where id = '40000000-0000-0000-0000-000000000001';
select test.ok((select depot_cents = 245759 from public.devis where id = '40000000-0000-0000-0000-000000000001'),
               'changer le pourcentage de dépôt recalcule le dépôt (50 % = 2 457,59 $)');
update public.devis set depot_bp = 4000 where id = '40000000-0000-0000-0000-000000000001';
update public.devis_lignes set rabais_bp = 800 where id = '50000000-0000-0000-0000-000000000001';
select test.ok((select approbation_requise from public.devis_lignes where id = '50000000-0000-0000-0000-000000000001'),
               'rabais de 8 % au-dessus du plafond : approbation requise');
select test.echec($$update public.devis set statut = 'envoye' where id = '40000000-0000-0000-0000-000000000001'$$,
                  'envoi d''un devis avec rabais non approuvé');

select test.comme('00000000-0000-0000-0000-00000000000c');
insert into public.approbations_rabais(id, devis_id, devis_ligne_id, rabais_bp, plafond_bp, motif) values
  ('60000000-0000-0000-0000-000000000001','40000000-0000-0000-0000-000000000001','50000000-0000-0000-0000-000000000001',
   800, 500, 'Client compare avec un concurrent');
select test.echec($$update public.approbations_rabais set statut = 'approuvee' where id = '60000000-0000-0000-0000-000000000001'$$,
                  'un vendeur ne peut pas approuver son propre rabais');
select test.echec($$insert into public.approbations_rabais(devis_id, devis_ligne_id, rabais_bp, plafond_bp, statut)
                    values ('40000000-0000-0000-0000-000000000001','50000000-0000-0000-0000-000000000001', 800, 500, 'approuvee')$$,
                  'créer une demande déjà approuvée', 'créée en attente');
select test.comme('00000000-0000-0000-0000-00000000000a');
update public.approbations_rabais set statut = 'approuvee' where id = '60000000-0000-0000-0000-000000000001';
select test.ok((select decide_par = '00000000-0000-0000-0000-00000000000a' from public.approbations_rabais
                 where id = '60000000-0000-0000-0000-000000000001'), 'Simon approuve, décision tracée');
update public.devis set statut = 'envoye' where id = '40000000-0000-0000-0000-000000000001';
select test.ok((select statut = 'envoye' from public.devis where id = '40000000-0000-0000-0000-000000000001'),
               'devis envoyé une fois le rabais approuvé');
select test.echec($$update public.devis_lignes set rabais_bp = 0 where id = '50000000-0000-0000-0000-000000000001'$$,
                  'modification d''une ligne d''un devis envoyé');
select test.echec($$update public.approbations_rabais set statut = 'refusee' where id = '60000000-0000-0000-0000-000000000001'$$,
                  'changer une décision déjà rendue');

-- Délégation : Simon accorde 10 % au vendeur de Rosemère
insert into public.delegations_rabais(employe_id, plafond_bp, accorde_par) values
  ('00000000-0000-0000-0000-00000000000c', 1000, '00000000-0000-0000-0000-00000000000a');
insert into public.devis_lignes(devis_id, produit_id, description, prix_unitaire_cents, rabais_bp) values
  ('40000000-0000-0000-0000-000000000002','20000000-0000-0000-0000-000000000001','Thermopompe 24k', 450000, 800);
select test.ok((select not approbation_requise and plafond_bp = 1000 from public.devis_lignes
                 where devis_id = '40000000-0000-0000-0000-000000000002'),
               'avec une délégation de 10 %, un rabais de 8 % ne demande plus d''approbation');
select test.echec($$insert into public.delegations_rabais(employe_id, plafond_bp, accorde_par)
                    values ('00000000-0000-0000-0000-00000000000d', 2000, '00000000-0000-0000-0000-00000000000c')$$,
                  'un vendeur ne peut pas accorder de délégation');
reset request.jwt.claims;

-- ---------------------------------------------------------------------------
-- Projet, équipements, BT
-- ---------------------------------------------------------------------------
insert into public.projets(id, succursale_code, client_id, devis_id, installation_prevue_le) values
  ('70000000-0000-0000-0000-000000000001','RO','30000000-0000-0000-0000-000000000001',
   '40000000-0000-0000-0000-000000000001', '2026-11-20 08:00-05');
select test.ok((select code_projet = 'ROV-001-' || to_char(current_date,'YY') from public.projets
                 where id = '70000000-0000-0000-0000-000000000001'), 'code projet ROV-001-AA (format provisoire)');
select test.ok((select solde_du_le = '2026-11-17 08:00-05'::timestamptz from public.projets
                 where id = '70000000-0000-0000-0000-000000000001'), 'solde dû 72 h avant l''installation');

insert into public.bons_travail(id, succursale_code, projet_id, assigne_employe_id, prevu_le) values
  ('80000000-0000-0000-0000-000000000001','RO','70000000-0000-0000-0000-000000000001',
   '00000000-0000-0000-0000-00000000000e','2026-11-20 08:00-05');

-- Certification expirée : informatif par défaut, bloquant si le paramètre est activé
insert into public.certifications(employe_id, type, numero, expire_le) values
  ('00000000-0000-0000-0000-00000000000e','halocarbures','H-123','2026-01-01');
insert into public.bons_travail(succursale_code, projet_id, assigne_employe_id, prevu_le) values
  ('RO','70000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-00000000000e','2026-11-21 08:00-05');
select test.ok(true, 'certification expirée : assignation permise quand le blocage est désactivé');
update public.parametres set valeur = 'true' where cle = 'bloquer_certifs_expirees';
select test.echec($$insert into public.bons_travail(succursale_code, projet_id, assigne_employe_id, prevu_le)
                    values ('RO','70000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-00000000000e','2026-11-22')$$,
                  'certification expirée : assignation refusée quand le blocage est activé');
update public.parametres set valeur = 'false' where cle = 'bloquer_certifs_expirees';

-- ---------------------------------------------------------------------------
-- RLS : qui voit quoi
-- ---------------------------------------------------------------------------
set role authenticated;
select test.comme('00000000-0000-0000-0000-00000000000c');
select test.ok((select count(*) = 2 from public.clients), 'vendeur RO voit les 2 clients de RO');
select test.ok((select count(*) = 0 from public.clients where succursale_code = 'GA'), 'vendeur RO ne voit pas Gatineau');
select test.echec($$insert into public.clients(nom, succursale_code) values ('Intrus','GA')$$, 'vendeur RO crée un client à GA');
select test.ok((select count(*) = 0 from public.journal_audit), 'vendeur ne lit pas le journal d''audit');
select test.ok((select count(*) = 0 from public.compteurs), 'personne ne lit les compteurs directement');
select test.echec($$select app.prochain_numero('facture')$$, 'appel direct de prochain_numero');

select test.comme('00000000-0000-0000-0000-00000000000e');
select test.ok((select count(*) = 1 from public.clients), 'technicien voit seulement le client de son BT');
select test.ok((select count(*) = 0 from public.devis), 'technicien ne voit pas les devis');
select test.ok((select count(*) = 2 from public.bons_travail), 'technicien voit ses BT');
update public.bons_travail set statut = 'en_cours' where id = '80000000-0000-0000-0000-000000000001';
select test.ok((select statut = 'en_cours' from public.bons_travail where id = '80000000-0000-0000-0000-000000000001'),
               'technicien met à jour son BT');

select test.comme('00000000-0000-0000-0000-00000000000f');
select test.ok((select count(*) = 3 from public.clients), 'comptabilité voit toutes les succursales');

select test.comme('00000000-0000-0000-0000-00000000000d');
select test.ok((select count(*) = 1 from public.clients), 'vendeur GA voit seulement Gatineau');
delete from public.clients;
select test.ok((select count(*) = 1 from public.clients), 'aucune suppression via l''API (aucune politique DELETE)');

reset role;
reset request.jwt.claims;
set role anon;
select test.echec($$select * from public.clients$$, 'anon (clé publique sans session) ne lit rien');
reset role;

-- ---------------------------------------------------------------------------
-- Facturation et LogisVert
-- ---------------------------------------------------------------------------
insert into public.subventions(id, succursale_code, client_id, projet_id, date_premiere_mesure) values
  ('90000000-0000-0000-0000-000000000001','RO','30000000-0000-0000-0000-000000000001',
   '70000000-0000-0000-0000-000000000001','2026-11-20');
select test.ok((select date_limite = '2027-08-20' from public.subventions where id = '90000000-0000-0000-0000-000000000001'),
               'LogisVert : date limite = première mesure + 9 mois');

insert into public.factures(id, type, succursale_code, client_id, projet_id) values
  ('a0000000-0000-0000-0000-000000000001','depot','RO','30000000-0000-0000-0000-000000000001','70000000-0000-0000-0000-000000000001');
insert into public.facture_lignes(facture_id, description, prix_unitaire_cents) values
  ('a0000000-0000-0000-0000-000000000001','Dépôt 40 %', 170000);
select test.ok((select numero is null and total_cents = 195458 from public.factures
                 where id = 'a0000000-0000-0000-0000-000000000001'), 'brouillon sans numéro, totaux calculés');
select test.echec($$insert into public.paiements(facture_id, montant_cents, mode)
                    values ('a0000000-0000-0000-0000-000000000001', 1000, 'carte')$$, 'paiement sur un brouillon');
update public.factures set statut = 'emise' where id = 'a0000000-0000-0000-0000-000000000001';
select test.ok((select numero = 'F-' || to_char(current_date,'YYYY') || '-00001' and emise_le is not null
                  from public.factures where id = 'a0000000-0000-0000-0000-000000000001'),
               'numéro attribué à l''émission : F-AAAA-00001');
select test.echec($$update public.facture_lignes set prix_unitaire_cents = 1 where facture_id = 'a0000000-0000-0000-0000-000000000001'$$,
                  'modification d''une facture émise');
update public.factures set total_cents = 1 where id = 'a0000000-0000-0000-0000-000000000001';
select test.ok((select total_cents = 195458 from public.factures where id = 'a0000000-0000-0000-0000-000000000001'),
               'un total de facture saisi à la main est ignoré');
select test.echec($$update public.factures set statut = 'payee' where id = 'a0000000-0000-0000-0000-000000000001'$$,
                  'marquer payée sans paiement', 'découle des paiements');
select test.echec($$delete from public.factures$$, 'suppression d''une facture');
insert into public.paiements(facture_id, montant_cents, mode) values ('a0000000-0000-0000-0000-000000000001', 195458, 'carte');
select test.ok((select statut = 'payee' and montant_paye_cents = 195458 from public.factures
                 where id = 'a0000000-0000-0000-0000-000000000001'), 'paiement complet : facture payée');
select test.echec($$delete from public.paiements$$, 'suppression d''un paiement');

-- Facture de solde : bloquée tant que les pièces LogisVert manquent
insert into public.factures(id, type, succursale_code, client_id, projet_id) values
  ('a0000000-0000-0000-0000-000000000002','solde','RO','30000000-0000-0000-0000-000000000001','70000000-0000-0000-0000-000000000001');
insert into public.facture_lignes(facture_id, description, prix_unitaire_cents) values
  ('a0000000-0000-0000-0000-000000000002','Solde 60 %', 255000);
select test.echec($$update public.factures set statut = 'emise' where id = 'a0000000-0000-0000-0000-000000000002'$$,
                  'facture de solde sans numéro de série ni date d''installation', 'non conforme LogisVert');
select test.ok((select coalesce(array_length(app.manques_logisvert('a0000000-0000-0000-0000-000000000002'),1),0) = 2
                ), 'deux pièces manquantes listées (installation, appareil extérieur)');

insert into public.documents(id, chemin, nom_fichier, categorie, entite, entite_id, succursale_code) values
  ('b0000000-0000-0000-0000-000000000001','ro/plaque.jpg','plaque.jpg','photo_plaque','equipements_installes',
   '70000000-0000-0000-0000-000000000001','RO');
insert into public.equipements_installes(projet_id, client_id, role, marque, modele, numero_serie, ahri, btu_nominal, installe_le, photo_plaque_id)
  values ('70000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001','exterieur','MarqueFictive A',
          'FIC-24-EXT','SN-0001','999000001',24000,'2026-11-20','b0000000-0000-0000-0000-000000000001');
update public.projets set installation_terminee_le = '2026-11-20 16:00-05' where id = '70000000-0000-0000-0000-000000000001';
update public.factures set statut = 'emise' where id = 'a0000000-0000-0000-0000-000000000002';
select test.ok((select numero like '%-00002' from public.factures where id = 'a0000000-0000-0000-0000-000000000002'),
               'facture de solde émise une fois le dossier LogisVert complet, numéro 00002');

-- Note de crédit : série distincte, référence obligatoire
select test.echec($$insert into public.factures(type, succursale_code, client_id) values ('credit','RO','30000000-0000-0000-0000-000000000001')$$,
                  'note de crédit sans facture d''origine');

-- ---------------------------------------------------------------------------
-- Audit
-- ---------------------------------------------------------------------------
select test.ok((select count(*) > 0 from public.journal_audit where table_nom = 'approbations_rabais'), 'approbations journalisées');
select test.echec($$update public.journal_audit set action = 'x'$$, 'modification du journal');
select test.echec($$delete from public.journal_audit$$, 'suppression du journal');
select test.ok((select count(*) > 0 from public.journal_audit where table_nom = 'factures' and action = 'update'), 'émission de facture journalisée');

\echo 'TOUS LES TESTS SQL PHASE 1 SONT PASSÉS'
