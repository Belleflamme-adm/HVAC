-- Photos des extras : brouillon seulement, 5 au plus, fichiers privés sous RLS (ADR-082)
\set ON_ERROR_STOP on
set client_min_messages = notice;
create temp table t_ph_inst as select id as type_id from public.types_travaux where code = 'INST-MULTI-2T';
grant select on t_ph_inst to authenticated;
insert into public.leads (id, succursale_code, contact_nom, contact_tel, ville, type_demande) values
  ('1e000000-0000-0000-0000-0000000000c1', 'RO', 'Marie Pelletier', '450-555-0155', 'Lorraine', 'mural_multi');
set role authenticated;
select test.comme('00000000-0000-0000-0000-00000000000a');
create temp table t_pp as select public.hvac_projet_signe(format($${"lead_id":"1e000000-0000-0000-0000-0000000000c1","devis_numero_mike":"121201",
  "sous_traitant_id":"f2000000-0000-0000-0000-000000000001","lignes":[{"type_ligne":"installation","type_travail_id":"%s"}]}$$,
  (select type_id from t_ph_inst))::jsonb) as id;
grant select on t_pp to authenticated;
update public.projets set statut = 'planifie' where id = (select id from t_pp);

select test.comme('00000000-0000-0000-0000-0000000000c1');
create temp table t_ex as select public.hvac_extra_ajouter((select id from t_pp),
  '{"description":"Support mural renforcé","cout_cents":18000,"justification":"Mur de brique trop friable pour le support","cause":"imprevu_chantier"}') as id;
grant select on t_ex to authenticated;
select test.echec($$select public.hvac_extra_photo_preparer((select id from t_ex), 'application/pdf', 1000)$$, 'type refusé', 'JPEG');
select test.echec($$select public.hvac_extra_photo_preparer((select id from t_ex), 'image/jpeg', 6000000)$$, 'photo trop lourde', 'lourde');
create temp table t_ph as select public.hvac_extra_photo_preparer((select id from t_ex), 'image/jpeg', 350000) as p;
grant select on t_ph to authenticated;
select test.ok((select (p->>'chemin') like (select id from t_pp)::text || '/' || (select id from t_ex)::text || '/%.jpg' from t_ph), 'chemin : projet/extra/uuid.jpg');
-- Pas de confirmation sans fichier ; téléversement permis seulement au chemin préparé
select test.echec($$select public.hvac_extra_photo_confirmer((select (p->>'id')::uuid from t_ph))$$, 'confirmer sans fichier', 'non reçu');
select test.echec($$insert into storage.objects (bucket_id, name) values ('extras-photos', 'autre/chemin.jpg')$$, 'téléverser ailleurs', 'row-level security');
insert into storage.objects (bucket_id, name) select 'extras-photos', p->>'chemin' from t_ph;
select public.hvac_extra_photo_confirmer((select (p->>'id')::uuid from t_ph));
select test.ok((select count(*) = 1 from public.hvac_extra_photos((select id from t_ex))), 'le sous-traitant voit sa photo');
select test.ok((select count(*) = 1 from storage.objects where bucket_id = 'extras-photos' and name = (select p->>'chemin' from t_ph)), 'il peut signer l''URL de sa photo (SELECT permis)');
select test.ok((select (x->>'nb_photos')::int = 1 from public.hvac_mes_projets() j, jsonb_array_elements(j.extras) x where j.id = (select id from t_pp)),
               'Mes jobs : 1 photo sur l''extra');
-- 5 au plus
select test.ok((select count(*) = 4 from (select public.hvac_extra_photo_preparer((select id from t_ex), 'image/jpeg', 1000) from generate_series(1, 4)) s), '4 photos de plus : 5 en tout');
select test.echec($$select public.hvac_extra_photo_preparer((select id from t_ex), 'image/jpeg', 1000)$$, '6e photo', '5 photos');
-- Imprévu de sa liste sans photo : refusé à l'envoi ; un oubli du vendeur de sa liste part sans photo
create temp table t_imp as select public.hvac_extra_ajouter((select id from t_pp),
  format('{"type_travail_id":"%s","cause":"imprevu_chantier"}', (select type_id from t_ph_inst))::jsonb) as id;
select test.echec($$select public.hvac_extras_envoyer((select id from t_pp))$$, 'imprévu sans photo', 'Photo obligatoire');
select public.hvac_extra_retirer((select id from t_imp));
-- Après l'envoi : plus d'ajout ni de retrait
select test.ok((select public.hvac_extras_envoyer((select id from t_pp)) = 1), 'extra envoyé avec sa photo');
select test.echec($$select public.hvac_extra_photo_preparer((select id from t_ex), 'image/jpeg', 1000)$$, 'photo après l''envoi', 'brouillon');
select test.echec($$select public.hvac_extra_photo_retirer((select (p->>'id')::uuid from t_ph))$$, 'retirer après l''envoi', 'ne se retire plus');

-- Belleflamme voit la photo ; un autre compte non
select test.comme('00000000-0000-0000-0000-00000000000a');
select test.ok((select nb_photos = 1 from public.extras_v where id = (select id from t_ex)), 'file d''approbation : 1 photo');
select test.ok((select count(*) = 1 from public.hvac_extra_photos((select id from t_ex))), 'Simon voit la photo');
select test.ok((select count(*) = 1 from storage.objects where bucket_id = 'extras-photos' and name = (select p->>'chemin' from t_ph)), 'Simon peut signer l''URL');
reset role;
insert into auth.users(id, email) values ('00000000-0000-0000-0000-0000000000d9', 'personne@test');
set role authenticated;
select test.comme('00000000-0000-0000-0000-0000000000d9');
select test.ok((select count(*) = 0 from storage.objects where bucket_id = 'extras-photos'), 'compte sans employé : aucune photo');
select test.echec($$select * from public.hvac_extra_photos((select id from t_ex))$$, 'compte sans employé : pas de liste', 'introuvable');
reset role;
\echo 'TESTS PHOTOS DES EXTRAS PASSÉS'
