-- Rabais global : montant ou pourcentage, toujours approuvé par Simon ou Mike.
\set ON_ERROR_STOP on
set client_min_messages = notice;

insert into public.devis(id, succursale_code, client_id, vendeur_id) values
  ('44000000-0000-0000-0000-000000000001','RO','30000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-00000000000c');
insert into public.devis_lignes(devis_id, produit_id, description, prix_unitaire_cents) values
  ('44000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','Thermopompe', 0);

-- Montant fixe
insert into public.devis_lignes(id, devis_id, type_ligne, description, prix_unitaire_cents, rabais_mode, rabais_valeur) values
  ('54000000-0000-0000-0000-000000000001','44000000-0000-0000-0000-000000000001','rabais','Rabais supplémentaire', 999, 'montant', 20000);
select test.ok((select prix_unitaire_cents = -20000 and montant_cents = -20000 and approbation_requise and plafond_bp = 0
                  from public.devis_lignes where id = '54000000-0000-0000-0000-000000000001'),
               'rabais global de 200 $ : -200,00 $, approbation obligatoire');
select test.ok((select sous_total_cents = 430000 and rabais_cents = 20000 and tps_cents = 21500
                  from public.devis where id = '44000000-0000-0000-0000-000000000001'),
               'le rabais global réduit le sous-total avant les taxes (4 300 $)');
select test.ok((select bloque_par_rabais from public.devis_v where id = '44000000-0000-0000-0000-000000000001'), 'devis bloqué tant que non approuvé');

-- Approbation, puis hausse du rabais : il faut une nouvelle approbation
select test.comme('00000000-0000-0000-0000-00000000000c');
insert into public.approbations_rabais(id, devis_ligne_id, motif) values
  ('64000000-0000-0000-0000-000000000001','54000000-0000-0000-0000-000000000001','Concurrent');
select test.comme('00000000-0000-0000-0000-00000000000b');
update public.approbations_rabais set statut = 'approuvee' where id = '64000000-0000-0000-0000-000000000001';
reset request.jwt.claims;
select test.ok((select not bloque_par_rabais from public.devis_v where id = '44000000-0000-0000-0000-000000000001'), 'approuvé par Mike : débloqué');
update public.devis_lignes set rabais_valeur = 30000 where id = '54000000-0000-0000-0000-000000000001';
select test.ok((select bloque_par_rabais from public.devis_v where id = '44000000-0000-0000-0000-000000000001'),
               'rabais porté à 300 $ : l''approbation de 200 $ ne suffit plus');
update public.devis_lignes set rabais_valeur = 15000 where id = '54000000-0000-0000-0000-000000000001';
select test.ok((select not bloque_par_rabais from public.devis_v where id = '44000000-0000-0000-0000-000000000001'),
               'rabais baissé à 150 $ : couvert par l''approbation de 200 $');

-- Passage en pourcentage : nouvelle approbation (autre mode)
update public.devis_lignes set rabais_mode = 'pourcentage', rabais_valeur = 500 where id = '54000000-0000-0000-0000-000000000001';
select test.ok((select prix_unitaire_cents = -22500 from public.devis_lignes where id = '54000000-0000-0000-0000-000000000001'),
               'rabais global de 5 % sur 4 500 $ = -225,00 $');
select test.ok((select bloque_par_rabais from public.devis_v where id = '44000000-0000-0000-0000-000000000001'),
               'changement de mode ($ vers %) : nouvelle approbation requise');

-- Le % suit le sous-total quand les autres lignes changent
insert into public.devis_lignes(devis_id, description, prix_unitaire_cents) values
  ('44000000-0000-0000-0000-000000000001','Ligne libre', 100000);
select test.ok((select prix_unitaire_cents = -27500 from public.devis_lignes where id = '54000000-0000-0000-0000-000000000001'),
               'le rabais de 5 % suit le sous-total (5 500 $ -> -275,00 $)');
select test.ok((select sous_total_cents = 522500 from public.devis where id = '44000000-0000-0000-0000-000000000001'),
               'sous-total après rabais : 5 225,00 $');

-- Garde-fous
select test.echec($$update public.devis_lignes set rabais_mode = 'montant', rabais_valeur = 99999999 where id = '54000000-0000-0000-0000-000000000001'$$,
                  'rabais plus grand que le sous-total', 'dépasse');
select test.echec($$insert into public.devis_lignes(devis_id, description, prix_unitaire_cents) values ('44000000-0000-0000-0000-000000000001','Crédit déguisé', -5000)$$,
                  'ligne libre négative (seul le rabais global peut être négatif)');
select test.echec($$insert into public.devis_lignes(devis_id, type_ligne, description, prix_unitaire_cents, rabais_mode, rabais_valeur) values ('44000000-0000-0000-0000-000000000001','rabais','X', 0, 'pourcentage', 20000)$$,
                  'rabais de plus de 100 %');

\echo 'TESTS RABAIS GLOBAL PASSÉS'
