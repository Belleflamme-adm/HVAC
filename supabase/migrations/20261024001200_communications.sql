-- Communications avec le client : appels, textos, courriels (ADR-067).
-- Ils passent par le système de l'app de Mike (téléphonie, textos, courriels). Une fois la greffe faite,
-- chaque communication arrive ici avec son heure, sa durée, l'enregistrement et la transcription faits par Mike.
-- Accès (choix de Simon) : tous les employés de Belleflamme, sauf les sous-traitants. Chaque écoute est journalisée.
-- Conservation des enregistrements : même règle que l'app de Mike (à confirmer avec lui ; paramètre à remplir).

-- Employé de Belleflamme (pas un sous-traitant), compte actif
create or replace function app.est_interne() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.employes e where e.id = app.employe_id() and e.actif and e.fournisseur_id is null)
$$;

create table public.communications (
  id                     uuid primary key default gen_random_uuid(),
  client_id              uuid references public.clients(id),
  lead_id                uuid references public.leads(id),
  canal                  text not null check (canal in ('appel','texto','courriel')),
  direction              text not null check (direction in ('sortant','entrant')),
  statut                 text not null default 'termine'
                         check (statut in ('termine','manque','messagerie','envoye','recu','echec')),
  employe_id             uuid references public.employes(id),
  coordonnee_client      text,                -- numéro ou courriel du client utilisé
  debut                  timestamptz not null,
  duree_s                integer check (duree_s >= 0),
  sujet                  text,                -- courriel
  contenu                text,                -- texto ou corps du courriel
  enregistrement_ref     text,                -- référence de l'enregistrement chez Mike (jamais une URL publique)
  enregistrement_duree_s integer check (enregistrement_duree_s >= 0),
  enregistrement_efface_le timestamptz,       -- effacé selon la règle de conservation
  transcription          text,
  resume                 text,
  externe_id             text unique,         -- identifiant chez Mike (ex. identifiant d'appel de la téléphonie)
  created_at             timestamptz not null default now(),
  updated_at             timestamptz not null default now(),
  check (client_id is not null or lead_id is not null)
);
call app.preparer_table('public.communications');
create index communications_client on public.communications (client_id, debut desc);
create index communications_lead on public.communications (lead_id, debut desc);
alter table public.communications enable row level security;
create policy lecture on public.communications for select to authenticated using (app.est_interne());
-- Aucune écriture par le navigateur : les communications arrivent de l'app de Mike (webhook, fonction serveur).
revoke all on public.communications from anon;
grant select on public.communications to authenticated;
create trigger trg_audit after insert or update on public.communications for each row execute function app.audit();

-- Historique d'un client : ses communications ET celles de ses leads (l'appel fait au stade du lead suit le client).
-- Vue du propriétaire (pas security_invoker) : le lien lead -> client doit se résoudre même si l'employé ne voit
-- pas ce lead ; le filtre app.est_interne() applique la même règle d'accès que la table.
create or replace view public.communications_v as
select c.id, coalesce(c.client_id, l.client_id) as client_id, c.lead_id, c.canal, c.direction, c.statut,
       c.employe_id, trim(e.prenom || ' ' || e.nom) as employe_nom, c.coordonnee_client, c.debut, c.duree_s,
       c.sujet, c.contenu, (c.enregistrement_ref is not null and c.enregistrement_efface_le is null) as a_enregistrement,
       c.enregistrement_duree_s, c.enregistrement_efface_le, c.transcription, c.resume, c.source
  from public.communications c
  left join public.leads l on l.id = c.lead_id
  left join public.employes e on e.id = c.employe_id
 where app.est_interne();
grant select on public.communications_v to authenticated;
revoke all on public.communications_v from anon;

-- Écoute d'un enregistrement : vérifie l'accès, journalise (qui, quand, quel appel), rend la référence chez Mike.
create or replace function public.hvac_ecouter_enregistrement(p_communication uuid)
returns text language plpgsql security definer set search_path = public as $$
declare v_ref text; v_client uuid; v_lead uuid;
begin
  if not app.est_interne() then raise exception 'Accès refusé' using errcode = '42501'; end if;
  select enregistrement_ref, client_id, lead_id into v_ref, v_client, v_lead from public.communications
   where id = p_communication and canal = 'appel' and enregistrement_efface_le is null;
  if v_ref is null then raise exception 'Enregistrement introuvable ou effacé' using errcode = 'P0002'; end if;
  insert into public.journal_audit (auth_uid, employe_id, action, table_nom, ligne_id, contexte)
  values (auth.uid(), app.employe_id(), 'lecture', 'communications', p_communication::text,
          jsonb_build_object('objet', 'enregistrement', 'client_id', v_client, 'lead_id', v_lead));
  return v_ref;
end $$;
revoke all on function public.hvac_ecouter_enregistrement(uuid) from public, anon;
grant execute on function public.hvac_ecouter_enregistrement(uuid) to authenticated;

-- Conservation : même règle que l'app de Mike. Tant que le paramètre est vide, rien n'est effacé.
insert into public.parametres (cle, valeur, description)
values ('conservation_enregistrements_jours', 'null',
        'Durée de conservation des enregistrements d''appels, en jours. Même règle que l''app de Mike : à confirmer avec lui (ADR-067). Vide = rien n''est effacé.')
on conflict (cle) do nothing;

-- Efface la référence des enregistrements trop vieux (l'heure, la durée et la transcription restent).
-- À lancer par une tâche planifiée une fois la règle confirmée. Retourne le nombre d'enregistrements effacés.
create or replace function app.purger_enregistrements() returns integer
language plpgsql security definer set search_path = public as $$
declare v_jours integer; n integer;
begin
  select nullif(valeur #>> '{}', 'null')::integer into v_jours from public.parametres where cle = 'conservation_enregistrements_jours';
  if v_jours is null then return 0; end if;
  update public.communications set enregistrement_ref = null, enregistrement_efface_le = now()
   where enregistrement_ref is not null and debut < now() - make_interval(days => v_jours);
  get diagnostics n = row_count;
  return n;
end $$;
revoke all on function app.purger_enregistrements() from public;

-- Position du client pour la carte (synchronisée avec la carte de l'app de Mike à la greffe)
alter table public.sites add column latitude numeric(9,6) check (latitude between -90 and 90),
                         add column longitude numeric(9,6) check (longitude between -180 and 180);
