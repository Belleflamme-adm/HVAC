-- Taxes : vente en Ontario (TVH 13 %) et client autochtone exonéré (ADR-054).
\set ON_ERROR_STOP on
set client_min_messages = notice;
update public.parametres set valeur = 'false' where cle = 'exiger_preinstallation';

insert into public.sites(id, client_id, adresse, ville, province) values
  ('d9900000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001','1 rue Principale','Hawkesbury','ON'),
  ('d9900000-0000-0000-0000-000000000002','30000000-0000-0000-0000-000000000001','2 rue Principale','Rosemère','QC');

-- Chantier en Ontario : case « Vente Ontario » précochée, TVH 13 % seule
insert into public.devis(id, succursale_code, client_id, site_id, vendeur_id) values
  ('49900000-0000-0000-0000-000000000001','RO','30000000-0000-0000-0000-000000000001','d9900000-0000-0000-0000-000000000001','00000000-0000-0000-0000-00000000000c');
insert into public.devis_lignes(devis_id, produit_id, description, prix_unitaire_cents) values
  ('49900000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','Thermopompe', 0);
select test.ok((select regime_taxes = 'ON' and tps_cents = 0 and tvq_cents = 0 and tvh_cents = 58500
                       and total_cents = 450000 + 58500
                  from public.devis where id = '49900000-0000-0000-0000-000000000001'),
               'Ontario : TVH 13 % sur 4 500 $ = 585,00 $, aucune TPS ni TVQ');

-- Décocher la case : retour à TPS + TVQ, mais envoi refusé (chantier en Ontario)
update public.devis set regime_taxes = 'QC' where id = '49900000-0000-0000-0000-000000000001';
select test.ok((select tps_cents = 22500 and tvq_cents = 44888 and tvh_cents = 0
                  from public.devis where id = '49900000-0000-0000-0000-000000000001'),
               'case décochée : TPS 225,00 $ et TVQ 448,88 $');
select test.echec($$update public.devis set statut = 'envoye' where id = '49900000-0000-0000-0000-000000000001'$$,
                  'envoyer un devis aux taxes du Québec pour un chantier en Ontario', 'Vente Ontario');
update public.devis set regime_taxes = 'ON' where id = '49900000-0000-0000-0000-000000000001';
update public.devis set statut = 'envoye' where id = '49900000-0000-0000-0000-000000000001';
select test.echec($$update public.devis set regime_taxes = 'QC' where id = '49900000-0000-0000-0000-000000000001'$$,
                  'changer les taxes d''un devis envoyé', 'figées');

-- Client autochtone : aucune taxe, au Québec comme en Ontario
insert into public.devis(id, succursale_code, client_id, site_id, vendeur_id, autochtone, autochtone_no_registre) values
  ('49900000-0000-0000-0000-000000000002','RO','30000000-0000-0000-0000-000000000001','d9900000-0000-0000-0000-000000000002','00000000-0000-0000-0000-00000000000c', true, '1234567890');
insert into public.devis_lignes(devis_id, produit_id, description, prix_unitaire_cents) values
  ('49900000-0000-0000-0000-000000000002','20000000-0000-0000-0000-000000000001','Thermopompe', 0);
select test.ok((select tps_cents = 0 and tvq_cents = 0 and tvh_cents = 0 and total_cents = 450000
                  from public.devis where id = '49900000-0000-0000-0000-000000000002'),
               'autochtone : exonéré TPS/TVQ');
update public.devis set autochtone = false where id = '49900000-0000-0000-0000-000000000002';
select test.ok((select total_cents = 450000 + 22500 + 44888 from public.devis where id = '49900000-0000-0000-0000-000000000002'),
               'case décochée : taxes recalculées');

-- Totaux protégés : la TVH ne s'écrit pas à la main
update public.devis set tvh_cents = 1 where id = '49900000-0000-0000-0000-000000000001';
select test.ok((select tvh_cents = 58500 from public.devis where id = '49900000-0000-0000-0000-000000000001'),
               'la TVH est calculée par la base seulement');

-- Facture : reprend les cases du devis
insert into public.factures(id, succursale_code, client_id, devis_id, type) values
  ('f9900000-0000-0000-0000-000000000001','RO','30000000-0000-0000-0000-000000000001','49900000-0000-0000-0000-000000000001','depot');
insert into public.facture_lignes(facture_id, description, prix_unitaire_cents) values
  ('f9900000-0000-0000-0000-000000000001','Dépôt 40 %', 100000);
select test.ok((select regime_taxes = 'ON' and tvh_cents = 13000 and tps_cents = 0 and total_cents = 113000
                  from public.factures where id = 'f9900000-0000-0000-0000-000000000001'),
               'facture d''un devis ontarien : TVH 13 %');

-- Fonction de calcul : arrondi au cent
select test.ok((select tvh = 13 from app.taxes_regime(100, current_date, 'ON', false, false, false)), 'TVH 13 % de 1,00 $ = 0,13 $');
select test.ok((select tvh = 0 from app.taxes_regime(100, current_date, 'ON', true, true, false)), 'client exempté des deux taxes : pas de TVH');

\echo 'TESTS TAXES PASSÉS'
