-- Demandes de prix aux sous-traitants par lien (ADR-061)
\set ON_ERROR_STOP on
set client_min_messages = notice;
create temp table t_jeton (id uuid, jeton text);
grant all on t_jeton to authenticated, anon;

-- Un vendeur ne peut pas envoyer de demande ; Simon oui
set role authenticated;
select test.comme('00000000-0000-0000-0000-00000000000c');
select test.echec($$select * from public.hvac_creer_demande_prix('f2000000-0000-0000-0000-000000000001',
  array(select id from public.types_travaux where code in ('INST-MURAL-1T-12')))$$, 'vendeur qui envoie une demande', 'Seuls');
select test.comme('00000000-0000-0000-0000-00000000000a');
insert into t_jeton select id, jeton from public.hvac_creer_demande_prix('f2000000-0000-0000-0000-000000000001',
  array(select id from public.types_travaux where code in ('INST-MURAL-1T-12','INST-TETE-MULTI','BIEN-GAZ-ADDON')), 'Merci de remplir avant vendredi');
select test.ok((select length(jeton) = 64 from t_jeton), 'jeton de 64 caractères remis une seule fois');
select test.ok((select count(*) = 3 from public.demandes_prix_lignes l join t_jeton t on t.id = l.demande_id), 'seulement les 3 travaux cochés');
select test.ok((select jeton_hash <> (select jeton from t_jeton limit 1) from public.demandes_prix where id = (select id from t_jeton limit 1)),
               'la base ne garde que l''empreinte du jeton');
-- Simon modifie un titre après l'envoi : la demande garde le texte envoyé
update public.types_travaux set nom = 'Murale 1 tête 12k (titre modifié)' where code = 'INST-MURAL-1T-12';
reset role;
select test.ok((select nom = 'Murale 1 tête, jusqu''à 12 000 BTU' from public.demandes_prix_lignes where code = 'INST-MURAL-1T-12'),
               'la demande garde le titre tel qu''envoyé au sous-traitant');
select test.ok((select count(*) = 1 from public.journal_audit where table_nom = 'types_travaux' and action = 'update' and apres->>'code' = 'INST-MURAL-1T-12'),
               'la modification d''une ligne de la liste est journalisée');

-- Le sous-traitant (sans compte) lit et remplit
set role anon;
reset request.jwt.claims;
select test.echec($$select public.hvac_demande_prix_lire('mauvais-jeton')$$, 'jeton invalide', 'invalide');
select test.ok((select jsonb_array_length(public.hvac_demande_prix_lire((select jeton from t_jeton limit 1))->'lignes') = 3), 'lecture par le lien');
select test.echec($$select count(*) from public.demandes_prix$$, 'anon qui lit la table directement');
select test.echec(format($$select public.hvac_demande_prix_soumettre(%L, '[]', 'Jean Sous-Traitant', 'data:image/png;base64,AAAA', true)$$, (select jeton from t_jeton limit 1)),
                  'lignes sans prix', 'Chaque ligne');
select test.echec(format($$select public.hvac_demande_prix_soumettre(%L, '[]', 'Jean Sous-Traitant', 'data:image/png;base64,AAAA', false)$$, (select jeton from t_jeton limit 1)),
                  'sans attestation de validité d''un an', 'un an');
reset role;
create temp table t_lignes as
  select jsonb_agg(jsonb_build_object('id', id, 'cout_cents', case code when 'INST-MURAL-1T-12' then 125000 when 'INST-TETE-MULTI' then 60000 end,
                                      'non_offert', code = 'BIEN-GAZ-ADDON', 'note', case when code = 'BIEN-GAZ-ADDON' then 'Pas de licence gaz' end)) as j
    from public.demandes_prix_lignes where demande_id = (select id from t_jeton limit 1);
grant all on t_lignes to anon;
set role anon;
select test.ok((select (public.hvac_demande_prix_soumettre((select jeton from t_jeton limit 1), (select j from t_lignes), 'Jean Sous-Traitant (FICTIF)',
                 'data:image/png;base64,iVBORw0KGgo=', true)->>'ok')::boolean), 'soumission signée');
select test.echec(format($$select public.hvac_demande_prix_soumettre(%L, '[]', 'Autre', 'data:image/png;base64,AAAA', true)$$, (select jeton from t_jeton limit 1)),
                  'deuxième soumission avec le même lien', 'déjà été envoyée');
reset role;
select test.ok((select statut = 'recue' and valide_jusqu = ((signe_le at time zone 'America/Toronto')::date + interval '1 year')::date
                  from public.demandes_prix where id = (select id from t_jeton limit 1)), 'prix valides un an complet à partir de la signature');
select test.ok((select count(*) >= 2 from public.notifications where type = 'prix_recus'), 'Simon et Mike sont avisés');
select test.echec($$update public.demandes_prix set signataire_nom = 'Faux' where id = (select id from t_jeton limit 1)$$, 'falsifier la signature', 'ne se modifie pas');
select test.echec($$update public.demandes_prix_lignes set cout_cents = 1 where demande_id = (select id from t_jeton limit 1)$$, 'changer un prix reçu', 'lien du sous-traitant');

-- Approbation par Simon : tarifs datés, valides un an ; la ligne non offerte n'en crée pas
set role authenticated;
select test.comme('00000000-0000-0000-0000-00000000000c');
select test.echec(format($$select public.hvac_approuver_demande_prix(%L)$$, (select id from t_jeton limit 1)), 'vendeur qui approuve', 'Seuls');
select test.comme('00000000-0000-0000-0000-00000000000a');
select test.ok((select public.hvac_approuver_demande_prix((select id from t_jeton limit 1)) = 2), 'approbation : 2 tarifs créés');
reset role;
select test.ok((select count(*) = 2 from public.tarifs_sous_traitants where demande_prix_id = (select id from t_jeton limit 1) and valide_jusqu is not null),
               'tarifs liés à la demande, avec leur échéance');

-- Une demande non répondue peut être annulée ; le lien ne fonctionne plus
set role authenticated;
select test.comme('00000000-0000-0000-0000-00000000000a');
insert into t_jeton select id, jeton from public.hvac_creer_demande_prix('f2000000-0000-0000-0000-000000000001', array(select id from public.types_travaux where code = 'SERV-HEURE'));
update public.demandes_prix set statut = 'annulee' where id = (select id from t_jeton offset 1);
reset role;
set role anon;
select test.echec(format($$select public.hvac_demande_prix_lire(%L)$$, (select jeton from t_jeton offset 1)), 'lien d''une demande annulée', 'annulé');
reset role;

\echo 'TESTS DEMANDES DE PRIX PASSÉS'
