-- Feuille d'extra du sous-traitant : liste ou hors liste, approbation, facture finale (ADR-081)
\set ON_ERROR_STOP on
set client_min_messages = notice;
create temp table t_x as select id as type_id from public.types_travaux where code = 'EXTRA-LIGNE-PI';
create temp table t_inst as select id as type_id from public.types_travaux where code = 'INST-MULTI-2T';
grant select on t_x, t_inst to authenticated;
insert into public.tarifs_sous_traitants(fournisseur_id, type_travail_id, cout_cents, en_vigueur_du)
  select 'f2000000-0000-0000-0000-000000000001', type_id, 2500, '2026-01-01' from t_x on conflict do nothing;
insert into public.travaux_sous_traitants(fournisseur_id, type_travail_id)
  select 'f2000000-0000-0000-0000-000000000001', type_id from t_x on conflict do nothing;
insert into public.leads (id, succursale_code, contact_nom, contact_tel, ville, type_demande, assigne_a) values
  ('1e000000-0000-0000-0000-0000000000b1', 'RO', 'Luc Fortin', '450-555-0166', 'Rosemère', 'mural_multi', '00000000-0000-0000-0000-00000000000c');
set role authenticated;

select test.comme('00000000-0000-0000-0000-00000000000a');
create temp table t_px as select public.hvac_projet_signe(format($${"lead_id":"1e000000-0000-0000-0000-0000000000b1","devis_numero_mike":"121101",
  "sous_traitant_id":"f2000000-0000-0000-0000-000000000001","lignes":[{"type_ligne":"installation","type_travail_id":"%s"}]}$$,
  (select type_id from t_inst))::jsonb) as id;
grant select on t_px to authenticated;

-- Avant le dépôt : pas d'extras
select test.comme('00000000-0000-0000-0000-0000000000c1');
select test.echec(format($$select public.hvac_extra_ajouter('%s', '{"description":"Support","cout_cents":18000,"justification":"Mur de brique trop friable","cause":"imprevu_chantier"}')$$,
  (select id from t_px)), 'pas d''extra avant le dépôt', 'Extras fermés');

select test.comme('00000000-0000-0000-0000-00000000000a');
update public.projets set statut = 'planifie' where id = (select id from t_px);

-- Le sous-traitant ajoute : un extra de sa liste (prix imposé par sa liste), un hors liste avec justification
select test.comme('00000000-0000-0000-0000-0000000000c1');
create temp table t_e1 as select public.hvac_extra_ajouter((select id from t_px),
  format('{"type_travail_id":"%s","quantite":10,"cout_cents":1,"cause":"oubli_vendeur"}', (select type_id from t_x))::jsonb) as id;
reset role;
select test.ok((select cout_cents = 2500 and not hors_liste and statut = 'brouillon' from public.projet_extras where id = (select id from t_e1)),
               'extra de sa liste : prix de sa liste, pas celui envoyé');
set role authenticated;
select test.comme('00000000-0000-0000-0000-0000000000c1');
select test.echec(format($$select public.hvac_extra_ajouter('%s', '{"description":"Support mural","cout_cents":18000,"justification":"court","cause":"imprevu_chantier"}')$$,
  (select id from t_px)), 'hors liste sans vraie justification', 'Justification');
select test.echec(format($$select public.hvac_extra_ajouter('%s', '{"description":"Support mural","cout_cents":18000,"justification":"Mur de brique trop friable"}')$$,
  (select id from t_px)), 'cause obligatoire', 'cause');
create temp table t_e2 as select public.hvac_extra_ajouter((select id from t_px),
  '{"description":"Support mural renforcé","cout_cents":18000,"justification":"Mur de brique trop friable pour le support standard","cause":"imprevu_chantier"}') as id;
create temp table t_e3 as select public.hvac_extra_ajouter((select id from t_px),
  '{"description":"Erreur de saisie","cout_cents":5000,"justification":"Ligne entrée par erreur, à retirer","cause":"autre"}') as id;
select public.hvac_extra_retirer((select id from t_e3));
select test.ok((select count(*) = 2 from public.hvac_mes_projets() j, jsonb_array_elements(j.extras) x where j.id = (select id from t_px)),
               'Mes jobs : 2 extras (le retiré disparaît)');
select test.ok((select extras_en_attente_cents = 43000 and total_final_cents = 210000 from public.hvac_mes_projets() where id = (select id from t_px)),
               'en attente : 250 $ + 180 $ ; total final sans extras non approuvés');
select test.echec(format($$select public.hvac_facture_finale('%s')$$, (select id from t_px)), 'facture finale avec des brouillons', 'job est en cours');
-- Photo obligatoire pour le hors liste (imprévu de chantier) : refusé sans photo, accepté avec
select test.echec($$select public.hvac_extras_envoyer((select id from t_px))$$, 'hors liste sans photo', 'Photo obligatoire');
create temp table t_ph_g as select public.hvac_extra_photo_preparer((select id from t_e2), 'image/jpeg', 200000) as p;
insert into storage.objects (bucket_id, name) select 'extras-photos', p->>'chemin' from t_ph_g;
select public.hvac_extra_photo_confirmer((select (p->>'id')::uuid from t_ph_g));
select test.ok((select public.hvac_extras_envoyer((select id from t_px)) = 2), 'feuille d''extra envoyée : 2 lignes');
select test.echec($$select public.hvac_extra_decider((select id from t_e1), true)$$, 'le sous-traitant n''approuve pas ses extras', 'réservée');

-- Belleflamme approuve l'oubli du vendeur (avis au vendeur), refuse le hors liste (raison obligatoire)
select test.comme('00000000-0000-0000-0000-00000000000a');
select test.ok((select count(*) = 2 from public.extras_v where projet_id = (select id from t_px) and statut = 'soumis'), 'file d''approbation : 2 extras');
select test.ok((select extras_a_approuver = 2 from public.projets_macro_v where id = (select id from t_px)), 'Macro : 2 extras à approuver');
select public.hvac_extra_decider((select id from t_e1), true);
select test.echec($$select public.hvac_extra_decider((select id from t_e2), false)$$, 'refus sans raison', 'Raison');
select public.hvac_extra_decider((select id from t_e2), false, 'Support standard suffisant selon la fiche technique');
select test.echec($$select public.hvac_extra_decider((select id from t_e1), false, 'trop tard')$$, 'une décision ne se change pas', 'pas en attente');
reset role;
select test.ok((select count(*) = 1 from public.notifications where destinataire_employe_id = '00000000-0000-0000-0000-00000000000c'
                 and type = 'extra_oubli_vendeur'), 'oubli du vendeur approuvé : avis au vendeur');
select test.ok((select count(*) >= 1 from public.notifications where type = 'extras_a_approuver'), 'avis à la planification à l''envoi');
set role authenticated;

-- Facture finale : job en cours, installation + extras approuvés, ensuite plus d'extras
select test.comme('00000000-0000-0000-0000-0000000000c1');
select test.echec(format($$select public.hvac_facture_finale('%s')$$, (select id from t_px)), 'facture finale avant la job', 'en cours ou terminée');
select test.comme('00000000-0000-0000-0000-00000000000a');
update public.projets set statut = 'termine' where id = (select id from t_px);
select test.comme('00000000-0000-0000-0000-0000000000c1');
select test.ok((select public.hvac_facture_finale((select id from t_px)) = 235000), 'facture finale : 2 100 $ + 250 $ approuvés = 2 350 $');
select test.ok((select total_final_cents = 235000 and facture_soumise_le is not null and not extras_ouverts from public.hvac_mes_projets() where id = (select id from t_px)),
               'Mes jobs : facture finale figée, extras fermés');
select test.echec(format($$select public.hvac_extra_ajouter('%s', '{"description":"Oubli","cout_cents":1000,"justification":"Ajout après la facture finale","cause":"autre"}')$$,
  (select id from t_px)), 'pas d''extra après la facture finale', 'Facture finale');
select test.ok((select count(*) = 0 from public.projet_extras), 'le sous-traitant ne lit pas les extras directement');
-- Un autre sous-traitant ou un vendeur n'ajoute rien
select test.comme('00000000-0000-0000-0000-00000000000c');
select test.echec(format($$select public.hvac_extra_ajouter('%s', '{"description":"X","cout_cents":1000,"justification":"Essai d''un vendeur ici","cause":"autre"}')$$,
  (select id from t_px)), 'un vendeur n''ajoute pas d''extra', 'introuvable');
reset role;
\echo 'TESTS EXTRAS PASSÉS'
