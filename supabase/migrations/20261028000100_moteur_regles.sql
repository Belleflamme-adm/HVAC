-- Moteur de règles (ADR-090) : les automatisations sont des DONNÉES (déclencheur, conditions, étapes), pas du code.
-- Une seule tâche planifiée (regles-cron, chaque minute) exécute les étapes dues. Chaque exécution est journalisée ;
-- un échec alerte Simon, Mike et la planification (pas de panne silencieuse).
-- Envois : SIMULÉS d'ici la greffe (décision de Simon). Les textos et courriels vont dans l'historique du client avec
-- le statut « simulé » ; paramètre envois_reels=true à la greffe : statut « en file », puis Twilio et courriel de Mike.
-- Consentement (LCAP) : un message commercial n'est envoyé qu'avec un consentement valide (tacite 2 ans après un achat,
-- 6 mois après une demande d'information, ou exprès), jamais après un désabonnement. À valider par un professionnel.

-- ---------------------------------------------------------------------------
-- 1. Outils : téléphone E.164, heures ouvrables par succursale
-- ---------------------------------------------------------------------------
create or replace function app.e164(p text) returns text
language sql immutable as $$
  select case
    when length(d) = 10 then '+1' || d
    when length(d) = 11 and left(d, 1) = '1' then '+' || d
    else null end
  from (select regexp_replace(coalesce(p, ''), '\D', '', 'g') as d) x
$$;
create index leads_tel_e164 on public.leads (app.e164(contact_tel));
create index clients_tel_e164 on public.clients (app.e164(telephone));

create table public.heures_succursales (
  succursale_code text not null references public.succursales(code),
  jour            smallint not null check (jour between 0 and 6),   -- 0 = dimanche (comme extract(dow))
  ouvre           time not null,
  ferme           time not null check (ferme > ouvre),
  primary key (succursale_code, jour)
);
alter table public.heures_succursales enable row level security;
create policy lecture on public.heures_succursales for select to authenticated using (app.est_interne());
create policy gestion on public.heures_succursales for all to authenticated using (app.est_admin()) with check (app.est_admin());
-- Heures de Simon (28 oct. 2026), toutes les succursales : lun-mer 9 h à 17 h, jeu-ven 9 h à 19 h, sam 10 h à 16 h, dim fermé
insert into public.heures_succursales (succursale_code, jour, ouvre, ferme)
select s.code, j, case when j = 6 then '10:00' else '09:00' end::time,
       case when j = 6 then '16:00' when j in (4, 5) then '19:00' else '17:00' end::time
  from public.succursales s cross join generate_series(1, 6) j
on conflict do nothing;

-- Ajoute des minutes OUVRABLES (heures de la succursale, heure de Montréal). Sans horaire : minutes réelles.
create or replace function app.plus_minutes_ouvrables(p_succ text, p_depart timestamptz, p_minutes integer) returns timestamptz
language plpgsql stable as $$
declare
  t timestamp := p_depart at time zone 'America/Toronto'; reste numeric := p_minutes; h record; debut timestamp; fin timestamp; n int := 0;
begin
  if not exists (select 1 from public.heures_succursales where succursale_code = p_succ) then return p_depart + make_interval(mins => p_minutes); end if;
  loop
    n := n + 1; if n > 60 then return p_depart + make_interval(mins => p_minutes); end if;
    select * into h from public.heures_succursales where succursale_code = p_succ and jour = extract(dow from t)::int;
    if h.succursale_code is not null then
      debut := date_trunc('day', t) + h.ouvre; fin := date_trunc('day', t) + h.ferme;
      if t < debut then t := debut; end if;
      if t < fin then
        if t + make_interval(secs => reste * 60) <= fin then return (t + make_interval(secs => reste * 60)) at time zone 'America/Toronto'; end if;
        reste := reste - extract(epoch from (fin - t)) / 60;
      end if;
    end if;
    t := date_trunc('day', t) + interval '1 day';
  end loop;
end $$;

-- Prochain moment ouvert à partir de p (p lui-même s'il est pendant les heures)
create or replace function app.prochaine_ouverture(p_succ text, p timestamptz) returns timestamptz
language sql stable as $$ select app.plus_minutes_ouvrables(p_succ, p, 0) $$;

-- ---------------------------------------------------------------------------
-- 2. Consentements (LCAP) et désabonnements
-- ---------------------------------------------------------------------------
create table public.consentements (
  id          uuid primary key default gen_random_uuid(),
  lead_id     uuid references public.leads(id),
  client_id   uuid references public.clients(id),
  tel_e164    text,
  courriel    text,
  type        text not null check (type in ('tacite_demande','tacite_achat','expres')),
  canal       text not null default 'tous' check (canal in ('sms','courriel','tous')),
  source      text not null,                 -- ex. « lead Facebook », « soumission #120815 signée », « formulaire »
  obtenu_le   timestamptz not null default now(),
  expire_le   timestamptz,                   -- null : exprès (jusqu'au retrait)
  created_at  timestamptz not null default now(),
  check (tel_e164 is not null or courriel is not null)
);
create index consentements_tel on public.consentements (tel_e164);
create index consentements_courriel on public.consentements (lower(courriel));
create table public.desabonnements (
  id         uuid primary key default gen_random_uuid(),
  tel_e164   text,
  courriel   text,
  canal      text not null default 'tous' check (canal in ('sms','courriel','tous')),
  source     text not null,                  -- ex. « texto STOP », « lien de désabonnement », « demande au téléphone »
  le         timestamptz not null default now(),
  check (tel_e164 is not null or courriel is not null)
);
create index desabonnements_tel on public.desabonnements (tel_e164);
alter table public.consentements enable row level security;
alter table public.desabonnements enable row level security;
create policy lecture on public.consentements for select to authenticated using (app.est_interne());
create policy lecture on public.desabonnements for select to authenticated using (app.est_interne());
create policy ajout on public.desabonnements for insert to authenticated with check (app.est_interne());   -- « ne m'écrivez plus » au téléphone

create or replace function app.peut_envoyer_commercial(p_tel text, p_courriel text, p_canal text) returns boolean
language sql stable security definer set search_path = public as $$
  select not exists (select 1 from public.desabonnements d
                      where d.canal in (p_canal, 'tous')
                        and ((p_tel is not null and d.tel_e164 = p_tel) or (p_courriel is not null and lower(d.courriel) = lower(p_courriel))))
     and exists (select 1 from public.consentements c
                  where c.canal in (p_canal, 'tous') and (c.expire_le is null or c.expire_le > now())
                    and ((p_tel is not null and c.tel_e164 = p_tel) or (p_courriel is not null and lower(c.courriel) = lower(p_courriel))))
$$;

-- ---------------------------------------------------------------------------
-- 3. Tâches (créées par les règles ou à la main) et messages automatiques dans l'historique
-- ---------------------------------------------------------------------------
create table public.taches (
  id                 uuid primary key default gen_random_uuid(),
  titre              text not null,
  details            text,
  lead_id            uuid references public.leads(id),
  projet_id          uuid references public.projets(id),
  assigne_employe_id uuid references public.employes(id),
  echeance           timestamptz,
  faite_le           timestamptz,
  faite_par          uuid references public.employes(id),
  execution_id       uuid,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);
call app.preparer_table('public.taches', false);
create index taches_assigne on public.taches (assigne_employe_id) where faite_le is null;
alter table public.taches enable row level security;
create policy lecture on public.taches for select to authenticated
  using (assigne_employe_id = app.employe_id() or app.est_admin() or app.est_planification());
-- Une tâche se marque faite par hvac_tache_faite seulement (rien d'autre ne se modifie)

alter table public.communications drop constraint communications_statut_check;
alter table public.communications add constraint communications_statut_check
  check (statut in ('termine','manque','messagerie','envoye','recu','echec','simule','en_file'));
alter table public.communications add column automatique boolean not null default false, add column execution_id uuid;
create or replace view public.communications_v as
select c.id, coalesce(c.client_id, l.client_id) as client_id, c.lead_id, c.canal, c.direction, c.statut,
       c.employe_id, trim(e.prenom || ' ' || e.nom) as employe_nom, c.coordonnee_client, c.debut, c.duree_s,
       c.sujet, c.contenu, (c.enregistrement_ref is not null and c.enregistrement_efface_le is null) as a_enregistrement,
       c.enregistrement_duree_s, c.enregistrement_efface_le, c.transcription, c.resume, c.source, c.automatique
  from public.communications c
  left join public.leads l on l.id = c.lead_id
  left join public.employes e on e.id = c.employe_id
 where app.est_interne();

-- ---------------------------------------------------------------------------
-- 4. Subvention LogisVert (étapes) et avis Google
-- ---------------------------------------------------------------------------
alter table public.projets add column subvention_statut text check (subvention_statut in ('a_deposer','deposee','acceptee','versee','refusee')),
  add column subvention_maj_le timestamptz;
alter table public.succursales add column lien_avis_google text check (lien_avis_google is null or lien_avis_google ~ '^https://');
create table public.avis_demandes (
  id         uuid primary key default gen_random_uuid(),
  client_id  uuid not null references public.clients(id),
  projet_id  uuid references public.projets(id),
  succursale_code text not null references public.succursales(code),
  envoye_le  timestamptz not null default now()
);
create index avis_demandes_client on public.avis_demandes (client_id, envoye_le desc);
alter table public.avis_demandes enable row level security;
create policy lecture on public.avis_demandes for select to authenticated using (app.est_interne());

-- ---------------------------------------------------------------------------
-- 5. Règles, exécutions, journal
-- ---------------------------------------------------------------------------
-- Étapes (jsonb, dans l'ordre) :
--   { "type": "attendre", "minutes": 15, "ouvrables": true } | { "type": "attendre", "jours": 1 }  (envoi pendant les heures d'ouverture)
--   { "type": "attendre_avant_visite", "heures": 24 }
--   { "type": "si", "condition": "lead_non_contacte" | "aucun_appel_sortant" | "aucun_avis_12_mois" | "lead_ouvert" }
--   { "type": "sms", "texte": "..." } | { "type": "courriel", "sujet": "...", "texte": "..." }
--   { "type": "tache", "a": "vendeur|directeur|planification", "titre": "...", "echeance_minutes": 60 }
--   { "type": "notifier", "a": "vendeur|directeur|planification", "titre": "...", "texte": "..." }
--   { "type": "noter_avis" }
-- Variables des textes : {prenom} {succursale} {vendeur} {type} {date_visite} {heure_visite} {lien_avis} {code_projet}
--   {subvention} {telephone}
create table public.regles (
  id          uuid primary key default gen_random_uuid(),
  code        text not null unique,
  nom         text not null,
  description text,
  declencheur text not null check (declencheur in ('lead_recu','appel_manque','visite_planifiee','projet_etape','subvention_etape','entretien_annuel')),
  conditions  jsonb not null default '{}',     -- ex. { "statut": "termine" }, { "sources_exclues": ["appel_manque"] }
  etapes      jsonb not null check (jsonb_typeof(etapes) = 'array' and jsonb_array_length(etapes) > 0),
  arret       text[] not null default '{}',    -- motifs qui arrêtent l'exécution : client_repond, lead_contacte, lead_ferme, visite_changee, projet_annule
  commercial  boolean not null default false,  -- LCAP : consentement exigé, mention de désabonnement ajoutée
  actif       boolean not null default true,
  division    text not null default 'Ventilation' references public.divisions(nom),
  modifie_par uuid references public.employes(id),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
call app.preparer_table('public.regles', false);
create trigger trg_audit_regles after insert or update on public.regles for each row execute function app.audit();
alter table public.regles enable row level security;
create policy lecture on public.regles for select to authenticated using (app.est_interne());
create policy gestion on public.regles for update to authenticated using (app.est_admin()) with check (app.est_admin());

-- Validation des étapes (la page d'édition ne peut pas enregistrer une règle cassée)
create or replace function app.regle_valider() returns trigger
language plpgsql as $$
declare e jsonb;
begin
  for e in select * from jsonb_array_elements(new.etapes) loop
    if e->>'type' not in ('attendre','attendre_avant_visite','si','sms','courriel','tache','notifier','noter_avis') then
      raise exception 'Étape inconnue : %', e->>'type' using errcode = 'P0001'; end if;
    if e->>'type' in ('sms','courriel') and length(trim(coalesce(e->>'texte', ''))) = 0 then raise exception 'Texte du message requis' using errcode = 'P0001'; end if;
    if e->>'type' = 'sms' and length(e->>'texte') > 320 then raise exception 'Texto trop long (320 caractères au plus)' using errcode = 'P0001'; end if;
    if e->>'type' = 'attendre' and coalesce((e->>'minutes')::numeric, 0) + coalesce((e->>'jours')::numeric, 0) * 1440 <= 0 then
      raise exception 'Délai d''attente requis' using errcode = 'P0001'; end if;
    if e->>'type' = 'si' and e->>'condition' not in ('lead_non_contacte','aucun_appel_sortant','aucun_avis_12_mois','lead_ouvert') then
      raise exception 'Condition inconnue : %', e->>'condition' using errcode = 'P0001'; end if;
    if e->>'type' in ('tache','notifier') and e->>'a' not in ('vendeur','directeur','planification') then
      raise exception 'Destinataire inconnu : %', e->>'a' using errcode = 'P0001'; end if;
  end loop;
  new.modifie_par := coalesce(app.employe_id(), new.modifie_par);
  return new;
end $$;
create trigger trg_regle_valider before insert or update on public.regles for each row execute function app.regle_valider();

create table public.executions (
  id              uuid primary key default gen_random_uuid(),
  regle_id        uuid not null references public.regles(id),
  cle             text not null,                 -- une seule exécution par règle et par clé (ex. un texto par numéro par 24 h)
  lead_id         uuid references public.leads(id),
  projet_id       uuid references public.projets(id),
  client_id       uuid references public.clients(id),
  contexte        jsonb not null default '{}',
  etape           integer not null default 0,
  statut          text not null default 'active' check (statut in ('active','terminee','arretee','echec')),
  prochaine_le    timestamptz not null default now(),
  essais          integer not null default 0,
  derniere_erreur text,
  arret_motif     text,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  unique (regle_id, cle)
);
call app.preparer_table('public.executions', false);
create index executions_dues on public.executions (prochaine_le) where statut = 'active';
create index executions_lead on public.executions (lead_id) where statut = 'active';
create index executions_projet on public.executions (projet_id) where statut = 'active';
create table public.execution_journal (
  id           bigint generated always as identity primary key,
  execution_id uuid not null references public.executions(id),
  etape        integer not null,
  action       text not null,
  resultat     text not null check (resultat in ('ok','attente','saute','arrete','echec')),
  detail       text,
  le           timestamptz not null default now()
);
create index execution_journal_exec on public.execution_journal (execution_id, id);
alter table public.executions enable row level security;
alter table public.execution_journal enable row level security;
create policy lecture on public.executions for select to authenticated using (app.est_admin() or app.est_planification());
create policy lecture on public.execution_journal for select to authenticated using (app.est_admin() or app.est_planification());

-- Démarrer les règles d'un déclencheur (appelé par les triggers de la base)
create or replace function app.declencher(p_declencheur text, p_cle text, p_lead uuid, p_projet uuid, p_client uuid, p_contexte jsonb default '{}')
returns integer language plpgsql security definer set search_path = public as $$
declare r public.regles%rowtype; n int := 0; v_source text;
begin
  if p_lead is not null then select source into v_source from public.leads where id = p_lead; end if;
  for r in select * from public.regles where actif and declencheur = p_declencheur loop
    if r.conditions ? 'statut' and r.conditions->>'statut' is distinct from p_contexte->>'statut' then continue; end if;
    if r.conditions ? 'sources_exclues' and v_source is not null and r.conditions->'sources_exclues' ? v_source then continue; end if;
    insert into public.executions (regle_id, cle, lead_id, projet_id, client_id, contexte)
    values (r.id, p_cle, p_lead, p_projet, p_client, coalesce(p_contexte, '{}'))
    on conflict (regle_id, cle) do nothing;
    if found then n := n + 1; end if;
  end loop;
  return n;
end $$;

-- Arrêter les exécutions actives dont la règle s'arrête sur ce motif
create or replace function app.arreter(p_motif text, p_lead uuid, p_projet uuid default null) returns integer
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  with a as (
    update public.executions x set statut = 'arretee', arret_motif = p_motif
      from public.regles r
     where r.id = x.regle_id and x.statut = 'active' and p_motif = any (r.arret)
       and ((p_lead is not null and x.lead_id = p_lead) or (p_projet is not null and x.projet_id = p_projet))
    returning x.id, x.etape)
  insert into public.execution_journal (execution_id, etape, action, resultat, detail)
  select id, etape, 'arrêt', 'arrete', p_motif from a;
  get diagnostics n = row_count;
  return n;
end $$;

-- Variables d'une exécution
create or replace function app.contexte_execution(x public.executions) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare l public.leads%rowtype; p public.projets%rowtype; c public.clients%rowtype; s public.succursales%rowtype;
  v_vendeur uuid; v_succ text; v_nom text; v_visite timestamptz; jours text[] := array['dimanche','lundi','mardi','mercredi','jeudi','vendredi','samedi'];
  mois text[] := array['janvier','février','mars','avril','mai','juin','juillet','août','septembre','octobre','novembre','décembre']; v_loc timestamp;
begin
  if x.lead_id is not null then select * into l from public.leads where id = x.lead_id; end if;
  if x.projet_id is not null then select * into p from public.projets where id = x.projet_id; end if;
  select * into c from public.clients where id = coalesce(x.client_id, p.client_id, l.client_id);
  v_succ := coalesce(p.succursale_code, l.succursale_code, c.succursale_code);
  select * into s from public.succursales where code = v_succ;
  v_vendeur := coalesce(l.assigne_a, p.vendeur_id, c.vendeur_id);
  v_nom := coalesce(nullif(trim(c.prenom), ''), split_part(coalesce(nullif(trim(l.contact_nom), ''), c.nom, ''), ' ', 1));
  v_visite := coalesce((x.contexte->>'visite_le')::timestamptz, l.visite_prevue_le);
  v_loc := v_visite at time zone 'America/Toronto';
  return jsonb_build_object(
    'prenom', coalesce(nullif(v_nom, ''), 'bonjour'),
    'telephone', app.e164(coalesce(c.telephone, l.contact_tel)),
    'courriel', coalesce(c.courriel, l.contact_courriel),
    'succursale', coalesce(s.nom, 'Belleflamme'), 'succursale_code', v_succ, 'lien_avis', coalesce(s.lien_avis_google, ''),
    'vendeur', (select prenom from public.employes where id = v_vendeur), 'vendeur_id', v_vendeur,
    'type', case coalesce(p.type_systeme, l.type_demande) when 'mural_simple' then 'thermopompe murale' when 'mural_multi' then 'thermopompe multizone'
                 when 'central' then 'système central' when 'bienergie' then 'système biénergie' else 'climatisation et chauffage' end,
    'date_visite', case when v_visite is null then null else jours[extract(dow from v_loc)::int + 1] || ' ' || extract(day from v_loc)::int || ' ' || mois[extract(month from v_loc)::int] end,
    'heure_visite', case when v_visite is null then null else to_char(v_loc, 'FMHH24 "h" MI') end,
    'visite_le', v_visite, 'code_projet', p.code_projet, 'client_id', c.id,
    'subvention', case x.contexte->>'etape' when 'deposee' then 'votre demande LogisVert est déposée auprès d''Hydro-Québec'
      when 'acceptee' then 'votre demande LogisVert est acceptée' when 'versee' then 'Hydro-Québec a versé votre subvention LogisVert'
      when 'refusee' then 'votre demande LogisVert a été refusée, on vous appelle pour la suite' else 'votre dossier LogisVert avance' end);
end $$;

create or replace function app.rendre(p_texte text, v jsonb) returns text
language plpgsql immutable as $$
declare k text; t text := p_texte;
begin
  for k in select jsonb_object_keys(v) loop t := replace(t, '{' || k || '}', coalesce(v->>k, '')); end loop;
  return trim(regexp_replace(t, '\s+', ' ', 'g'));
end $$;

-- Destinataires internes d'une tâche ou d'un avis
create or replace function app.destinataires(p_a text, v jsonb) returns setof uuid
language sql stable security definer set search_path = public as $$
  select (v->>'vendeur_id')::uuid where p_a = 'vendeur' and v->>'vendeur_id' is not null
  union
  select id from public.employes where p_a = 'directeur' and actif
     and ((role = 'Gérant de succursale' and succursale_code = v->>'succursale_code')
          or (role in ('Admin tout','Direction') and not exists (select 1 from public.employes g where g.actif and g.role = 'Gérant de succursale'
                                                                   and g.succursale_code = v->>'succursale_code')))
  union
  select id from public.employes where p_a = 'planification' and actif and role in ('Admin tout','Direction','Coordonnateur')
$$;

-- Une étape. Rend : 'suivante' (passer à la prochaine), 'attente' (prochaine_le fixée), 'fin' (terminer : condition fausse)
create or replace function app.executer_etape(x public.executions, e jsonb, r public.regles, v jsonb, out resultat text, out detail text, out prochaine timestamptz)
language plpgsql security definer set search_path = public as $$
declare t text; s text; dest text; reel boolean := app.parametre_bool('envois_reels', false); u uuid; n int := 0; cible timestamptz;
  l public.leads%rowtype;
begin
  resultat := 'suivante';
  if e->>'type' = 'attendre' then
    if e ? 'minutes' and coalesce((e->>'ouvrables')::boolean, false) then
      prochaine := app.plus_minutes_ouvrables(v->>'succursale_code', now(), (e->>'minutes')::int);
    else
      prochaine := app.prochaine_ouverture(v->>'succursale_code',
        now() + make_interval(mins => coalesce((e->>'minutes')::int, 0)) + make_interval(days => coalesce((e->>'jours')::int, 0)));
    end if;
    resultat := 'attente'; detail := 'jusqu''au ' || to_char(prochaine at time zone 'America/Toronto', 'YYYY-MM-DD HH24:MI');
  elsif e->>'type' = 'attendre_avant_visite' then
    if (v->>'visite_le') is null then resultat := 'fin'; detail := 'aucune visite'; return; end if;
    cible := (v->>'visite_le')::timestamptz - make_interval(hours => (e->>'heures')::int);
    if cible <= now() then detail := 'moment passé : étape suivante'; resultat := 'saute';
    else prochaine := cible; resultat := 'attente'; detail := 'jusqu''au ' || to_char(cible at time zone 'America/Toronto', 'YYYY-MM-DD HH24:MI'); end if;
  elsif e->>'type' = 'si' then
    if e->>'condition' = 'lead_non_contacte' then
      select * into l from public.leads where id = x.lead_id;
      if l.premier_contact_le is not null or l.statut in ('converti','perdu') then resultat := 'fin'; detail := 'lead déjà contacté'; end if;
    elsif e->>'condition' = 'lead_ouvert' then
      select * into l from public.leads where id = x.lead_id;
      if l.statut in ('converti','perdu') then resultat := 'fin'; detail := 'lead fermé'; end if;
    elsif e->>'condition' = 'aucun_appel_sortant' then
      if exists (select 1 from public.communications where canal = 'appel' and direction = 'sortant' and debut >= x.created_at
                   and (lead_id = x.lead_id or app.e164(coordonnee_client) = v->>'telephone')) then
        resultat := 'fin'; detail := 'client déjà rappelé'; end if;
    elsif e->>'condition' = 'aucun_avis_12_mois' then
      if exists (select 1 from public.avis_demandes where client_id = (v->>'client_id')::uuid and envoye_le > now() - interval '12 months') then
        resultat := 'fin'; detail := 'avis déjà demandé dans les 12 derniers mois'; end if;
    end if;
  elsif e->>'type' in ('sms','courriel') then
    dest := case when e->>'type' = 'sms' then v->>'telephone' else v->>'courriel' end;
    if dest is null then resultat := 'saute'; detail := 'aucune coordonnée pour ' || (e->>'type'); return; end if;
    if position('{lien_avis}' in e->>'texte') > 0 and coalesce(v->>'lien_avis', '') = '' then
      resultat := 'saute'; detail := 'lien d''avis Google manquant pour la succursale ' || coalesce(v->>'succursale', ''); return; end if;
    if r.commercial and not app.peut_envoyer_commercial(v->>'telephone', v->>'courriel', case when e->>'type' = 'sms' then 'sms' else 'courriel' end) then
      resultat := 'saute'; detail := 'consentement absent ou retiré (LCAP)'; return; end if;
    t := app.rendre(e->>'texte', v);
    if r.commercial then
      t := t || case when e->>'type' = 'sms' then ' Belleflamme ' || (v->>'succursale') || '. STOP pour vous désabonner.'
                     else E'\n\n--\nGroupe Belleflamme, ' || (v->>'succursale') || '. Pour ne plus recevoir nos courriels, répondez « désabonner ».' end;
    end if;
    s := case when e->>'type' = 'courriel' then app.rendre(coalesce(e->>'sujet', 'Belleflamme'), v) end;
    insert into public.communications (client_id, lead_id, canal, direction, statut, coordonnee_client, debut, sujet, contenu, automatique, execution_id)
    values ((v->>'client_id')::uuid, x.lead_id, case when e->>'type' = 'sms' then 'texto' else 'courriel' end, 'sortant',
            case when reel then 'en_file' else 'simule' end, dest, now(), s, t, true, x.id);
    detail := case when reel then 'en file : ' else 'simulé : ' end || left(t, 120);
  elsif e->>'type' in ('tache','notifier') then
    for u in select * from app.destinataires(e->>'a', v) loop
      n := n + 1;
      if e->>'type' = 'tache' then
        insert into public.taches (titre, details, lead_id, projet_id, assigne_employe_id, echeance, execution_id)
        values (app.rendre(e->>'titre', v), app.rendre(coalesce(e->>'texte', ''), v), x.lead_id, x.projet_id, u,
                now() + make_interval(mins => coalesce((e->>'echeance_minutes')::int, 60)), x.id);
      else
        insert into public.notifications (destinataire_employe_id, type, titre, message, lien)
        values (u, 'regle', app.rendre(e->>'titre', v), app.rendre(coalesce(e->>'texte', ''), v),
                case when x.lead_id is not null then '/lead?id=' || x.lead_id else '/macro' end);
      end if;
    end loop;
    if n = 0 then resultat := 'saute'; detail := 'aucun destinataire (' || (e->>'a') || ')'; else detail := n || ' destinataire(s)'; end if;
  elsif e->>'type' = 'noter_avis' then
    if v->>'client_id' is null then resultat := 'saute'; detail := 'aucun client'; return; end if;
    insert into public.avis_demandes (client_id, projet_id, succursale_code) values ((v->>'client_id')::uuid, x.projet_id, v->>'succursale_code');
    detail := 'demande d''avis notée';
  end if;
end $$;

-- Le moteur : exécute les étapes dues (appelé chaque minute par regles-cron, clé serveur seulement)
create or replace function public.hvac_regles_executer(p_limite integer default 200) returns jsonb
language plpgsql security definer set search_path = public as $$
declare x public.executions%rowtype; r public.regles%rowtype; e jsonb; v jsonb; res record; n_exec int := 0; n_echec int := 0; garde int;
begin
  perform app.planifier_entretiens();
  for x in select * from public.executions where statut = 'active' and prochaine_le <= now() order by prochaine_le limit p_limite for update skip locked loop
    n_exec := n_exec + 1;
    begin
      select * into r from public.regles where id = x.regle_id;
      if not r.actif then
        update public.executions set statut = 'arretee', arret_motif = 'règle désactivée' where id = x.id; continue;
      end if;
      v := app.contexte_execution(x);
      garde := 0;
      loop
        garde := garde + 1; exit when garde > 20;
        if x.etape >= jsonb_array_length(r.etapes) then
          update public.executions set statut = 'terminee', etape = x.etape where id = x.id; exit;
        end if;
        e := r.etapes->x.etape;
        select * into res from app.executer_etape(x, e, r, v);
        insert into public.execution_journal (execution_id, etape, action, resultat, detail)
        values (x.id, x.etape, e->>'type', case res.resultat when 'suivante' then 'ok' when 'fin' then 'arrete' else res.resultat end, res.detail);
        if res.resultat = 'fin' then
          update public.executions set statut = 'terminee', etape = x.etape, arret_motif = res.detail where id = x.id; exit;
        end if;
        x.etape := x.etape + 1;
        if res.resultat = 'attente' then
          update public.executions set etape = x.etape, prochaine_le = res.prochaine where id = x.id; exit;
        end if;
      end loop;
    exception when others then
      n_echec := n_echec + 1;
      update public.executions set statut = 'echec', essais = essais + 1, derniere_erreur = sqlerrm where id = x.id;
      insert into public.execution_journal (execution_id, etape, action, resultat, detail) values (x.id, x.etape, 'erreur', 'echec', sqlerrm);
      insert into public.notifications (destinataire_employe_id, type, titre, message, lien)
      select id, 'regle_echec', 'Automatisation en échec : ' || coalesce(r.nom, '?'), left(sqlerrm, 300), '/automatisations'
        from public.employes where actif and role in ('Admin tout','Direction');
    end;
  end loop;
  return jsonb_build_object('executions', n_exec, 'echecs', n_echec);
end $$;
revoke all on function public.hvac_regles_executer(integer) from public, anon, authenticated;
grant execute on function public.hvac_regles_executer(integer) to service_role;

-- Relancer une exécution en échec (après correction de la règle) : Simon, Mike
create or replace function public.hvac_execution_relancer(p_id uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not app.est_admin() then raise exception 'Réservé à Simon et Mike' using errcode = '42501'; end if;
  update public.executions set statut = 'active', prochaine_le = now(), derniere_erreur = null where id = p_id and statut = 'echec';
  if not found then raise exception 'Exécution introuvable ou pas en échec' using errcode = 'P0001'; end if;
end $$;
revoke all on function public.hvac_execution_relancer(uuid) from public, anon;
grant execute on function public.hvac_execution_relancer(uuid) to authenticated;

-- Entretien annuel : 30 jours avant chaque anniversaire de la fin des travaux (une fois par année et par projet)
create or replace function app.planifier_entretiens() returns integer
language plpgsql security definer set search_path = public as $$
declare p record; n int := 0; v_annee int; v_anniv date;
begin
  for p in select id, client_id, installation_terminee_le from public.projets
            where division = 'Ventilation' and installation_terminee_le is not null and statut in ('termine','facture','ferme') loop
    v_annee := extract(year from now())::int;
    for v_annee in v_annee .. v_annee + 1 loop
      v_anniv := make_date(v_annee, extract(month from p.installation_terminee_le)::int, least(extract(day from p.installation_terminee_le)::int, 28));
      if v_anniv > p.installation_terminee_le::date and current_date between v_anniv - 30 and v_anniv then
        n := n + app.declencher('entretien_annuel', p.id || ':' || v_annee, null, p.id, p.client_id, jsonb_build_object('annee', v_annee));
      end if;
    end loop;
  end loop;
  return n;
end $$;

-- ---------------------------------------------------------------------------
-- 6. Déclencheurs branchés sur les événements de l'app
-- ---------------------------------------------------------------------------
create or replace function app.regles_lead() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform app.declencher('lead_recu', new.id::text, new.id, null, new.client_id, '{}');
  -- Consentement tacite : demande d'information, 6 mois (LCAP)
  if app.e164(new.contact_tel) is not null or new.contact_courriel is not null then
    insert into public.consentements (lead_id, tel_e164, courriel, type, source, obtenu_le, expire_le)
    values (new.id, app.e164(new.contact_tel), nullif(trim(new.contact_courriel), ''), 'tacite_demande', 'demande reçue (' || new.source || ')',
            new.recu_le, new.recu_le + interval '6 months');
  end if;
  return null;
end $$;
create trigger trg_regles_lead after insert on public.leads for each row execute function app.regles_lead();

create or replace function app.regles_activite() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.type in ('appel','courriel','texto') then perform app.arreter('lead_contacte', new.lead_id); end if;
  if new.type in ('perdu','vendu') then perform app.arreter('lead_ferme', new.lead_id); end if;
  if new.type in ('visite_planifiee','visite_annulee') then
    perform app.arreter('visite_changee', new.lead_id);
    perform app.arreter('visite_planifiee', new.lead_id);
  end if;
  if new.type = 'visite_planifiee' and new.visite_le is not null then
    perform app.declencher('visite_planifiee', new.lead_id || ':' || new.visite_le, new.lead_id, null, null, jsonb_build_object('visite_le', new.visite_le));
  end if;
  return null;
end $$;
create trigger trg_regles_activite after insert on public.lead_activites for each row execute function app.regles_activite();

create or replace function app.regles_communication() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_tel text := app.e164(new.coordonnee_client);
begin
  -- Un appel manqué n'est pas une réponse du client (sinon la séquence d'un lead « appel manqué » s'arrêterait aussitôt)
  if new.direction = 'entrant' and new.statut <> 'manque' then
    perform app.arreter('client_repond', new.lead_id);
    if new.client_id is not null then
      perform app.arreter('client_repond', l.id) from public.leads l where l.client_id = new.client_id;
    end if;
    -- « STOP » par texto : désabonnement (LCAP), au plus tard 10 jours ouvrables ; ici, immédiat
    if new.canal = 'texto' and v_tel is not null and lower(trim(coalesce(new.contenu, ''))) ~ '^(stop|arr[eê]t|arreter|arrêter|d[ée]sabonner|unsubscribe)\.?$' then
      insert into public.desabonnements (tel_e164, canal, source) values (v_tel, 'sms', 'texto « ' || trim(new.contenu) || ' »');
    end if;
  end if;
  return null;
end $$;
create trigger trg_regles_communication after insert on public.communications for each row execute function app.regles_communication();

create or replace function app.regles_projet() returns trigger
language plpgsql security definer set search_path = public as $$
declare c public.clients%rowtype;
begin
  if tg_op = 'INSERT' then
    -- Consentement tacite : achat, 2 ans (LCAP)
    select * into c from public.clients where id = new.client_id;
    if app.e164(c.telephone) is not null or c.courriel is not null then
      insert into public.consentements (client_id, tel_e164, courriel, type, source, obtenu_le, expire_le)
      values (c.id, app.e164(c.telephone), nullif(trim(c.courriel), ''), 'tacite_achat',
              'soumission ' || coalesce('#' || new.devis_numero_mike, new.code_projet, '') || ' signée',
              coalesce(new.signe_le, now()), coalesce(new.signe_le, now()) + interval '2 years');
    end if;
    return null;
  end if;
  if new.statut is distinct from old.statut then
    if new.statut = 'annule' then perform app.arreter('projet_annule', null, new.id); end if;
    perform app.declencher('projet_etape', new.id || ':' || new.statut, null, new.id, new.client_id, jsonb_build_object('statut', new.statut));
  end if;
  if new.subvention_statut is distinct from old.subvention_statut and new.subvention_statut is not null then
    perform app.declencher('subvention_etape', new.id || ':' || new.subvention_statut, null, new.id, new.client_id, jsonb_build_object('etape', new.subvention_statut));
  end if;
  return null;
end $$;
create trigger trg_regles_projet after insert or update on public.projets for each row execute function app.regles_projet();

-- Macro : étape de la subvention (ajoutée à la fin de la vue)
create or replace view public.projets_macro_v with (security_invoker = true) as
select p.id, p.code_projet, p.statut, p.succursale_code, p.client_id, trim(coalesce(c.prenom || ' ', '') || c.nom) as client_nom,
       coalesce(s.ville, l.ville) as ville, p.vendeur_id, trim(e.prenom || ' ' || e.nom) as vendeur_nom, p.lead_id, p.devis_numero_mike,
       p.montant_avant_taxes_cents, p.type_systeme, p.signe_le, p.installation_prevue_le, p.created_at, p.updated_at,
       p.sous_traitant_id, f.nom as sous_traitant_nom,
       (select sum(round(pl.quantite * pl.cout_cents))::bigint from public.projet_lignes pl
         where pl.projet_id = p.id and pl.type_ligne = 'installation') as cout_installation_cents,
       (select count(*)::int from public.projet_extras x where x.projet_id = p.id and x.statut = 'soumis') as extras_a_approuver,
       (select sum(round(x.quantite * x.cout_cents))::bigint from public.projet_extras x where x.projet_id = p.id and x.statut = 'approuve') as extras_approuves_cents,
       p.facture_st_soumise_le, p.facture_st_total_cents,
       p.numero_ahri, case when p.sous_traitant_id is null then null else cardinality(app.dossier_job(p.id)) end as dossier_manques,
       p.depot_recu_le, p.depot_montant_cents, p.subvention_statut, p.subvention_maj_le
  from public.projets p
  join public.clients c on c.id = p.client_id
  left join public.sites s on s.id = p.site_id
  left join public.leads l on l.id = p.lead_id
  left join public.employes e on e.id = p.vendeur_id
  left join public.fournisseurs f on f.id = p.sous_traitant_id
 where p.division = 'Ventilation';

-- Étape de la subvention LogisVert (Simon, Mike, planification)
create or replace function public.hvac_subvention_etape(p_projet uuid, p_statut text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not (app.est_admin() or app.est_planification()) then raise exception 'Réservé à Belleflamme' using errcode = '42501'; end if;
  if p_statut not in ('a_deposer','deposee','acceptee','versee','refusee') then raise exception 'Étape inconnue' using errcode = 'P0001'; end if;
  update public.projets set subvention_statut = p_statut, subvention_maj_le = now() where id = p_projet;
  if not found then raise exception 'Projet introuvable' using errcode = 'P0002'; end if;
end $$;
revoke all on function public.hvac_subvention_etape(uuid, text) from public, anon;
grant execute on function public.hvac_subvention_etape(uuid, text) to authenticated;

-- Appel manqué (webhook de la téléphonie de Mike, clé serveur) : lead existant ou nouveau (source appel_manque), puis règle
alter table public.leads drop constraint leads_source_check;
alter table public.leads add constraint leads_source_check
  check (source in ('google','facebook','instagram','site_web','telephone','magasin','reference','salon','autre','appel_manque'));
create or replace function public.hvac_appel_manque(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_tel text := app.e164(p->>'telephone'); v_succ text := p->>'succursale_code'; v_lead uuid; v_le timestamptz := coalesce(nullif(p->>'appele_le', '')::timestamptz, now());
begin
  if v_tel is null then raise exception 'Numéro de l''appelant requis' using errcode = 'P0001'; end if;
  if not exists (select 1 from public.succursales where code = v_succ) then raise exception 'Succursale inconnue' using errcode = 'P0001'; end if;
  select id into v_lead from public.leads where app.e164(contact_tel) = v_tel and statut not in ('converti','perdu') order by recu_le desc limit 1;
  if v_lead is null then
    insert into public.leads (succursale_code, source, contact_nom, contact_tel, recu_le)
    values (v_succ, 'appel_manque', 'Appel manqué ' || v_tel, v_tel, v_le) returning id into v_lead;
  end if;
  insert into public.communications (lead_id, canal, direction, statut, coordonnee_client, debut, externe_id)
  values (v_lead, 'appel', 'entrant', 'manque', v_tel, v_le, nullif(p->>'appel_ref', ''))
  on conflict (externe_id) do nothing;
  perform app.declencher('appel_manque', v_tel || ':' || to_char(v_le at time zone 'America/Toronto', 'YYYY-MM-DD'), v_lead, null, null,
                         jsonb_build_object('telephone', v_tel));
  return jsonb_build_object('lead_id', v_lead);
end $$;
revoke all on function public.hvac_appel_manque(jsonb) from public, anon, authenticated;
grant execute on function public.hvac_appel_manque(jsonb) to service_role;

-- Gestes de la page Automatisations et de la cloche
create or replace function public.hvac_tache_faite(p_id uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  update public.taches set faite_le = now(), faite_par = app.employe_id()
   where id = p_id and faite_le is null and (assigne_employe_id = app.employe_id() or app.est_admin() or app.est_planification());
  if not found then raise exception 'Tâche introuvable ou déjà faite' using errcode = 'P0001'; end if;
end $$;
create or replace function public.hvac_lien_avis(p_succ text, p_lien text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not app.est_admin() then raise exception 'Réservé à Simon et Mike' using errcode = '42501'; end if;
  if nullif(trim(p_lien), '') is not null and p_lien !~ '^https://' then raise exception 'Lien : doit commencer par https://' using errcode = 'P0001'; end if;
  update public.succursales set lien_avis_google = nullif(trim(p_lien), '') where code = p_succ;
  if not found then raise exception 'Succursale inconnue' using errcode = 'P0001'; end if;
end $$;
-- p_heures : [{ jour: 0..6, ouvre: "08:30", ferme: "17:00" }] ; un jour absent = fermé
create or replace function public.hvac_heures(p_succ text, p_heures jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare h jsonb;
begin
  if not app.est_admin() then raise exception 'Réservé à Simon et Mike' using errcode = '42501'; end if;
  if not exists (select 1 from public.succursales where code = p_succ) then raise exception 'Succursale inconnue' using errcode = 'P0001'; end if;
  delete from public.heures_succursales where succursale_code = p_succ;
  for h in select * from jsonb_array_elements(coalesce(p_heures, '[]')) loop
    if (h->>'ferme')::time <= (h->>'ouvre')::time then raise exception 'Fermeture avant l''ouverture' using errcode = 'P0001'; end if;
    insert into public.heures_succursales (succursale_code, jour, ouvre, ferme) values (p_succ, (h->>'jour')::smallint, (h->>'ouvre')::time, (h->>'ferme')::time);
  end loop;
end $$;
revoke all on function public.hvac_tache_faite(uuid), public.hvac_lien_avis(text, text), public.hvac_heures(text, jsonb) from public, anon;
grant execute on function public.hvac_tache_faite(uuid), public.hvac_lien_avis(text, text), public.hvac_heures(text, jsonb) to authenticated;

-- Suivi des règles (page Automatisations)
create or replace view public.regles_suivi_v with (security_invoker = true) as
select r.id, r.code, r.nom, r.description, r.declencheur, r.actif, r.commercial, r.etapes, r.arret, r.updated_at,
       count(x.*) filter (where x.statut = 'active')                                    as en_cours,
       count(x.*) filter (where x.statut = 'terminee' and x.updated_at > now() - interval '30 days') as terminees_30j,
       count(x.*) filter (where x.statut = 'arretee' and x.updated_at > now() - interval '30 days')  as arretees_30j,
       count(x.*) filter (where x.statut = 'echec')                                     as echecs,
       max(x.updated_at)                                                                 as derniere_activite
  from public.regles r left join public.executions x on x.regle_id = r.id
 group by r.id;
grant select on public.regles_suivi_v to authenticated;
revoke all on public.regles_suivi_v from anon;

-- ---------------------------------------------------------------------------
-- 7. Règles de départ (textes modifiables dans la page Automatisations)
-- ---------------------------------------------------------------------------
-- Lien de la fiche Google « Le Groupe Belleflamme Rive-Nord » (fourni par Simon le 28 oct. 2026), associé à Rosemère.
-- Lien de PARTAGE de la fiche : à remplacer par le lien direct « écrire un avis » (Google Business Profile, « Demander des avis »).
update public.succursales set lien_avis_google = 'https://share.google/Uxc4mQUVVAVHzIjUS' where code = 'RO';
-- Fiche « Le Groupe BelleFlamme Laurentides » (fournie par Simon le 28 oct. 2026) : Saint-Sauveur. Lien de partage, même remarque.
update public.succursales set lien_avis_google = 'https://share.google/gGKH35om5NjXuPDzG' where code = 'ST';
-- Fiche « Le Groupe Belleflamme Outaouais » (fournie par Simon le 28 oct. 2026) : Gatineau. Lien de partage, même remarque.
update public.succursales set lien_avis_google = 'https://share.google/fsydVHASs2yHY1rvr' where code = 'GA';
-- Fiche « Le Groupe Belleflamme Centre-du-Québec » (fournie par Simon le 28 oct. 2026) : Drummondville. Lien de partage, même remarque.
update public.succursales set lien_avis_google = 'https://share.google/e5Zs4fPXfuCQDxcsn' where code = 'DR';

insert into public.parametres (cle, valeur, description) values
  ('envois_reels', 'false', 'false : textos et courriels automatiques simulés (historique du client). true à la greffe : envoyés par l''app de Mike (ADR-090).')
on conflict (cle) do nothing;

insert into public.regles (code, nom, description, declencheur, conditions, etapes, arret, commercial) values
('lead_eclair', 'Réponse éclair au lead', 'Texto et courriel au client dès que sa demande arrive.', 'lead_recu',
 '{"sources_exclues":["appel_manque"]}',
 '[{"type":"sms","texte":"Bonjour {prenom}, ici Belleflamme {succursale}. Votre demande de {type} est bien reçue. {vendeur} vous appelle très vite. Vous pouvez aussi répondre ici."},
   {"type":"courriel","sujet":"Votre demande à Belleflamme {succursale}","texte":"Bonjour {prenom},\n\nMerci pour votre demande de {type}. {vendeur}, de notre succursale {succursale}, vous contactera très bientôt pour planifier une visite d''évaluation gratuite.\n\nÀ bientôt,\nL''équipe Belleflamme"}]',
 '{lead_ferme}', false),
('lead_escalade', 'Escalade : lead sans contact', 'Après 15 minutes ouvrables sans contact du vendeur, le directeur est avisé et reçoit une tâche.', 'lead_recu',
 '{}',
 '[{"type":"attendre","minutes":15,"ouvrables":true},{"type":"si","condition":"lead_non_contacte"},
   {"type":"notifier","a":"directeur","titre":"Lead sans contact depuis 15 min","texte":"{prenom} ({type}) attend toujours un contact de {vendeur}."},
   {"type":"tache","a":"directeur","titre":"Appeler {prenom} : lead sans contact","texte":"Le vendeur {vendeur} n''a pas encore contacté ce client.","echeance_minutes":30}]',
 '{lead_contacte,lead_ferme}', false),
('lead_sequence', 'Séquence si le client ne répond pas', 'J+1 texto, J+3 courriel, J+7 tâche d''appel au vendeur. S''arrête dès que le client répond, que la visite est planifiée ou que le lead est fermé.', 'lead_recu',
 '{}',
 '[{"type":"attendre","jours":1},{"type":"si","condition":"lead_ouvert"},
   {"type":"sms","texte":"Bonjour {prenom}, c''est {vendeur} de Belleflamme {succursale}. Avez-vous un moment pour planifier votre visite d''évaluation gratuite? Répondez ici avec vos disponibilités."},
   {"type":"attendre","jours":2},{"type":"si","condition":"lead_ouvert"},
   {"type":"courriel","sujet":"Votre projet de {type}","texte":"Bonjour {prenom},\n\nJe n''ai pas réussi à vous joindre. Si votre projet de {type} tient toujours, répondez à ce courriel ou appelez-nous : nous planifierons une visite d''évaluation gratuite, à votre convenance.\n\n{vendeur}, Belleflamme {succursale}"},
   {"type":"attendre","jours":4},{"type":"si","condition":"lead_ouvert"},
   {"type":"tache","a":"vendeur","titre":"Rappeler {prenom} (7 jours sans réponse)","texte":"Dernière relance prévue par la séquence.","echeance_minutes":240}]',
 '{client_repond,lead_ferme,visite_planifiee}', false),
('appel_manque', 'Texto après appel manqué', 'Une minute après un appel manqué, si personne n''a rappelé : texto au client et avis au vendeur de garde. Une fois par numéro par jour.', 'appel_manque',
 '{}',
 '[{"type":"attendre","minutes":1},{"type":"si","condition":"aucun_appel_sortant"},
   {"type":"sms","texte":"Belleflamme {succursale}, désolés pour l''appel manqué. On vous rappelle ou répondez ici."},
   {"type":"notifier","a":"vendeur","titre":"Appel manqué : {telephone}","texte":"Un texto automatique est parti. Rappelle le client."}]',
 '{client_repond}', false),
('rappel_visite', 'Rappels de visite', 'Texto 24 h et 2 h avant la visite d''évaluation (date reçue de Pointage).', 'visite_planifiee',
 '{}',
 '[{"type":"attendre_avant_visite","heures":24},{"type":"sms","texte":"Rappel : {vendeur} de Belleflamme {succursale} vous visite {date_visite} à {heure_visite}. Un empêchement? Répondez ici."},
   {"type":"attendre_avant_visite","heures":2},{"type":"sms","texte":"Belleflamme : {vendeur} sera chez vous à {heure_visite}, dans environ 2 heures. À tantôt!"}]',
 '{visite_changee,lead_ferme}', false),
('avis_google', 'Demande d''avis Google', '2 jours après la fin des travaux : texto et courriel avec le lien d''avis de la succursale. Même lien pour tous les clients, sans filtre (règle de Google). Une fois par client par 12 mois.', 'projet_etape',
 '{"statut":"termine"}',
 '[{"type":"attendre","jours":2},{"type":"si","condition":"aucun_avis_12_mois"},
   {"type":"sms","texte":"Merci {prenom} d''avoir choisi Belleflamme {succursale}! Votre avis nous aide beaucoup : {lien_avis}"},
   {"type":"courriel","sujet":"Comment s''est passée votre installation?","texte":"Bonjour {prenom},\n\nMerci d''avoir fait confiance à Belleflamme {succursale} pour votre {type}. Prendriez-vous une minute pour nous laisser un avis? {lien_avis}\n\nL''équipe Belleflamme"},
   {"type":"noter_avis"}]',
 '{projet_annule}', true),
('subvention_suivi', 'Suivi de subvention LogisVert', 'À chaque étape de la subvention (déposée, acceptée, versée, refusée), un texto au client.', 'subvention_etape',
 '{}',
 '[{"type":"sms","texte":"Belleflamme {succursale} : bonne nouvelle {prenom}, {subvention}. Des questions? Répondez ici."}]',
 '{projet_annule}', false),
('entretien_annuel', 'Entretien annuel de la thermopompe', '30 jours avant l''anniversaire de l''installation : texto pour choisir une plage d''entretien, et tâche à la planification.', 'entretien_annuel',
 '{}',
 '[{"type":"sms","texte":"Bonjour {prenom}, votre thermopompe Belleflamme aura bientôt un an. C''est le temps de l''entretien annuel pour garder la garantie et l''efficacité. Répondez ici pour choisir votre plage."},
   {"type":"tache","a":"planification","titre":"Entretien annuel : {prenom} ({code_projet})","texte":"Le client a reçu l''offre d''entretien.","echeance_minutes":2880}]',
 '{}', true);
