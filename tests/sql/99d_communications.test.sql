-- Communications avec le client : historique, écoute journalisée, conservation (ADR-067)
\set ON_ERROR_STOP on
set client_min_messages = notice;
insert into public.leads (id, succursale_code, client_id, contact_nom) values
  ('1e000000-0000-0000-0000-000000000001', 'RO', '30000000-0000-0000-0000-000000000001', 'Client test');
insert into public.communications (id, lead_id, canal, direction, employe_id, debut, duree_s, enregistrement_ref, enregistrement_duree_s, transcription, resume) values
  ('c0000000-0000-0000-0000-000000000001', '1e000000-0000-0000-0000-000000000001', 'appel', 'sortant', '00000000-0000-0000-0000-00000000000c',
   now() - interval '400 days', 312, 'mike:enreg:ancien', 310, 'Bonjour, ici Belleflamme...', 'Client intéressé par une murale');
insert into public.communications (id, client_id, canal, direction, debut, contenu) values
  ('c0000000-0000-0000-0000-000000000002', '30000000-0000-0000-0000-000000000001', 'texto', 'entrant', now() - interval '1 day', 'Oui demain 10 h');
set role authenticated;

-- Un vendeur voit l'historique du client, y compris l'appel fait au stade du lead
select test.comme('00000000-0000-0000-0000-00000000000c');
select test.ok((select count(*) = 2 from public.communications_v where client_id = '30000000-0000-0000-0000-000000000001'),
               'fiche client : appels du lead et textos du client dans le même historique');
select test.ok((select a_enregistrement and employe_nom is not null from public.communications_v where id = 'c0000000-0000-0000-0000-000000000001'),
               'appel : enregistrement disponible, employé nommé');
select test.ok((select public.hvac_ecouter_enregistrement('c0000000-0000-0000-0000-000000000001') = 'mike:enreg:ancien'), 'le vendeur écoute l''enregistrement');
select test.echec($$insert into public.communications (client_id, canal, direction, debut) values ('30000000-0000-0000-0000-000000000001', 'appel', 'sortant', now())$$,
                  'le navigateur n''écrit pas de communication');

-- Le sous-traitant ne voit rien et n'écoute rien
select test.comme('00000000-0000-0000-0000-0000000000c1');
select test.ok((select count(*) = 0 from public.communications_v), 'le sous-traitant ne voit pas les communications');
select test.echec($$select public.hvac_ecouter_enregistrement('c0000000-0000-0000-0000-000000000001')$$, 'le sous-traitant n''écoute pas', 'Accès refusé');
reset role;

select test.ok((select count(*) = 1 from public.journal_audit where action = 'lecture' and table_nom = 'communications'
                  and ligne_id = 'c0000000-0000-0000-0000-000000000001' and employe_id = '00000000-0000-0000-0000-00000000000c'),
               'chaque écoute est journalisée (qui, quel appel)');

-- Conservation : rien n'est effacé tant que la règle de Mike n'est pas confirmée
select test.ok((select app.purger_enregistrements() = 0), 'règle de conservation vide : rien n''est effacé');
update public.parametres set valeur = '365' where cle = 'conservation_enregistrements_jours';
select test.ok((select app.purger_enregistrements() = 1), 'règle à 365 jours : l''enregistrement de 400 jours est effacé');
select test.ok((select enregistrement_ref is null and transcription is not null and duree_s = 312 from public.communications
                 where id = 'c0000000-0000-0000-0000-000000000001'), 'après effacement : l''heure, la durée et la transcription restent');
update public.parametres set valeur = 'null' where cle = 'conservation_enregistrements_jours';
\echo 'TESTS COMMUNICATIONS PASSÉS'
