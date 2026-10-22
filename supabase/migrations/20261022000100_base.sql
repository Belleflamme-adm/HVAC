-- Phase 1 | Base : référentiels, employés, helpers d'accès, audit.
-- Conventions :
--   * montants en cents (bigint), jamais de float
--   * pourcentages de rabais en points de base (bp) : 1 % = 100 bp
--   * taux de taxe en pcm (pour cent mille) : TPS 5 % = 5000, TVQ 9,975 % = 9975
--   * aucune suppression physique des données métier : on passe par un statut
--   * colonnes de migration (monday_board_id, monday_item_id, source, synced_at)
--     sur chaque table qui a un équivalent dans l'app de Mike (voir docs/MAPPING.md)

create extension if not exists pgcrypto;

create schema if not exists app;

-- ---------------------------------------------------------------------------
-- Helpers génériques
-- ---------------------------------------------------------------------------

create or replace function app.maj_updated_at() returns trigger
language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end $$;

-- Ajoute les colonnes de migration Monday/Friday et le trigger updated_at.
create or replace procedure app.preparer_table(p_table regclass, p_migration boolean default true)
language plpgsql as $$
begin
  if p_migration then
    execute format($f$
      alter table %s
        add column if not exists monday_board_id bigint,
        add column if not exists monday_item_id  bigint,
        add column if not exists source text not null default 'hvac'
          check (source in ('hvac','monday','friday')),
        add column if not exists synced_at timestamptz
    $f$, p_table);
    execute format('create unique index if not exists %s on %s (monday_item_id) where monday_item_id is not null',
      replace(p_table::text, '.', '_') || '_monday_item_uk', p_table);
  end if;
  execute format('drop trigger if exists trg_updated_at on %s', p_table);
  execute format('create trigger trg_updated_at before update on %s for each row execute function app.maj_updated_at()', p_table);
end $$;

-- ---------------------------------------------------------------------------
-- Référentiels
-- ---------------------------------------------------------------------------

-- Succursales. Saint-Jérôme (succursale + entrepôt central) = HO (ADR-003).
create table public.succursales (
  code        text primary key check (code ~ '^[A-Z]{2}$'),
  nom         text not null,
  ville       text,
  est_entrepot boolean not null default false,
  actif       boolean not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
call app.preparer_table('public.succursales');

-- Divisions, mêmes libellés que le champ `division` chez Mike.
create table public.divisions (
  nom             text primary key,           -- 'Ventilation', 'Climatisation', 'Foyer'...
  lettre          char(1) not null,           -- lettre du code projet : V, F, B
  code_generique  text not null,              -- VTC, FYR, FYG, BBQ, PLB, ASV, ADM
  est_hvac        boolean not null default false,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
call app.preparer_table('public.divisions');

-- Paramètres applicatifs (clé/valeur). Ex. blocage des certifications expirées.
create table public.parametres (
  cle         text primary key,
  valeur      jsonb not null,
  description text,
  updated_at  timestamptz not null default now(),
  created_at  timestamptz not null default now()
);
call app.preparer_table('public.parametres', false);

create or replace function app.parametre_bool(p_cle text, p_defaut boolean default false)
returns boolean language sql stable as $$
  select coalesce((select (valeur #>> '{}')::boolean from public.parametres where cle = p_cle), p_defaut)
$$;

-- Taux de taxes datés : on ne modifie jamais un taux, on ajoute une ligne.
create table public.taux_taxes (
  code          text not null check (code in ('TPS','TVQ')),
  taux_pcm      integer not null check (taux_pcm between 0 and 100000),
  en_vigueur_du date not null,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  primary key (code, en_vigueur_du)
);
call app.preparer_table('public.taux_taxes', false);

-- ---------------------------------------------------------------------------
-- Employés et accès
-- ---------------------------------------------------------------------------

-- Rôles : libellés à confirmer avec ceux de Mike (seul « Admin tout » est connu).
create table public.employes (
  id                    uuid primary key default gen_random_uuid(),
  auth_user_id          uuid unique,          -- lien Supabase Auth (auth.users.id)
  email                 text not null unique,
  prenom                text not null,
  nom                   text not null,
  telephone             text,
  role                  text not null check (role in (
                          'Admin tout','Direction','Gérant de succursale','Vendeur',
                          'Coordonnateur','Technicien','Comptabilité')),
  succursale_code       text not null references public.succursales(code),
  peut_approuver_rabais boolean not null default false,  -- Mike et Simon (ADR-010)
  actif                 boolean not null default true,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now()
);
call app.preparer_table('public.employes');

-- Accès à des succursales supplémentaires (ex. vendeur qui couvre RO et ST).
create table public.employe_succursales (
  employe_id      uuid not null references public.employes(id),
  succursale_code text not null references public.succursales(code),
  created_at      timestamptz not null default now(),
  primary key (employe_id, succursale_code)
);

-- Fournisseurs et sous-traitants (ADR-005 : installation par employés ET sous-traitants).
create table public.fournisseurs (
  id          uuid primary key default gen_random_uuid(),
  nom         text not null,
  type        text not null default 'fournisseur' check (type in ('fournisseur','sous-traitant','les deux')),
  courriel    text,
  telephone   text,
  neq         text,
  licence_rbq text,
  actif       boolean not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
call app.preparer_table('public.fournisseurs');

-- Certifications des techniciens et sous-traitants (ADR-015).
create table public.certifications (
  id            uuid primary key default gen_random_uuid(),
  employe_id    uuid references public.employes(id),
  fournisseur_id uuid references public.fournisseurs(id),
  type          text not null check (type in ('halocarbures','rbq','cmmtq','gaz','autre')),
  numero        text,
  emise_le      date,
  expire_le     date,
  document_id   uuid,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  check ((employe_id is null) <> (fournisseur_id is null))
);
call app.preparer_table('public.certifications', false);

-- ---------------------------------------------------------------------------
-- Helpers RLS (security definer pour éviter la récursion des politiques)
-- ---------------------------------------------------------------------------

create or replace function app.employe_id() returns uuid
language sql stable security definer set search_path = public as $$
  select id from public.employes where auth_user_id = auth.uid() and actif
$$;

create or replace function app.role() returns text
language sql stable security definer set search_path = public as $$
  select role from public.employes where auth_user_id = auth.uid() and actif
$$;

create or replace function app.est_admin() returns boolean
language sql stable as $$ select coalesce(app.role() in ('Admin tout','Direction'), false) $$;

-- Voit toutes les succursales : admin, direction, comptabilité.
create or replace function app.voit_tout() returns boolean
language sql stable as $$ select coalesce(app.role() in ('Admin tout','Direction','Comptabilité'), false) $$;

create or replace function app.mes_succursales() returns text[]
language sql stable security definer set search_path = public as $$
  select coalesce(array_agg(distinct s), '{}') from (
    select succursale_code as s from public.employes where auth_user_id = auth.uid() and actif
    union
    select es.succursale_code from public.employe_succursales es
      join public.employes e on e.id = es.employe_id
     where e.auth_user_id = auth.uid() and e.actif
  ) x
$$;

create or replace function app.voit_succursale(p_code text) returns boolean
language sql stable as $$ select app.voit_tout() or p_code = any(app.mes_succursales()) $$;

-- Rôles qui créent et modifient le commercial (leads, clients, devis).
create or replace function app.est_commercial() returns boolean
language sql stable as $$
  select coalesce(app.role() in ('Admin tout','Direction','Gérant de succursale','Vendeur','Coordonnateur'), false)
$$;

create or replace function app.peut_approuver_rabais() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select peut_approuver_rabais from public.employes where auth_user_id = auth.uid() and actif), false)
$$;

-- ---------------------------------------------------------------------------
-- Journal d'audit (Loi 25, rabais, impersonation). Insertion seulement.
-- ---------------------------------------------------------------------------

create table public.journal_audit (
  id          bigint generated always as identity primary key,
  at          timestamptz not null default now(),
  auth_uid    uuid,
  employe_id  uuid,
  action      text not null,       -- insert | update | delete | lecture | impersonation | approbation...
  table_nom   text,
  ligne_id    text,
  avant       jsonb,
  apres       jsonb,
  contexte    jsonb                -- ex. { "impersonne": "<employe_id>", "ip": "..." }
);

create or replace function app.audit() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.journal_audit(auth_uid, employe_id, action, table_nom, ligne_id, avant, apres)
  values (auth.uid(), app.employe_id(), lower(tg_op), tg_table_name,
          coalesce((case when tg_op = 'DELETE' then to_jsonb(old) else to_jsonb(new) end) ->> 'id', ''),
          case when tg_op in ('UPDATE','DELETE') then to_jsonb(old) end,
          case when tg_op in ('INSERT','UPDATE') then to_jsonb(new) end);
  return coalesce(new, old);
end $$;

create or replace function app.interdit() returns trigger
language plpgsql as $$
begin
  raise exception '% interdit sur %', tg_op, tg_table_name using errcode = '42501';
end $$;

create trigger trg_journal_immuable before update or delete on public.journal_audit
  for each row execute function app.interdit();

-- Journal explicite d'une lecture de renseignements personnels ou d'une impersonation,
-- appelé par les fonctions serverless.
create or replace function app.journaliser(p_action text, p_table text, p_ligne text, p_contexte jsonb default null)
returns void language sql security definer set search_path = public as $$
  insert into public.journal_audit(auth_uid, employe_id, action, table_nom, ligne_id, contexte)
  values (auth.uid(), app.employe_id(), p_action, p_table, p_ligne, p_contexte)
$$;

create trigger trg_audit after insert or update or delete on public.employes
  for each row execute function app.audit();
