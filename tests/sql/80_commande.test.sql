-- Lot B : acceptation -> projet + BT + BC ; planification ; jobs du sous-traitant ; notifications.
\set ON_ERROR_STOP on
set client_min_messages = notice;

-- Produit commandable chez un fournisseur (au coût de 2 700 $)
insert into public.fournisseurs(id, nom, type) values ('fa000000-0000-0000-0000-000000000001','Distributeur HVAC (TEST)','fournisseur');
update public.produits set fournisseur_id = 'fa000000-0000-0000-0000-000000000001' where id = '20000000-0000-0000-0000-000000000001';
update public.fournisseurs set telephone = '450 555-0199', courriel = 'st@test.invalid' where id = 'f2000000-0000-0000-0000-000000000001';

-- Devis au lieu T0002 (desservi avec supplément par le ST de test), produit + installation
insert into public.devis(id, succursale_code, client_id, site_id, vendeur_id) values
  ('48000000-0000-0000-0000-000000000001','RO','30000000-0000-0000-0000-000000000003','d9000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-00000000000c');
insert into public.devis_lignes(devis_id, position, produit_id, description, prix_unitaire_cents, quantite) values
  ('48000000-0000-0000-0000-000000000001', 1, '20000000-0000-0000-0000-000000000001','Thermopompe', 0, 2);
insert into public.devis_lignes(devis_id, position, type_ligne, type_travail_id, sous_traitant_id, description, prix_unitaire_cents) values
  ('48000000-0000-0000-0000-000000000001', 2, 'installation','71000000-0000-0000-0000-000000000001','f2000000-0000-0000-0000-000000000001','Installation murale', 0);
update public.devis set statut = 'envoye' where id = '48000000-0000-0000-0000-000000000001';
update public.devis set statut = 'accepte' where id = '48000000-0000-0000-0000-000000000001';

select test.ok((select count(*) = 1 from public.projets where devis_id = '48000000-0000-0000-0000-000000000001'), 'acceptation : projet créé');
select test.ok((select b.numero = 'RV001 ' || p.code_projet and b.statut = 'brouillon' and b.assigne_fournisseur_id = 'f2000000-0000-0000-0000-000000000001'
                  from public.bons_travail b join public.projets p on p.id = b.projet_id where p.devis_id = '48000000-0000-0000-0000-000000000001'),
               'acceptation : BT RV001 en brouillon, assigné au sous-traitant du devis');
select test.ok((select count(*) = 2 from public.bt_lignes bl join public.bons_travail b on b.id = bl.bon_travail_id
                  join public.projets p on p.id = b.projet_id where p.devis_id = '48000000-0000-0000-0000-000000000001'),
               'BT : produit et installation repris du devis');
select test.ok((select bc.numero = app.prefixe_de_code(p.code_projet) || '-100' and bc.statut = 'brouillon'
                       and bc.mode_livraison = 'ramassage' and bc.ramassage_par = 'f2000000-0000-0000-0000-000000000001'
                       and bc.sous_total_cents = 540000 and bc.tps_cents = 27000 and bc.adresse_livraison like '%Saint-Jérôme%'
                  from public.bons_commande bc join public.projets p on p.id = bc.projet_id where p.devis_id = '48000000-0000-0000-0000-000000000001'),
               'BC brouillon : préfixe-100, au coût (2 x 2 700 $), ramassage par le sous-traitant');

-- Transitions du BC
select test.echec($$update public.bons_commande set statut = 'recu' where statut = 'brouillon'$$, 'BC brouillon directement reçu', 'non permis');
update public.bons_commande set statut = 'envoye' where projet_id = (select id from public.projets where devis_id = '48000000-0000-0000-0000-000000000001');
select test.echec($$update public.bc_lignes set quantite = 9$$, 'modifier les lignes d''un BC envoyé');
select test.echec($$delete from public.bons_commande$$, 'supprimer un BC');

-- 2e devis accepté pour le même client : BC -101
insert into public.devis(id, succursale_code, client_id, site_id, vendeur_id) values
  ('48000000-0000-0000-0000-000000000002','RO','30000000-0000-0000-0000-000000000003','d9000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-00000000000c');
insert into public.devis_lignes(devis_id, produit_id, description, prix_unitaire_cents) values
  ('48000000-0000-0000-0000-000000000002','20000000-0000-0000-0000-000000000001','Thermopompe', 0);
update public.devis set statut = 'envoye' where id = '48000000-0000-0000-0000-000000000002';
update public.devis set statut = 'accepte' where id = '48000000-0000-0000-0000-000000000002';
select test.ok((select bc.numero like '%-101' from public.bons_commande bc join public.projets p on p.id = bc.projet_id
                 where p.devis_id = '48000000-0000-0000-0000-000000000002'), '2e BC du même préfixe : -101');

-- Planification
select b.id as bt from public.bons_travail b join public.projets p on p.id = b.projet_id
 where p.devis_id = '48000000-0000-0000-0000-000000000001' \gset
set role authenticated;
select test.comme('00000000-0000-0000-0000-00000000000c');
select test.echec(format($$select public.hvac_planifier_bt(%L, '2026-11-20')$$, :'bt'), 'un vendeur ne planifie pas', 'réservée');
select test.comme('00000000-0000-0000-0000-00000000000a');
select test.echec(format($$select public.hvac_planifier_bt(%L, '2026-11-20')$$, :'bt'), 'planification sans dépôt payé', 'dépôt non payé');
reset role;
insert into public.financements(succursale_code, client_id, projet_id, statut, montant_cents)
  select 'RO','30000000-0000-0000-0000-000000000003', id, 'approuve', 100000 from public.projets where devis_id = '48000000-0000-0000-0000-000000000001';
set role authenticated;
select test.echec(format($$select public.hvac_planifier_bt(%L, '2026-11-21')$$, :'bt'), 'journée non disponible du sous-traitant', 'pas disponible');
select public.hvac_planifier_bt(:'bt', '2026-11-20', '08:00');
reset role;
select test.ok((select statut = 'planifie' and prevu_le = '2026-11-20 08:00-05'::timestamptz from public.bons_travail where id = :'bt'),
               'planifié le 20 novembre à 8 h (confirmé automatiquement)');
select test.ok((select p.installation_prevue_le = '2026-11-20 08:00-05'::timestamptz and p.solde_du_le = '2026-11-17 08:00-05'::timestamptz
                  from public.projets p join public.bons_travail b on b.projet_id = p.id where b.id = :'bt'),
               'projet : date d''installation et solde dû 72 h avant');
select test.ok((select count(*) = 1 from public.notifications where destinataire_fournisseur_id = 'f2000000-0000-0000-0000-000000000001'),
               'le sous-traitant reçoit une notification');
select test.ok((select count(*) = 2 from public.envois where statut = 'en_attente'), 'courriel et SMS mis en file d''envoi');

-- Jobs du sous-traitant
set role authenticated;
select test.comme('00000000-0000-0000-0000-0000000000c1');
select test.ok((select jsonb_array_length(public.hvac_mes_jobs()) = 1), 'sous-traitant : voit sa job planifiée (pas les brouillons)');
select test.ok((select (public.hvac_mes_jobs() -> 0 ->> 'client') = 'Line Roy'), 'sous-traitant : nom du client pour se présenter');
select test.ok((select (public.hvac_mes_jobs() -> 0 -> 'materiel' -> 0 ->> 'mode') = 'ramassage'), 'sous-traitant : où ramasser le matériel');
select test.ok((select count(*) = 1 from public.notifications), 'sous-traitant : lit sa notification');
select public.hvac_job_statut(:'bt', 'en_cours');
select test.echec(format($$select public.hvac_job_statut(%L, 'planifie')$$, :'bt'), 'retour en arrière d''une job', 'non permis');
select test.comme('00000000-0000-0000-0000-00000000000c');
select test.echec($$select public.hvac_mes_jobs()$$, 'un vendeur n''utilise pas la vue des sous-traitants', 'Réservé');
reset role;
reset request.jwt.claims;
select test.ok((select count(*) >= 1 from public.journal_audit where action = 'lecture' and table_nom = 'jobs_sous_traitant'),
               'accès du sous-traitant aux renseignements clients journalisé (Loi 25)');

\echo 'TESTS COMMANDE PASSÉS'
