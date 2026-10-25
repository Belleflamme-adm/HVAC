-- Dossier de job LogisVert : AHRI, appareils, photos ; blocages ; conservation 5 ans (ADR-084)
\set ON_ERROR_STOP on
set client_min_messages = notice;
create temp table t_di as select id as type_id from public.types_travaux where code = 'INST-MULTI-2T';
grant select on t_di to authenticated;
insert into public.leads (id, succursale_code, contact_nom, contact_tel, ville, type_demande) values
  ('1e000000-0000-0000-0000-0000000000d1', 'RO', 'Julie Gagné', '450-555-0122', 'Bois-des-Filion', 'mural_multi');
set role authenticated;
select test.comme('00000000-0000-0000-0000-00000000000a');
create temp table t_dj as select public.hvac_projet_signe(format($${"lead_id":"1e000000-0000-0000-0000-0000000000d1","devis_numero_mike":"121301",
  "sous_traitant_id":"f2000000-0000-0000-0000-000000000001","lignes":[{"type_ligne":"installation","type_travail_id":"%s"}]}$$,
  (select type_id from t_di))::jsonb) as id;
grant select on t_dj to authenticated;

-- Avant le dépôt : dossier fermé au sous-traitant
select test.comme('00000000-0000-0000-0000-0000000000c1');
select test.echec($$select public.hvac_job_equipement_ajouter((select id from t_dj), '{"role":"exterieur","marque":"M","modele":"X","numero_serie":"S0"}')$$, 'dossier avant le dépôt', 'Dossier fermé');
select test.comme('00000000-0000-0000-0000-00000000000a');
update public.projets set statut = 'en_cours' where id = (select id from t_dj);

select test.comme('00000000-0000-0000-0000-0000000000c1');
select test.ok((select jsonb_array_length(public.hvac_job_dossier((select id from t_dj))->'manques') = 2), 'dossier vide : extérieur, intérieur (AHRI non exigé du sous-traitant)');
select test.echec($$select public.hvac_job_ahri((select id from t_dj), '210987654')$$, 'le sous-traitant n''inscrit pas l''AHRI', 'inscrit par Belleflamme');
-- Belleflamme inscrit l'AHRI
select test.comme('00000000-0000-0000-0000-00000000000a');
select test.echec($$select public.hvac_job_ahri((select id from t_dj), '12-AB')$$, 'AHRI invalide', 'AHRI');
select public.hvac_job_ahri((select id from t_dj), '210 987 654');
select test.comme('00000000-0000-0000-0000-0000000000c1');
create temp table t_ext as select public.hvac_job_equipement_ajouter((select id from t_dj), '{"role":"exterieur","marque":"Mitsubishi","modele":"MXZ-2C20NAHZ","numero_serie":"31u 00123"}') as id;
grant select on t_ext to authenticated;
select test.echec($$select public.hvac_job_equipement_ajouter((select id from t_dj), '{"role":"exterieur","marque":"mitsubishi","modele":"X","numero_serie":"31U00123"}')$$,
  'même numéro de série deux fois', 'déjà inscrit');
select test.echec($$select public.hvac_job_equipement_ajouter((select id from t_dj), '{"role":"interieur","marque":"Mitsubishi","modele":"MSZ-GL09"}')$$, 'série manquante', 'numéro de série');
create temp table t_int as select public.hvac_job_equipement_ajouter((select id from t_dj), '{"role":"interieur","marque":"Mitsubishi","modele":"MSZ-GL09NA","numero_serie":"5ZU45678"}') as id;
grant select on t_int to authenticated;
reset role;
select test.ok((select numero_serie = '31U00123' and ahri = '210987654' from public.equipements_installes where id = (select id from t_ext)),
               'série normalisée, AHRI du système copié sur l''appareil');
set role authenticated;
select test.comme('00000000-0000-0000-0000-0000000000c1');
select test.ok((select jsonb_array_length(public.hvac_job_dossier((select id from t_dj))->'manques') = 4), 'il manque 4 photos (plaque et installé, par appareil)');

-- Photos : préparées au chemin de la job, téléversées sous RLS, confirmées
create temp table t_pj as select e.id as equipement, c as categorie, public.hvac_job_photo_preparer((select id from t_dj), e.id, c, 'image/jpeg', 300000) as p
  from (select id from t_ext union all select id from t_int) e, unnest(array['plaque','installe']) c;
grant select on t_pj to authenticated;
select test.echec($$insert into storage.objects (bucket_id, name) values ('jobs-photos', 'ailleurs/x.jpg')$$, 'téléverser ailleurs', 'row-level security');
insert into storage.objects (bucket_id, name) select 'jobs-photos', p->>'chemin' from t_pj;
select public.hvac_job_photo_confirmer((p->>'id')::uuid) from t_pj;
select test.ok((select jsonb_array_length(public.hvac_job_dossier((select id from t_dj))->'manques') = 0), 'dossier complet');
select test.ok((select jsonb_array_length(public.hvac_job_dossier((select id from t_dj))->'photos') = 4), '4 photos dans le dossier');
-- Retirer une photo rouvre le manque ; on la remet
select public.hvac_job_photo_retirer((select (p->>'id')::uuid from t_pj where categorie = 'plaque' limit 1));
select test.ok((select jsonb_array_length(public.hvac_job_dossier((select id from t_dj))->'manques') = 1), 'photo retirée : 1 manque');
create temp table t_pj2 as select public.hvac_job_photo_preparer((select id from t_dj), (select id from t_ext), 'plaque', 'image/jpeg', 300000) as p;
insert into storage.objects (bucket_id, name) select 'jobs-photos', p->>'chemin' from t_pj2;
select public.hvac_job_photo_confirmer((select (p->>'id')::uuid from t_pj2));

-- Belleflamme : le Macro voit l'état ; « Terminé » passe une fois le dossier complet
select test.comme('00000000-0000-0000-0000-00000000000a');
select test.ok((select dossier_manques = 0 and numero_ahri = '210987654' from public.projets_macro_v where id = (select id from t_dj)), 'Macro : dossier complet');
select test.ok((select count(*) = 4 from storage.objects where bucket_id = 'jobs-photos' and name like (select id from t_dj)::text || '/%'),
               'Simon peut signer les URL des 4 photos montrées (pas la retirée)');
update public.projets set statut = 'termine' where id = (select id from t_dj);
select test.ok((select installation_terminee_le is not null from public.projets where id = (select id from t_dj)), 'date de fin inscrite au passage à Terminé');

-- Facture finale : dossier figé ensuite
select test.comme('00000000-0000-0000-0000-0000000000c1');
select test.ok((select public.hvac_facture_finale((select id from t_dj)) = 210000), 'facture finale avec dossier complet');
select test.echec($$select public.hvac_job_equipement_ajouter((select id from t_dj), '{"role":"interieur","marque":"Mitsubishi","modele":"MSZ","numero_serie":"ZZ1"}')$$, 'dossier figé après la facture finale', 'figé');

-- Un vendeur ne touche pas au dossier ; un compte sans employé ne le lit pas
select test.comme('00000000-0000-0000-0000-00000000000c');
select test.echec($$select public.hvac_job_ahri((select id from t_dj), '210000000')$$, 'un vendeur n''inscrit pas l''AHRI', 'inscrit par Belleflamme');
select test.echec($$select public.hvac_job_equipement_ajouter((select id from t_dj), '{"role":"interieur","marque":"M","modele":"X","numero_serie":"S9"}')$$, 'un vendeur ne modifie pas le dossier', 'introuvable');
select test.comme('00000000-0000-0000-0000-0000000000d9');
select test.echec($$select public.hvac_job_dossier((select id from t_dj))$$, 'compte sans employé', 'introuvable');
select test.echec($$select * from public.hvac_photos_a_purger()$$, 'purge réservée au serveur', 'permission');
reset role;

-- Conservation : rien avant 5 ans ; tout (job et extras) après 5 ans
select test.ok((select count(*) = 0 from public.hvac_photos_a_purger() where chemin like (select id from t_dj)::text || '/%'), 'rien à purger avant 5 ans');
update public.projets set installation_terminee_le = now() - interval '5 years 1 day' where id = (select id from t_dj);
select test.ok((select count(*) = 5 from public.hvac_photos_a_purger() where source = 'job' and chemin like (select id from t_dj)::text || '/%'), '5 ans après Terminé : 5 photos à purger (dont la retirée)');
select test.ok((select public.hvac_photos_purgees(array(select id from public.hvac_photos_a_purger() where source = 'job' and chemin like (select id from t_dj)::text || '/%'), null) = 5),
               'photos marquées purgées');
select test.ok((select count(*) = 0 from public.hvac_photos_a_purger() where chemin like (select id from t_dj)::text || '/%'), 'plus rien à purger');
select test.comme('00000000-0000-0000-0000-00000000000a');
select test.ok((select jsonb_array_length(public.hvac_job_dossier((select id from t_dj))->'manques') = 0), 'dossier toujours complet après la purge (trace gardée)');
\echo 'TESTS DOSSIER DE JOB PASSÉS'
