-- Projet annulé : toutes ses photos (job et extras) sont à purger tout de suite (ADR-094)
\set ON_ERROR_STOP on
set client_min_messages = notice;
create temp table t_pa as select id from public.projets where statut not in ('facture','ferme','annule','termine') order by created_at limit 1;
insert into public.projet_photos (projet_id, categorie, chemin, type_mime, taille_octets, statut, ajoute_par_auth)
select id, 'lignes', format('%s/%s.jpg', id, gen_random_uuid()), 'image/jpeg', 1000, 'televersee', '00000000-0000-0000-0000-00000000000a' from t_pa;
select test.ok((select count(*) = 0 from public.hvac_photos_a_purger() where chemin like (select id from t_pa)::text || '/%'), 'projet actif : rien à purger');
update public.projets set statut = 'annule' where id = (select id from t_pa);
select test.ok((select count(*) = 1 from public.hvac_photos_a_purger() where chemin like (select id from t_pa)::text || '/%'), 'projet annulé : photos à purger tout de suite');
select test.ok((select public.hvac_photos_purgees(array(select id from public.hvac_photos_a_purger() where source = 'job' and chemin like (select id from t_pa)::text || '/%'), null) = 1), 'photos marquées purgées');
select test.ok((select count(*) = 0 from public.hvac_photos_a_purger() where chemin like (select id from t_pa)::text || '/%'), 'plus rien à purger');
\echo 'TESTS PURGE DES PROJETS ANNULÉS PASSÉS'
