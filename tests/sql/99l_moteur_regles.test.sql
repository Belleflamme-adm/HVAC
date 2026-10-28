-- Moteur de règles : réponse éclair, escalade, séquence, rappels de visite, avis, subvention, appel manqué, LCAP (ADR-090)
\set ON_ERROR_STOP on
set client_min_messages = notice;
grant usage on schema test to service_role;
grant execute on all functions in schema test to service_role;
-- Outil : faire « passer le temps » pour une exécution (la base ne peut pas avancer son horloge)
create or replace function test.echu(p_lead uuid, p_code text) returns void language sql as $$
  update public.executions x set prochaine_le = now() - interval '1 second' from public.regles r
   where r.id = x.regle_id and r.code = p_code and x.lead_id = p_lead and x.statut = 'active' $$;
create or replace function test.echu_projet(p_projet uuid, p_code text) returns void language sql as $$
  update public.executions x set prochaine_le = now() - interval '1 second' from public.regles r
   where r.id = x.regle_id and r.code = p_code and x.projet_id = p_projet and x.statut = 'active' $$;
create or replace function test.executer() returns jsonb language sql as $$ select public.hvac_regles_executer() $$;
grant execute on all functions in schema test to service_role;
create or replace function test.statut(p_lead uuid, p_code text) returns text language sql as $$
  select x.statut from public.executions x join public.regles r on r.id = x.regle_id where r.code = p_code and x.lead_id = p_lead $$;

-- Heures ouvrables : un lead reçu dimanche compte à partir de lundi 8 h 30 (heure de Montréal)
select test.ok(app.plus_minutes_ouvrables('RO', '2026-11-01 14:00-05', 15) = '2026-11-02 08:45-05', 'dimanche 14 h + 15 min ouvrables = lundi 8 h 45');
select test.ok(app.plus_minutes_ouvrables('RO', '2026-11-02 16:50-05', 15) = '2026-11-03 08:35-05', 'lundi 16 h 50 + 15 min = mardi 8 h 35');
select test.ok(app.plus_minutes_ouvrables('RO', '2026-11-02 10:00-05', 15) = '2026-11-02 10:15-05', 'pendant les heures : minutes réelles');
select test.ok(app.e164('(450) 555-0199') = '+14505550199' and app.e164('1-450-555-0199') = '+14505550199' and app.e164('5550199') is null, 'téléphone E.164');

-- 1. Lead reçu : réponse éclair (texto + courriel simulés), consentement tacite 6 mois, escalade et séquence armées
insert into public.crm_vendeurs (employe_id, ordre) values ('00000000-0000-0000-0000-00000000000c', 9) on conflict do nothing;
insert into public.leads (id, succursale_code, source, contact_nom, contact_tel, contact_courriel, type_demande) values
  ('1e000000-0000-0000-0000-000000000101', 'RO', 'facebook', 'Line Poirier', '450 555 0101', 'line@exemple.invalid', 'mural_simple');
select test.ok((select count(*) = 3 from public.executions where lead_id = '1e000000-0000-0000-0000-000000000101'), 'lead : 3 règles armées (éclair, escalade, séquence)');
select test.ok((select type = 'tacite_demande' and expire_le = obtenu_le + interval '6 months' and tel_e164 = '+14505550101'
                  from public.consentements where lead_id = '1e000000-0000-0000-0000-000000000101'), 'consentement tacite 6 mois (demande)');
set role service_role;
select test.executer();
reset role;
select test.ok((select count(*) = 2 and bool_and(automatique and statut = 'simule' and direction = 'sortant')
                  from public.communications where lead_id = '1e000000-0000-0000-0000-000000000101'), 'réponse éclair : texto et courriel simulés dans l''historique');
select test.ok((select contenu like 'Bonjour Line, ici Belleflamme Rosemère%thermopompe murale%' from public.communications
                  where lead_id = '1e000000-0000-0000-0000-000000000101' and canal = 'texto'), 'texte rendu avec les variables');
select test.ok(test.statut('1e000000-0000-0000-0000-000000000101', 'lead_escalade') = 'active', 'escalade en attente de 15 min ouvrables');

-- 2. Escalade : 15 min sans contact, le directeur (Simon, faute de gérant à Rosemère) reçoit l'avis et la tâche
select test.echu('1e000000-0000-0000-0000-000000000101', 'lead_escalade');
set role service_role;
select test.executer();
reset role;
select test.ok((select count(*) >= 1 from public.taches where lead_id = '1e000000-0000-0000-0000-000000000101'
                  and assigne_employe_id = '00000000-0000-0000-0000-00000000000a' and titre like 'Appeler Line%'), 'escalade : tâche au directeur');
select test.ok((select count(*) >= 1 from public.notifications where type = 'regle' and titre = 'Lead sans contact depuis 15 min'), 'escalade : avis');
select test.ok(test.statut('1e000000-0000-0000-0000-000000000101', 'lead_escalade') = 'terminee', 'escalade terminée');

-- 3. Séquence : le vendeur appelle (pas d'arrêt : le client n'a pas répondu) ; le client répond par texto : arrêt
insert into public.lead_activites (lead_id, type, resultat, employe_id) values ('1e000000-0000-0000-0000-000000000101', 'appel', 'pas_de_reponse', '00000000-0000-0000-0000-00000000000c');
select test.ok(test.statut('1e000000-0000-0000-0000-000000000101', 'lead_sequence') = 'active', 'appel sans réponse : la séquence continue');
select test.echu('1e000000-0000-0000-0000-000000000101', 'lead_sequence');
set role service_role;
select test.executer();
reset role;
select test.ok((select count(*) = 1 from public.communications where lead_id = '1e000000-0000-0000-0000-000000000101' and contenu like '%Avez-vous un moment%'), 'J+1 : texto de relance');
insert into public.communications (lead_id, canal, direction, statut, coordonnee_client, debut, contenu)
values ('1e000000-0000-0000-0000-000000000101', 'texto', 'entrant', 'recu', '4505550101', now(), 'Oui, jeudi après-midi');
select test.ok(test.statut('1e000000-0000-0000-0000-000000000101', 'lead_sequence') = 'arretee', 'le client répond : séquence arrêtée');

-- 4. Rappels de visite (date de Pointage) : 24 h et 2 h avant ; visite déplacée : rappels refaits
insert into public.lead_activites (lead_id, type, visite_le, employe_id) values
  ('1e000000-0000-0000-0000-000000000101', 'visite_planifiee', now() + interval '3 days', '00000000-0000-0000-0000-00000000000c');
set role service_role;
select test.executer();
reset role;
select test.ok((select prochaine_le between now() + interval '47 hours' and now() + interval '49 hours' from public.executions x join public.regles r on r.id = x.regle_id
                  where r.code = 'rappel_visite' and x.lead_id = '1e000000-0000-0000-0000-000000000101' and x.statut = 'active'), 'rappel prévu 24 h avant la visite');
insert into public.lead_activites (lead_id, type, visite_le, employe_id) values
  ('1e000000-0000-0000-0000-000000000101', 'visite_planifiee', now() + interval '5 hours', '00000000-0000-0000-0000-00000000000c');
select test.ok((select count(*) = 1 from public.executions x join public.regles r on r.id = x.regle_id
                  where r.code = 'rappel_visite' and x.lead_id = '1e000000-0000-0000-0000-000000000101' and x.statut = 'arretee'), 'visite déplacée : ancien rappel arrêté');
set role service_role;
select test.executer();
reset role;
select test.ok((select count(*) = 1 from public.communications where lead_id = '1e000000-0000-0000-0000-000000000101' and contenu like 'Rappel : %'),
               'visite dans 5 h : rappel « 24 h » envoyé tout de suite (moment passé), rappel 2 h en attente');

-- 5. LCAP : avis Google (commercial) sauté sans consentement ; STOP par texto = désabonnement
insert into public.communications (lead_id, canal, direction, statut, coordonnee_client, debut, contenu)
values ('1e000000-0000-0000-0000-000000000101', 'texto', 'entrant', 'recu', '450-555-0101', now(), 'STOP');
select test.ok((select count(*) = 1 from public.desabonnements where tel_e164 = '+14505550101'), 'STOP : désabonnement');
select test.ok(not app.peut_envoyer_commercial('+14505550101', null, 'sms'), 'plus de texto commercial après STOP');
select test.ok(app.peut_envoyer_commercial(null, 'line@exemple.invalid', 'courriel'), 'le courriel reste permis (consentement tacite)');

-- 6. Projet terminé : demande d'avis 2 jours plus tard, une fois par 12 mois ; consentement tacite d'achat 2 ans
update public.succursales set lien_avis_google = 'https://g.page/r/belleflamme-rosemere/review' where code = 'RO';
insert into public.leads (id, succursale_code, source, contact_nom, contact_tel, contact_courriel, type_demande) values
  ('1e000000-0000-0000-0000-000000000102', 'RO', 'google', 'Marc Ouellette', '450-555-0102', 'marc@exemple.invalid', 'central');
set role authenticated;
select test.comme('00000000-0000-0000-0000-00000000000a');
create temp table t_pr as select public.hvac_projet_signe('{"lead_id":"1e000000-0000-0000-0000-000000000102","devis_numero_mike":"121501"}') as id;
reset role;
select test.ok((select count(*) = 1 from public.consentements c join public.projets p on p.client_id = c.client_id where p.id = (select id from t_pr)
                  and c.type = 'tacite_achat' and c.expire_le > now() + interval '23 months'), 'consentement tacite 2 ans (achat)');
update public.projets set statut = 'termine' where id = (select id from t_pr);
set role service_role;
select test.executer();   -- arme l'attente de 2 jours
reset role;
select test.ok((select prochaine_le > now() + interval '47 hours' from public.executions x join public.regles r on r.id = x.regle_id
                  where r.code = 'avis_google' and x.projet_id = (select id from t_pr)), 'avis : attente de 2 jours');
select test.echu_projet((select id from t_pr), 'avis_google');
set role service_role;
select test.executer();
reset role;
select test.ok((select count(*) = 2 from public.communications c join public.projets p on p.client_id = c.client_id
                  where p.id = (select id from t_pr) and c.automatique and c.contenu like '%https://g.page/r/belleflamme-rosemere/review%'),
               'avis Google : texto et courriel, avec le lien de la succursale');
select test.ok((select count(*) = 1 from public.communications c join public.projets p on p.client_id = c.client_id
                  where p.id = (select id from t_pr) and c.canal = 'texto' and c.contenu like '%STOP pour vous désabonner.'), 'message commercial : mention de désabonnement');
select test.ok((select count(*) = 1 from public.avis_demandes where projet_id = (select id from t_pr)), 'demande d''avis notée');

-- 7. Subvention : chaque étape envoie un texto
set role authenticated;
select test.comme('00000000-0000-0000-0000-00000000000a');
select public.hvac_subvention_etape((select id from t_pr), 'deposee');
reset role;
set role service_role;
select test.executer();
reset role;
select test.ok((select count(*) = 1 from public.communications c join public.projets p on p.client_id = c.client_id
                  where p.id = (select id from t_pr) and c.contenu like '%votre demande LogisVert est déposée%'), 'subvention déposée : texto au client');

-- 8. Appel manqué : nouveau lead, texto 1 minute plus tard, une seule fois par numéro par jour ; pas de réponse éclair en double
set role service_role;
select test.ok((select public.hvac_appel_manque('{"telephone":"819-555-0103","succursale_code":"GA"}') ? 'lead_id'), 'appel manqué reçu');
select public.hvac_appel_manque('{"telephone":"8195550103","succursale_code":"GA"}');
reset role;
create temp table t_am as select id from public.leads where app.e164(contact_tel) = '+18195550103';
select test.ok((select count(*) = 1 from t_am), 'un seul lead pour deux appels manqués');
select test.ok((select count(*) = 1 from public.executions x join public.regles r on r.id = x.regle_id where r.code = 'appel_manque' and x.lead_id = (select id from t_am)),
               'une seule exécution « appel manqué » par numéro par jour');
select test.ok((select count(*) = 0 from public.executions x join public.regles r on r.id = x.regle_id where r.code = 'lead_eclair' and x.lead_id = (select id from t_am)),
               'pas de réponse éclair en double pour un appel manqué');
select test.ok(test.statut((select id from t_am), 'lead_sequence') = 'active', 'l''appel manqué n''arrête pas la séquence');
set role service_role;
select test.executer();   -- arme l'attente d'une minute
reset role;
select test.ok((select count(*) = 0 from public.communications where lead_id = (select id from t_am) and automatique), 'rien avant la minute d''attente');
select test.echu((select id from t_am), 'appel_manque');
set role service_role;
select test.executer();
reset role;
select test.ok((select count(*) = 1 from public.communications where lead_id = (select id from t_am) and contenu like '%désolés pour l''appel manqué%'), 'texto après appel manqué');

-- 9. Échec d'une exécution : journalisé, alerte à Simon et Mike, relance possible
update public.regles set etapes = '[{"type":"sms","texte":"{prenom}"}]' where code = 'subvention_suivi';
insert into public.execution_journal (execution_id, etape, action, resultat) select id, 0, 'test', 'ok' from public.executions limit 1;
create or replace function app.contexte_execution(x public.executions) returns jsonb language plpgsql as $$ begin raise exception 'panne simulée'; end $$;
set role authenticated;
select test.comme('00000000-0000-0000-0000-00000000000a');
select public.hvac_subvention_etape((select id from t_pr), 'acceptee');
reset role;
set role service_role;
select test.ok((select (test.executer()->>'echecs')::int >= 1), 'panne : exécution en échec');
reset role;
select test.ok((select count(*) >= 2 from public.notifications where type = 'regle_echec'), 'alerte d''échec à Simon et Mike');
select test.ok((select echecs >= 1 from public.regles_suivi_v where code = 'subvention_suivi'), 'suivi : échec compté');

-- 10. Règle cassée refusée ; un vendeur ne modifie pas les règles
select test.echec($$update public.regles set etapes = '[{"type":"teleporter"}]' where code = 'lead_eclair'$$, 'étape inconnue', 'Étape inconnue');
set role authenticated;
select test.comme('00000000-0000-0000-0000-00000000000c');
update public.regles set actif = false where code = 'lead_eclair';
reset role;
select test.ok((select actif from public.regles where code = 'lead_eclair'), 'un vendeur ne désactive pas une règle');
-- 11. Tâche faite (assigné seulement), heures et lien d'avis (Simon et Mike seulement)
set role authenticated;
select test.comme('00000000-0000-0000-0000-00000000000c');
select test.echec($$select public.hvac_tache_faite((select id from public.taches where assigne_employe_id = '00000000-0000-0000-0000-00000000000a' limit 1))$$, 'tâche d''un autre', 'introuvable');
select test.echec($$select public.hvac_heures('RO', '[]')$$, 'un vendeur ne change pas les heures', 'Réservé');
select test.comme('00000000-0000-0000-0000-00000000000a');
select public.hvac_tache_faite((select id from public.taches where assigne_employe_id = '00000000-0000-0000-0000-00000000000a' and faite_le is null limit 1));
select public.hvac_heures('GA', '[{"jour":1,"ouvre":"09:00","ferme":"17:00"}]');
select test.echec($$select public.hvac_lien_avis('RO', 'http://faux')$$, 'lien non https', 'https');
reset role;
select test.ok((select count(*) = 1 from public.heures_succursales where succursale_code = 'GA'), 'heures de Gatineau remplacées (lundi seulement)');
select test.ok((select count(*) >= 1 from public.taches where faite_le is not null and faite_par = '00000000-0000-0000-0000-00000000000a'), 'tâche faite');
\echo 'TESTS MOTEUR DE RÈGLES PASSÉS'
