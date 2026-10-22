-- Module Clients + Devis (suite de 10_phase1 et 20_session).
\set ON_ERROR_STOP on
set client_min_messages = notice;

insert into public.kits(id, code, nom) values ('c0000000-0000-0000-0000-000000000001','KIT-T','Kit test');
insert into public.kit_items(kit_id, produit_id, quantite) values
  ('c0000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001', 2);
select test.ok((select public.hvac_prix_kit('c0000000-0000-0000-0000-000000000001') = 900000), 'prix du kit = somme des composantes');
update public.kits set prix_cents = 850000 where id = 'c0000000-0000-0000-0000-000000000001';
select test.ok((select public.hvac_prix_kit('c0000000-0000-0000-0000-000000000001') = 850000), 'prix fixe du kit prioritaire');

-- Rabais sur un kit : toujours une approbation, même avec une délégation de 10 %
insert into public.devis(id, succursale_code, client_id, vendeur_id) values
  ('41000000-0000-0000-0000-000000000001','RO','30000000-0000-0000-0000-000000000003','00000000-0000-0000-0000-00000000000c');
insert into public.devis_lignes(id, devis_id, kit_id, description, prix_unitaire_cents, rabais_bp) values
  ('51000000-0000-0000-0000-000000000001','41000000-0000-0000-0000-000000000001','c0000000-0000-0000-0000-000000000001','Kit test', 850000, 100);
select test.ok((select approbation_requise and plafond_bp = 0 from public.devis_lignes where id = '51000000-0000-0000-0000-000000000001'),
               'kit : 1 % de rabais demande l''approbation de Simon ou Mike');
select test.ok((select bloque_par_rabais and statut_effectif = 'brouillon' from public.devis_v where id = '41000000-0000-0000-0000-000000000001'),
               'vue devis_v : devis bloqué par un rabais');

-- La demande prend ses valeurs de la ligne, pas du client
select test.comme('00000000-0000-0000-0000-00000000000c');
insert into public.approbations_rabais(id, devis_id, devis_ligne_id, rabais_bp, plafond_bp)
  values ('61000000-0000-0000-0000-000000000001','40000000-0000-0000-0000-000000000001','51000000-0000-0000-0000-000000000001', 1, 9999);
select test.ok((select rabais_bp = 100 and plafond_bp = 0 and devis_id = '41000000-0000-0000-0000-000000000001'
                  from public.approbations_rabais where id = '61000000-0000-0000-0000-000000000001'),
               'demande d''approbation : rabais, plafond et devis recopiés de la ligne');
select test.echec($$insert into public.approbations_rabais(devis_id, devis_ligne_id, rabais_bp, plafond_bp)
                    select devis_id, id, 0, 0 from public.devis_lignes where devis_id = '40000000-0000-0000-0000-000000000002' limit 1$$,
                  'demande inutile (rabais dans le plafond)', 'aucune approbation requise');
reset request.jwt.claims;

-- Envoi : validité = aujourd'hui + 30 jours ; devis vide refusé
select test.comme('00000000-0000-0000-0000-00000000000a');
update public.approbations_rabais set statut = 'approuvee' where id = '61000000-0000-0000-0000-000000000001';
reset request.jwt.claims;
update public.devis set valide_jusqu = current_date - 100 where id = '41000000-0000-0000-0000-000000000001';
update public.devis set statut = 'envoye' where id = '41000000-0000-0000-0000-000000000001';
select test.ok((select valide_jusqu = current_date + 30 from public.devis where id = '41000000-0000-0000-0000-000000000001'),
               'envoi : valide 30 jours à partir d''aujourd''hui');
insert into public.devis(id, succursale_code, client_id, vendeur_id) values
  ('41000000-0000-0000-0000-000000000002','RO','30000000-0000-0000-0000-000000000003','00000000-0000-0000-0000-00000000000c');
select test.echec($$update public.devis set statut = 'envoye' where id = '41000000-0000-0000-0000-000000000002'$$, 'envoi d''un devis vide', 'aucune ligne');
select test.echec($$update public.devis set statut = 'accepte' where id = '41000000-0000-0000-0000-000000000002'$$,
                  'accepter un brouillon');

-- Expiration
update public.devis set valide_jusqu = current_date - 1 where id = '41000000-0000-0000-0000-000000000001';
select test.ok((select statut = 'envoye' and statut_effectif = 'expire' from public.devis_v where id = '41000000-0000-0000-0000-000000000001'),
               'après 30 jours, le devis apparaît expiré');
select test.echec($$update public.devis set statut = 'accepte' where id = '41000000-0000-0000-0000-000000000001'$$,
                  'accepter un devis expiré', 'expiré');

-- Renouvellement : nouveau numéro, mêmes lignes, approbation à refaire
select test.comme('00000000-0000-0000-0000-00000000000c');
select public.hvac_dupliquer_devis('41000000-0000-0000-0000-000000000001') as nouveau \gset
select test.ok((select n.numero <> o.numero and n.statut = 'brouillon' and n.code_projet = o.code_projet || '-E01'
                  from public.devis n, public.devis o
                 where n.id = :'nouveau' and o.id = '41000000-0000-0000-0000-000000000001'),
               'renouvellement : nouveau devis en brouillon, nouveau numéro, code d''origine + E01');
select test.ok((select count(*) = 1 from public.devis_v where notes_internes like '%Renouvellement%' and bloque_par_rabais),
               'renouvellement : le rabais du kit doit être réapprouvé');

-- RLS de la vue
select test.comme('00000000-0000-0000-0000-00000000000d');
set role authenticated;
select test.ok((select count(*) = 0 from public.devis_v), 'vue devis_v : vendeur GA ne voit pas les devis de RO');
reset role;
reset request.jwt.claims;

-- Prix imposé par le catalogue
insert into public.devis_lignes(id, devis_id, produit_id, description, prix_unitaire_cents) values
  ('51000000-0000-0000-0000-000000000009','41000000-0000-0000-0000-000000000002','20000000-0000-0000-0000-000000000001','Prix trafiqué', 1);
select test.ok((select prix_unitaire_cents = 450000 from public.devis_lignes where id = '51000000-0000-0000-0000-000000000009'),
               'le prix d''un produit vient du catalogue, pas du formulaire');

\echo 'TESTS MODULE DEVIS PASSÉS'
