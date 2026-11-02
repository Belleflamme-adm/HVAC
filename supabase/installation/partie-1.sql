-- Installation HVAC Belleflamme | partie 1 sur 6 | à coller dans Supabase > SQL Editor > Run
-- Généré depuis supabase/migrations (commentaires retirés). Les parties s'exécutent DANS L'ORDRE, une seule fois.

-- ===== 20261022000100_base.sql =====
create extension if not exists pgcrypto;
create schema if not exists app;
create or replace function app.maj_updated_at() returns trigger
language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end $$;
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
create table public.divisions (
  nom             text primary key,           -- 'Ventilation', 'Climatisation', 'Foyer'...
  lettre          char(1) not null,           -- lettre du code projet : V, F, B
  code_generique  text not null,              -- VTC, FYR, FYG, BBQ, PLB, ASV, ADM
  est_hvac        boolean not null default false,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
call app.preparer_table('public.divisions');
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
create table public.taux_taxes (
  code          text not null check (code in ('TPS','TVQ')),
  taux_pcm      integer not null check (taux_pcm between 0 and 100000),
  en_vigueur_du date not null,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  primary key (code, en_vigueur_du)
);
call app.preparer_table('public.taux_taxes', false);
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
create table public.employe_succursales (
  employe_id      uuid not null references public.employes(id),
  succursale_code text not null references public.succursales(code),
  created_at      timestamptz not null default now(),
  primary key (employe_id, succursale_code)
);
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
create or replace function app.est_commercial() returns boolean
language sql stable as $$
  select coalesce(app.role() in ('Admin tout','Direction','Gérant de succursale','Vendeur','Coordonnateur'), false)
$$;
create or replace function app.peut_approuver_rabais() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select peut_approuver_rabais from public.employes where auth_user_id = auth.uid() and actif), false)
$$;
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
create or replace function app.journaliser(p_action text, p_table text, p_ligne text, p_contexte jsonb default null)
returns void language sql security definer set search_path = public as $$
  insert into public.journal_audit(auth_uid, employe_id, action, table_nom, ligne_id, contexte)
  values (auth.uid(), app.employe_id(), p_action, p_table, p_ligne, p_contexte)
$$;
create trigger trg_audit after insert or update or delete on public.employes
  for each row execute function app.audit();

-- ===== 20261022000200_numerotation.sql =====
create table public.formats_numerotation (
  cle         text primary key,       -- devis | facture | note_credit | projet | bt | asv | contrat
  modele      text not null,
  prefixe     text not null default '',
  portee      text not null default 'annuelle'
              check (portee in ('globale','annuelle','succursale','succursale_annuelle')),
  description text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
call app.preparer_table('public.formats_numerotation', false);
create table public.compteurs (
  cle        text not null references public.formats_numerotation(cle),
  periode    text not null,          -- '*' | '2026' | 'RO' | 'RO-2026'
  prochain   bigint not null default 1 check (prochain >= 1),
  updated_at timestamptz not null default now(),
  primary key (cle, periode)
);
create or replace function app.compteur_garde() returns trigger
language plpgsql as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'Suppression d''un compteur interdite (Revenu Québec)' using errcode = '42501';
  end if;
  if new.prochain < old.prochain then
    raise exception 'Décrément du compteur % interdit (% -> %)', old.cle, old.prochain, new.prochain
      using errcode = '42501';
  end if;
  return new;
end $$;
create trigger trg_compteur_garde before update or delete on public.compteurs
  for each row execute function app.compteur_garde();
create or replace function app.prochain_numero(
  p_cle text, p_succursale text default null, p_division_lettre text default null,
  p_date date default current_date
) returns text
language plpgsql security definer set search_path = public as $$
declare
  f        public.formats_numerotation%rowtype;
  v_periode text;
  v_n      bigint;
  v_txt    text;
  v_largeur text;
begin
  select * into f from public.formats_numerotation where cle = p_cle;
  if not found then
    raise exception 'Format de numérotation inconnu : %', p_cle;
  end if;
  if f.portee in ('succursale','succursale_annuelle') and p_succursale is null then
    raise exception 'Succursale requise pour numéroter %', p_cle;
  end if;
  v_periode := case f.portee
    when 'globale' then '*'
    when 'annuelle' then to_char(p_date, 'YYYY')
    when 'succursale' then p_succursale
    else p_succursale || '-' || to_char(p_date, 'YYYY')
  end;
  insert into public.compteurs(cle, periode) values (p_cle, v_periode)
    on conflict do nothing;
  update public.compteurs
     set prochain = prochain + 1, updated_at = now()
   where cle = p_cle and periode = v_periode
  returning prochain - 1 into v_n;
  v_txt := f.modele;
  v_txt := replace(v_txt, '{prefixe}', f.prefixe);
  v_txt := replace(v_txt, '{annee}', to_char(p_date, 'YYYY'));
  v_txt := replace(v_txt, '{aa}', to_char(p_date, 'YY'));
  v_txt := replace(v_txt, '{succ}', coalesce(p_succursale, ''));
  v_txt := replace(v_txt, '{div}', coalesce(p_division_lettre, ''));
  v_largeur := substring(v_txt from '\{seq:(\d+)\}');
  if v_largeur is not null then
    v_txt := regexp_replace(v_txt, '\{seq:\d+\}', lpad(v_n::text, v_largeur::int, '0'));
  end if;
  v_txt := replace(v_txt, '{seq}', v_n::text);
  return v_txt;
end $$;
revoke all on function app.prochain_numero(text, text, text, date) from public;

-- ===== 20261022000300_crm.sql =====
create table public.clients (
  id                      uuid primary key default gen_random_uuid(),
  type                    text not null default 'particulier' check (type in ('particulier','entreprise')),
  prenom                  text,
  nom                     text not null,
  entreprise              text,
  courriel                text,
  telephone               text,
  langue                  text not null default 'fr' check (langue in ('fr','en')),
  succursale_code         text not null references public.succursales(code),
  vendeur_id              uuid references public.employes(id),
  est_proprietaire        boolean,
  nom_preuve_propriete    text,
  hq_numero_client        text check (hq_numero_client is null or hq_numero_client ~ '^1\d{8}$'),
  hq_numero_compteur      text check (hq_numero_compteur is null or length(hq_numero_compteur) between 11 and 12),
  consentement_hq_le      timestamptz,
  exemption_taxes         text not null default 'aucune'
                          check (exemption_taxes in ('aucune','autochtone','revendeur','organisme','autre')),
  exemption_tps           boolean not null default false,
  exemption_tvq           boolean not null default false,
  exemption_numero        text,
  exemption_document_id   uuid,
  consentement_comm_le    timestamptz,
  notes                   text,
  actif                   boolean not null default true,
  created_by              uuid references public.employes(id) default app.employe_id(),
  created_at              timestamptz not null default now(),
  updated_at              timestamptz not null default now(),
  check ((hq_numero_client is null and hq_numero_compteur is null) or consentement_hq_le is not null),
  check (exemption_taxes <> 'aucune' or (not exemption_tps and not exemption_tvq))
);
call app.preparer_table('public.clients');
create index on public.clients (succursale_code);
create index on public.clients (lower(nom));
create table public.sites (
  id                 uuid primary key default gen_random_uuid(),
  client_id          uuid not null references public.clients(id),
  libelle            text,
  adresse            text not null,
  ville              text not null,
  province           text not null default 'QC',
  code_postal        text,
  type_habitation    text check (type_habitation in ('maison','condo','multiplex','immeuble','commercial','autre')),
  annee_construction integer,
  a_geothermie       boolean not null default false,   -- LogisVert : centrale + géothermie non admissible
  notes              text,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);
call app.preparer_table('public.sites', false);
create index on public.sites (client_id);
create table public.leads (
  id              uuid primary key default gen_random_uuid(),
  division        text not null default 'Ventilation' references public.divisions(nom),
  succursale_code text not null references public.succursales(code),
  source          text not null default 'autre'
                  check (source in ('site_web','facebook','instagram','telephone','magasin','reference','salon','autre')),
  statut          text not null default 'nouveau'
                  check (statut in ('nouveau','contacte','qualifie','inspection_planifiee','converti','perdu')),
  client_id       uuid references public.clients(id),
  contact_nom     text,
  contact_tel     text,
  contact_courriel text,
  besoin          text,
  assigne_a       uuid references public.employes(id),
  raison_perte    text,
  created_by      uuid references public.employes(id) default app.employe_id(),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
call app.preparer_table('public.leads');
create index on public.leads (succursale_code, statut);
create table public.inspections (
  id              uuid primary key default gen_random_uuid(),
  division        text not null default 'Ventilation' references public.divisions(nom),
  succursale_code text not null references public.succursales(code),
  lead_id         uuid references public.leads(id),
  client_id       uuid not null references public.clients(id),
  site_id         uuid references public.sites(id),
  inspecteur_id   uuid references public.employes(id),
  prevue_le       timestamptz,
  realisee_le     timestamptz,
  statut          text not null default 'planifiee'
                  check (statut in ('planifiee','realisee','annulee')),
  donnees         jsonb not null default '{}'::jsonb,
  recommandations text,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
call app.preparer_table('public.inspections');
create index on public.inspections (client_id);
create table public.documents (
  id              uuid primary key default gen_random_uuid(),
  bucket          text not null default 'hvac-documents',
  chemin          text not null,
  nom_fichier     text not null,
  type_mime       text,
  taille_octets   bigint,
  categorie       text not null default 'autre' check (categorie in (
                    'photo_plaque','preuve_propriete','facture_pdf','devis_pdf','photo_chantier',
                    'signature','exemption','plan','certificat','autre')),
  entite          text not null,       -- 'clients' | 'projets' | 'equipements_installes' ...
  entite_id       uuid not null,
  succursale_code text not null references public.succursales(code),
  contient_rp     boolean not null default false,  -- renseignements personnels (Loi 25)
  created_by      uuid references public.employes(id) default app.employe_id(),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  unique (bucket, chemin)
);
call app.preparer_table('public.documents', false);
create index on public.documents (entite, entite_id);
create trigger trg_audit after insert or update or delete on public.clients
  for each row execute function app.audit();

-- ===== 20261022000400_catalogue.sql =====
create table public.marques (
  id                       uuid primary key default gen_random_uuid(),
  nom                      text not null unique,
  fournisseur_id           uuid references public.fournisseurs(id),
  escompte_fournisseur_bp  integer not null default 0 check (escompte_fournisseur_bp between 0 and 10000),
  plafond_rabais_exception_bp integer check (plafond_rabais_exception_bp between 0 and 10000),
  actif                    boolean not null default true,
  created_at               timestamptz not null default now(),
  updated_at               timestamptz not null default now()
);
call app.preparer_table('public.marques');
create table public.produits (
  id                  uuid primary key default gen_random_uuid(),
  sku                 text not null unique,
  division            text not null default 'Ventilation' references public.divisions(nom),
  marque_id           uuid references public.marques(id),
  fournisseur_id      uuid references public.fournisseurs(id),
  nom                 text not null,
  categorie           text not null default 'autre' check (categorie in (
                        'thermopompe_murale','thermopompe_centrale','unite_exterieure','unite_interieure',
                        'fournaise','echangeur_air','climatiseur','conduit','accessoire','main_oeuvre','autre')),
  modele              text,
  ahri                text,
  energy_star         text check (energy_star is null or energy_star ~ '^\d{7}$'),
  btu_nominal         integer check (btu_nominal > 0),
  btu_moins8          integer check (btu_moins8 > 0),       -- puissance de chauffage à -8 °C
  climat_froid        boolean not null default false,
  logisvert_admissible boolean,
  cout_cents          bigint not null default 0 check (cout_cents >= 0),
  prix_cents          bigint not null default 0 check (prix_cents >= 0),
  escompte_fournisseur_bp integer check (escompte_fournisseur_bp between 0 and 10000),
  taxable             boolean not null default true,
  stocke              boolean not null default true,
  fictif              boolean not null default false,       -- données de démo
  actif               boolean not null default true,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);
call app.preparer_table('public.produits');
create index on public.produits (marque_id);
create index on public.produits (categorie);
create table public.kits (
  id          uuid primary key default gen_random_uuid(),
  code        text not null unique,
  nom         text not null,
  division    text not null default 'Ventilation' references public.divisions(nom),
  description text,
  prix_cents  bigint check (prix_cents >= 0),   -- null = somme des composantes
  fictif      boolean not null default false,
  actif       boolean not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
call app.preparer_table('public.kits');
create table public.kit_items (
  kit_id      uuid not null references public.kits(id),
  produit_id  uuid not null references public.produits(id),
  quantite    numeric(10,2) not null default 1 check (quantite > 0),
  created_at  timestamptz not null default now(),
  primary key (kit_id, produit_id)
);

-- ===== 20261022000500_ventes.sql =====
create or replace function app.taux_pcm(p_code text, p_date date) returns integer
language sql stable as $$
  select taux_pcm from public.taux_taxes
   where code = p_code and en_vigueur_du <= p_date
   order by en_vigueur_du desc limit 1
$$;
create or replace function app.arrondi_taxe(p_montant bigint, p_taux_pcm integer) returns bigint
language sql immutable as $$
  select sign(p_montant)::bigint * ((abs(p_montant) * p_taux_pcm + 50000) / 100000)
$$;
create or replace function app.taxes(
  p_montant bigint, p_date date default current_date,
  p_exempt_tps boolean default false, p_exempt_tvq boolean default false,
  out tps bigint, out tvq bigint
) language sql stable as $$
  select case when p_exempt_tps then 0 else app.arrondi_taxe(p_montant, app.taux_pcm('TPS', p_date)) end,
         case when p_exempt_tvq then 0 else app.arrondi_taxe(p_montant, app.taux_pcm('TVQ', p_date)) end
$$;
create table public.delegations_rabais (
  id          uuid primary key default gen_random_uuid(),
  employe_id  uuid not null references public.employes(id),
  plafond_bp  integer not null check (plafond_bp between 0 and 10000),
  accorde_par uuid not null references public.employes(id),
  debut       timestamptz not null default now(),
  fin         timestamptz,
  revoque_le  timestamptz,
  revoque_par uuid references public.employes(id),
  motif       text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
call app.preparer_table('public.delegations_rabais', false);
create or replace function app.delegation_garde() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    if not exists (select 1 from public.employes where id = new.accorde_par and peut_approuver_rabais and actif) then
      raise exception 'Seuls les approbateurs (Mike, Simon) peuvent accorder un plafond de rabais' using errcode = '42501';
    end if;
  else
    if (new.employe_id, new.plafond_bp, new.accorde_par, new.debut)
       is distinct from (old.employe_id, old.plafond_bp, old.accorde_par, old.debut) then
      raise exception 'Une délégation ne se modifie pas : révoquer et en créer une nouvelle' using errcode = '42501';
    end if;
    if new.revoque_le is not null and not exists (
         select 1 from public.employes where id = new.revoque_par and peut_approuver_rabais and actif) then
      raise exception 'Révocation réservée aux approbateurs' using errcode = '42501';
    end if;
  end if;
  return new;
end $$;
create trigger trg_delegation_garde before insert or update on public.delegations_rabais
  for each row execute function app.delegation_garde();
create trigger trg_delegation_delete before delete on public.delegations_rabais
  for each row execute function app.interdit();
create trigger trg_audit after insert or update on public.delegations_rabais
  for each row execute function app.audit();
create or replace function app.plafond_rabais_bp(p_produit uuid, p_employe uuid, p_a timestamptz default now())
returns integer language sql stable security definer set search_path = public as $$
  with auto as (
    select coalesce(m.plafond_rabais_exception_bp,
                    greatest(coalesce(p.escompte_fournisseur_bp, m.escompte_fournisseur_bp, 0) - 3500, 0)) as bp
      from public.produits p left join public.marques m on m.id = p.marque_id
     where p.id = p_produit
  ), deleg as (
    select max(plafond_bp) as bp from public.delegations_rabais
     where employe_id = p_employe and revoque_le is null
       and debut <= p_a and (fin is null or fin > p_a)
  )
  select greatest(coalesce((select bp from auto), 0), coalesce((select bp from deleg), 0))
$$;
create table public.devis (
  id                uuid primary key default gen_random_uuid(),
  numero            text unique,                       -- attribué par la base
  division          text not null default 'Ventilation' references public.divisions(nom),
  succursale_code   text not null references public.succursales(code),
  client_id         uuid not null references public.clients(id),
  site_id           uuid references public.sites(id),
  lead_id           uuid references public.leads(id),
  inspection_id     uuid references public.inspections(id),
  vendeur_id        uuid not null references public.employes(id),
  statut            text not null default 'brouillon' check (statut in (
                      'brouillon','envoye','accepte','refuse','expire','annule')),
  date_devis        date not null default current_date,
  valide_jusqu      date not null default (current_date + 30),
  mode_paiement     text not null default 'comptant' check (mode_paiement in ('comptant','financeit','mixte')),
  depot_bp          integer not null default 4000 check (depot_bp between 0 and 10000),  -- 40 % (ADR-009)
  sous_total_cents  bigint not null default 0,
  rabais_cents      bigint not null default 0,
  tps_cents         bigint not null default 0,
  tvq_cents         bigint not null default 0,
  total_cents       bigint not null default 0,
  depot_cents       bigint not null default 0,
  subvention_estimee_cents bigint,
  notes_client      text,
  notes_internes    text,
  accepte_le        timestamptz,
  refuse_le         timestamptz,
  raison_refus      text,
  created_by        uuid references public.employes(id) default app.employe_id(),
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);
call app.preparer_table('public.devis');
create index on public.devis (succursale_code, statut);
create index on public.devis (client_id);
create table public.devis_lignes (
  id                  uuid primary key default gen_random_uuid(),
  devis_id            uuid not null references public.devis(id),
  position            integer not null default 1,
  produit_id          uuid references public.produits(id),
  kit_id              uuid references public.kits(id),
  description         text not null,
  quantite            numeric(10,2) not null default 1 check (quantite > 0),
  prix_unitaire_cents bigint not null check (prix_unitaire_cents >= 0),
  rabais_bp           integer not null default 0 check (rabais_bp between 0 and 10000),
  plafond_bp          integer not null default 0,    -- instantané du plafond au moment du calcul
  approbation_requise boolean not null default false,
  taxable             boolean not null default true,
  montant_cents       bigint not null default 0,     -- après rabais, avant taxes
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  check (produit_id is null or kit_id is null)
);
call app.preparer_table('public.devis_lignes', false);
create index on public.devis_lignes (devis_id);
create table public.approbations_rabais (
  id              uuid primary key default gen_random_uuid(),
  devis_id        uuid not null references public.devis(id),
  devis_ligne_id  uuid not null references public.devis_lignes(id),
  rabais_bp       integer not null,
  plafond_bp      integer not null,
  demande_par     uuid not null references public.employes(id) default app.employe_id(),
  motif           text,
  statut          text not null default 'en_attente' check (statut in ('en_attente','approuvee','refusee')),
  decide_par      uuid references public.employes(id),
  decide_le       timestamptz,
  commentaire     text,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
call app.preparer_table('public.approbations_rabais', false);
create index on public.approbations_rabais (devis_id);
create or replace function app.devis_numero() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    new.numero := app.prochain_numero('devis', new.succursale_code, null, new.date_devis);
    new.sous_total_cents := 0; new.rabais_cents := 0; new.tps_cents := 0;
    new.tvq_cents := 0; new.total_cents := 0; new.depot_cents := 0;
    return new;
  end if;
  if new.numero is distinct from old.numero then
    raise exception 'Le numéro de devis ne se modifie pas' using errcode = '42501';
  end if;
  if pg_trigger_depth() = 1 then
    new.sous_total_cents := old.sous_total_cents; new.rabais_cents := old.rabais_cents;
    new.tps_cents := old.tps_cents; new.tvq_cents := old.tvq_cents;
    new.total_cents := old.total_cents; new.depot_cents := old.depot_cents;
    if new.depot_bp is distinct from old.depot_bp or new.client_id is distinct from old.client_id
       or new.date_devis is distinct from old.date_devis then
      if old.statut <> 'brouillon' then
        raise exception 'Devis non modifiable (statut %)', old.statut using errcode = '42501';
      end if;
      null;
    end if;
  end if;
  return new;
end $$;
create trigger trg_devis_numero before insert or update on public.devis
  for each row execute function app.devis_numero();
create or replace function app.devis_apres_maj() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform app.recalculer_devis(new.id);
  return null;
end $$;
create trigger trg_devis_apres_maj after update of depot_bp, client_id, date_devis on public.devis
  for each row when (pg_trigger_depth() = 0) execute function app.devis_apres_maj();
create or replace function app.devis_ligne_calcul() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_vendeur uuid; v_statut text;
begin
  select vendeur_id, statut into v_vendeur, v_statut from public.devis
   where id = coalesce(new.devis_id, old.devis_id);
  if v_statut <> 'brouillon' then
    raise exception 'Devis non modifiable (statut %)', v_statut using errcode = '42501';
  end if;
  if tg_op = 'DELETE' then return old; end if;
  new.montant_cents := round(new.quantite * new.prix_unitaire_cents * (10000 - new.rabais_bp) / 10000.0)::bigint;
  new.plafond_bp := case when new.produit_id is not null
                         then app.plafond_rabais_bp(new.produit_id, v_vendeur)
                         else app.plafond_rabais_bp(null, v_vendeur) end;
  new.approbation_requise := new.rabais_bp > new.plafond_bp;
  return new;
end $$;
create trigger trg_devis_ligne_calcul before insert or update or delete on public.devis_lignes
  for each row execute function app.devis_ligne_calcul();
create or replace function app.recalculer_devis(p_devis uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  d public.devis%rowtype; c public.clients%rowtype;
  v_brut bigint; v_net bigint; v_taxable bigint; v_tps bigint; v_tvq bigint;
begin
  select * into d from public.devis where id = p_devis;
  select * into c from public.clients where id = d.client_id;
  select coalesce(sum(round(quantite * prix_unitaire_cents)::bigint), 0),
         coalesce(sum(montant_cents), 0),
         coalesce(sum(montant_cents) filter (where taxable), 0)
    into v_brut, v_net, v_taxable
    from public.devis_lignes where devis_id = p_devis;
  select t.tps, t.tvq into v_tps, v_tvq
    from app.taxes(v_taxable, d.date_devis, c.exemption_tps, c.exemption_tvq) t;
  update public.devis set
    sous_total_cents = v_net,
    rabais_cents     = v_brut - v_net,
    tps_cents        = v_tps,
    tvq_cents        = v_tvq,
    total_cents      = v_net + v_tps + v_tvq,
    depot_cents      = round((v_net + v_tps + v_tvq) * depot_bp / 10000.0)::bigint
  where id = p_devis;
end $$;
create or replace function app.devis_lignes_apres() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform app.recalculer_devis(coalesce(new.devis_id, old.devis_id));
  return null;
end $$;
create trigger trg_devis_lignes_apres after insert or update or delete on public.devis_lignes
  for each row execute function app.devis_lignes_apres();
create or replace function app.devis_statut_garde() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.statut in ('envoye','accepte') and old.statut is distinct from new.statut then
    if exists (
      select 1 from public.devis_lignes l
       where l.devis_id = new.id and l.approbation_requise
         and not exists (select 1 from public.approbations_rabais a
                          where a.devis_ligne_id = l.id and a.statut = 'approuvee'
                            and a.rabais_bp >= l.rabais_bp)
    ) then
      raise exception 'Devis % : rabais hors plafond en attente d''approbation', new.numero
        using errcode = 'P0001';
    end if;
  end if;
  if new.statut = 'accepte' and old.statut <> 'accepte' then new.accepte_le := coalesce(new.accepte_le, now()); end if;
  if new.statut = 'refuse'  and old.statut <> 'refuse'  then new.refuse_le  := coalesce(new.refuse_le, now()); end if;
  return new;
end $$;
create trigger trg_devis_statut_garde before update of statut on public.devis
  for each row execute function app.devis_statut_garde();
create or replace function app.approbation_garde() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    if new.statut <> 'en_attente' or new.decide_par is not null then
      raise exception 'Une demande d''approbation est créée en attente' using errcode = '42501';
    end if;
    return new;
  end if;
  if (new.rabais_bp, new.plafond_bp, new.devis_ligne_id, new.demande_par)
     is distinct from (old.rabais_bp, old.plafond_bp, old.devis_ligne_id, old.demande_par) then
    raise exception 'Une demande d''approbation ne se modifie pas' using errcode = '42501';
  end if;
  if new.statut <> old.statut then
    if old.statut <> 'en_attente' then
      raise exception 'Décision déjà rendue' using errcode = '42501';
    end if;
    new.decide_par := coalesce(new.decide_par, app.employe_id());
    new.decide_le  := now();
    if not exists (select 1 from public.employes where id = new.decide_par and peut_approuver_rabais and actif) then
      raise exception 'Seuls Mike ou Simon peuvent approuver un rabais hors plafond' using errcode = '42501';
    end if;
  end if;
  return new;
end $$;
create trigger trg_approbation_garde before insert or update on public.approbations_rabais
  for each row execute function app.approbation_garde();
create trigger trg_approbation_delete before delete on public.approbations_rabais
  for each row execute function app.interdit();
create trigger trg_audit after insert or update on public.approbations_rabais
  for each row execute function app.audit();
create trigger trg_audit after insert or update or delete on public.devis
  for each row execute function app.audit();
create trigger trg_devis_delete before delete on public.devis
  for each row execute function app.interdit();

-- ===== 20261022000600_operations.sql =====
create table public.projets (
  id                    uuid primary key default gen_random_uuid(),
  code_projet           text unique,                    -- XXX-XXX-XXX, attribué par la base
  division              text not null default 'Ventilation' references public.divisions(nom),
  succursale_code       text not null references public.succursales(code),
  client_id             uuid not null references public.clients(id),
  site_id               uuid references public.sites(id),
  devis_id              uuid unique references public.devis(id),
  vendeur_id            uuid references public.employes(id),
  chef_projet_id        uuid references public.employes(id),
  statut                text not null default 'a_planifier' check (statut in (
                          'a_planifier','planifie','en_cours','termine','facture','ferme','annule')),
  installation_prevue_le timestamptz,
  installation_terminee_le timestamptz,
  solde_du_le           timestamptz,
  notes                 text,
  created_by            uuid references public.employes(id) default app.employe_id(),
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now()
);
call app.preparer_table('public.projets');
create index on public.projets (succursale_code, statut);
create or replace function app.projet_avant() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_lettre text;
begin
  if tg_op = 'INSERT' then
    select lettre into v_lettre from public.divisions where nom = new.division;
    new.code_projet := app.prochain_numero('projet', new.succursale_code, v_lettre, current_date);
  elsif new.code_projet is distinct from old.code_projet then
    raise exception 'Le code projet ne se modifie pas' using errcode = '42501';
  end if;
  new.solde_du_le := new.installation_prevue_le
    - coalesce((select (valeur #>> '{}')::int from public.parametres where cle = 'delai_solde_heures'), 72)
      * interval '1 hour';
  return new;
end $$;
create trigger trg_projet_avant before insert or update on public.projets
  for each row execute function app.projet_avant();
create trigger trg_projet_delete before delete on public.projets
  for each row execute function app.interdit();
create table public.equipements_installes (
  id                   uuid primary key default gen_random_uuid(),
  projet_id            uuid references public.projets(id),
  client_id            uuid not null references public.clients(id),
  site_id              uuid references public.sites(id),
  produit_id           uuid references public.produits(id),
  role                 text not null check (role in ('exterieur','interieur','fournaise','echangeur_air','climatiseur','autre')),
  marque               text,
  modele               text not null,
  numero_serie         text,
  ahri                 text,
  energy_star          text check (energy_star is null or energy_star ~ '^\d{7}$'),
  btu_nominal          integer,
  installe_le          date,
  photo_plaque_id      uuid references public.documents(id),
  garantie_fin         date,
  actif                boolean not null default true,   -- false si remplacé
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now()
);
call app.preparer_table('public.equipements_installes');
create unique index on public.equipements_installes (lower(marque), lower(numero_serie))
  where numero_serie is not null;
create index on public.equipements_installes (projet_id);
create table public.appels_service (
  id              uuid primary key default gen_random_uuid(),
  numero          text unique,
  division        text not null default 'Ventilation' references public.divisions(nom),
  succursale_code text not null references public.succursales(code),
  client_id       uuid not null references public.clients(id),
  site_id         uuid references public.sites(id),
  equipement_id   uuid references public.equipements_installes(id),
  contrat_id      uuid,
  type            text not null default 'reparation' check (type in ('urgence','reparation','entretien','garantie','inspection')),
  priorite        text not null default 'normale' check (priorite in ('basse','normale','haute','urgente')),
  statut          text not null default 'ouvert' check (statut in ('ouvert','planifie','en_cours','termine','facture','annule')),
  description     text,
  facturable      boolean not null default true,
  technicien_id   uuid references public.employes(id),
  prevu_le        timestamptz,
  created_by      uuid references public.employes(id) default app.employe_id(),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
call app.preparer_table('public.appels_service');
create table public.contrats_entretien (
  id                  uuid primary key default gen_random_uuid(),
  numero              text unique,
  succursale_code     text not null references public.succursales(code),
  client_id           uuid not null references public.clients(id),
  site_id             uuid references public.sites(id),
  debut               date not null,
  fin                 date,
  frequence_mois      integer not null default 12 check (frequence_mois > 0),
  prochain_entretien  date not null,
  rappel_jours_avant  integer not null default 30,
  prix_cents          bigint not null default 0,
  renouvellement_auto boolean not null default true,
  statut              text not null default 'actif' check (statut in ('actif','suspendu','termine','annule')),
  dernier_rappel_le   timestamptz,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);
call app.preparer_table('public.contrats_entretien', false);
alter table public.appels_service
  add constraint appels_service_contrat_fk foreign key (contrat_id) references public.contrats_entretien(id);
create table public.bons_travail (
  id                     uuid primary key default gen_random_uuid(),
  numero                 text unique,
  division               text not null default 'Ventilation' references public.divisions(nom),
  succursale_code        text not null references public.succursales(code),
  projet_id              uuid references public.projets(id),
  appel_service_id       uuid references public.appels_service(id),
  assigne_employe_id     uuid references public.employes(id),
  assigne_fournisseur_id uuid references public.fournisseurs(id),   -- sous-traitant
  prevu_le               timestamptz,
  debut_le               timestamptz,
  fin_le                 timestamptz,
  statut                 text not null default 'planifie' check (statut in ('planifie','en_cours','termine','annule')),
  travaux                text,
  notes_technicien       text,
  signature_id           uuid references public.documents(id),
  modifie_hors_ligne_le  timestamptz,       -- horodatage appareil, pour la résolution de conflits
  created_by             uuid references public.employes(id) default app.employe_id(),
  created_at             timestamptz not null default now(),
  updated_at             timestamptz not null default now(),
  check (projet_id is not null or appel_service_id is not null)
);
call app.preparer_table('public.bons_travail');
create index on public.bons_travail (assigne_employe_id, prevu_le);
create table public.bt_lignes (
  id           uuid primary key default gen_random_uuid(),
  bon_travail_id uuid not null references public.bons_travail(id),
  produit_id   uuid references public.produits(id),
  description  text not null,
  quantite     numeric(10,2) not null default 1,
  heures       numeric(6,2),
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
call app.preparer_table('public.bt_lignes', false);
create or replace function app.numeroter() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    new.numero := app.prochain_numero(tg_argv[0], new.succursale_code, null, current_date);
  elsif new.numero is distinct from old.numero then
    raise exception 'Le numéro ne se modifie pas' using errcode = '42501';
  end if;
  return new;
end $$;
create trigger trg_numero before insert or update on public.bons_travail
  for each row execute function app.numeroter('bt');
create trigger trg_numero before insert or update on public.appels_service
  for each row execute function app.numeroter('asv');
create trigger trg_numero before insert or update on public.contrats_entretien
  for each row execute function app.numeroter('contrat');
create or replace function app.bt_certif_garde() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_date date := coalesce(new.prevu_le, now())::date;
begin
  if app.parametre_bool('bloquer_certifs_expirees', false) and exists (
       select 1 from public.certifications c
        where c.expire_le < v_date
          and ((new.assigne_employe_id is not null and c.employe_id = new.assigne_employe_id)
            or (new.assigne_fournisseur_id is not null and c.fournisseur_id = new.assigne_fournisseur_id))) then
    raise exception 'Assignation refusée : certification expirée' using errcode = 'P0001';
  end if;
  return new;
end $$;
create trigger trg_bt_certif before insert or update of assigne_employe_id, assigne_fournisseur_id, prevu_le
  on public.bons_travail for each row execute function app.bt_certif_garde();

-- ===== 20261022000700_facturation.sql =====
create table public.factures (
  id                  uuid primary key default gen_random_uuid(),
  numero              text unique,          -- attribué à l'émission seulement : un brouillon n'a pas de numéro
  type                text not null check (type in ('depot','solde','progressive','finale','service','credit')),
  statut              text not null default 'brouillon' check (statut in ('brouillon','emise','payee')),
  division            text not null default 'Ventilation' references public.divisions(nom),
  succursale_code     text not null references public.succursales(code),
  client_id           uuid not null references public.clients(id),
  projet_id           uuid references public.projets(id),
  devis_id            uuid references public.devis(id),
  appel_service_id    uuid references public.appels_service(id),
  facture_origine_id  uuid references public.factures(id),     -- obligatoire pour une note de crédit
  emise_le            timestamptz,
  echeance_le         timestamptz,
  sous_total_cents    bigint not null default 0,
  tps_cents           bigint not null default 0,
  tvq_cents           bigint not null default 0,
  total_cents         bigint not null default 0,
  montant_paye_cents  bigint not null default 0,
  notes               text,
  created_by          uuid references public.employes(id) default app.employe_id(),
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  check (type <> 'credit' or facture_origine_id is not null)
);
call app.preparer_table('public.factures');
create index on public.factures (succursale_code, statut);
create index on public.factures (projet_id);
create table public.facture_lignes (
  id                  uuid primary key default gen_random_uuid(),
  facture_id          uuid not null references public.factures(id),
  position            integer not null default 1,
  produit_id          uuid references public.produits(id),
  description         text not null,
  quantite            numeric(10,2) not null default 1 check (quantite > 0),
  prix_unitaire_cents bigint not null check (prix_unitaire_cents >= 0),
  rabais_bp           integer not null default 0 check (rabais_bp between 0 and 10000),
  taxable             boolean not null default true,
  montant_cents       bigint not null default 0,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);
call app.preparer_table('public.facture_lignes', false);
create index on public.facture_lignes (facture_id);
create table public.paiements (
  id              uuid primary key default gen_random_uuid(),
  facture_id      uuid not null references public.factures(id),
  montant_cents   bigint not null check (montant_cents <> 0),   -- négatif = remboursement
  mode            text not null check (mode in ('carte','debit','virement','cheque','comptant','financeit','stripe','autre')),
  recu_le         timestamptz not null default now(),
  reference       text,
  recu_par        uuid references public.employes(id) default app.employe_id(),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
call app.preparer_table('public.paiements');
create table public.financements (
  id              uuid primary key default gen_random_uuid(),
  fournisseur     text not null default 'Financeit',
  succursale_code text not null references public.succursales(code),
  client_id       uuid not null references public.clients(id),
  devis_id        uuid references public.devis(id),
  projet_id       uuid references public.projets(id),
  statut          text not null default 'a_soumettre' check (statut in (
                    'a_soumettre','soumis','approuve','refuse','finance','annule')),
  montant_cents   bigint not null check (montant_cents > 0),
  reference       text,
  soumis_le       timestamptz,
  decision_le     timestamptz,
  verse_le        timestamptz,
  notes           text,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
call app.preparer_table('public.financements', false);
create table public.subventions (
  id                     uuid primary key default gen_random_uuid(),
  programme              text not null default 'LogisVert',
  succursale_code        text not null references public.succursales(code),
  client_id              uuid not null references public.clients(id),
  projet_id              uuid references public.projets(id),
  mode_depot             text not null default 'client' check (mode_depot in ('client','accompagne')),  -- ADR-008
  accompagne_par         uuid references public.employes(id),
  statut                 text not null default 'a_preparer' check (statut in (
                           'a_preparer','documents_remis','deposee','incomplete','approuvee','refusee','versee','abandonnee')),
  date_premiere_mesure   date,          -- le délai de 9 mois part de la première mesure installée
  date_limite            date,
  majoration_5pct        boolean not null default false,
  montant_estime_cents   bigint,
  montant_recu_cents     bigint,
  numero_dossier         text,
  deposee_le             date,
  notes                  text,
  created_at             timestamptz not null default now(),
  updated_at             timestamptz not null default now(),
  check (mode_depot = 'client' or accompagne_par is not null)
);
call app.preparer_table('public.subventions');
create or replace function app.subvention_avant() returns trigger
language plpgsql as $$
begin
  if new.programme = 'LogisVert' and new.date_premiere_mesure is not null then
    new.date_limite := (new.date_premiere_mesure + interval '9 months')::date;
  end if;
  return new;
end $$;
create trigger trg_subvention_avant before insert or update on public.subventions
  for each row execute function app.subvention_avant();
create or replace function app.facture_ligne_avant() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_statut text;
begin
  select statut into v_statut from public.factures where id = coalesce(new.facture_id, old.facture_id);
  if v_statut <> 'brouillon' then
    raise exception 'Facture émise : non modifiable. Faire une note de crédit.' using errcode = '42501';
  end if;
  if tg_op = 'DELETE' then return old; end if;
  new.montant_cents := round(new.quantite * new.prix_unitaire_cents * (10000 - new.rabais_bp) / 10000.0)::bigint;
  return new;
end $$;
create trigger trg_facture_ligne_avant before insert or update or delete on public.facture_lignes
  for each row execute function app.facture_ligne_avant();
create or replace function app.recalculer_facture(p_facture uuid) returns void
language plpgsql security definer set search_path = public as $$
declare f public.factures%rowtype; c public.clients%rowtype; v_net bigint; v_taxable bigint; v_tps bigint; v_tvq bigint;
begin
  select * into f from public.factures where id = p_facture;
  select * into c from public.clients where id = f.client_id;
  select coalesce(sum(montant_cents), 0), coalesce(sum(montant_cents) filter (where taxable), 0)
    into v_net, v_taxable from public.facture_lignes where facture_id = p_facture;
  select t.tps, t.tvq into v_tps, v_tvq
    from app.taxes(v_taxable, coalesce(f.emise_le, now())::date, c.exemption_tps, c.exemption_tvq) t;
  update public.factures set sous_total_cents = v_net, tps_cents = v_tps, tvq_cents = v_tvq,
         total_cents = v_net + v_tps + v_tvq
   where id = p_facture;
end $$;
create or replace function app.facture_lignes_apres() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform app.recalculer_facture(coalesce(new.facture_id, old.facture_id));
  return null;
end $$;
create trigger trg_facture_lignes_apres after insert or update or delete on public.facture_lignes
  for each row execute function app.facture_lignes_apres();
create or replace function app.manques_logisvert(p_facture uuid) returns text[]
language plpgsql stable security definer set search_path = public as $$
declare
  f public.factures%rowtype; c public.clients%rowtype; p public.projets%rowtype;
  m text[] := '{}';
begin
  select * into f from public.factures where id = p_facture;
  if f.projet_id is null or not exists (
       select 1 from public.subventions s where s.projet_id = f.projet_id and s.programme = 'LogisVert'
         and s.statut <> 'abandonnee') then
    return m;
  end if;
  select * into c from public.clients where id = f.client_id;
  select * into p from public.projets where id = f.projet_id;
  if c.est_proprietaire is not true then m := array_append(m, 'client non confirmé propriétaire'); end if;
  if c.nom_preuve_propriete is null then
    m := array_append(m, 'nom de la preuve de propriété absent');
  elsif lower(trim(c.nom_preuve_propriete)) <> lower(trim(coalesce(c.prenom || ' ', '') || c.nom)) then
    m := array_append(m, 'nom du client différent de la preuve de propriété');
  end if;
  if p.installation_terminee_le is null then m := array_append(m, 'date d''installation absente'); end if;
  if not exists (select 1 from public.equipements_installes e
                  where e.projet_id = f.projet_id and e.role = 'exterieur' and e.actif) then
    m := array_append(m, 'aucun appareil extérieur');
  end if;
  if exists (select 1 from public.equipements_installes e
              where e.projet_id = f.projet_id and e.role = 'exterieur' and e.actif
                and (e.numero_serie is null or (e.ahri is null and e.energy_star is null)
                     or e.btu_nominal is null or e.photo_plaque_id is null)) then
    m := array_append(m, 'appareil extérieur incomplet (S/N, AHRI ou ENERGY STAR, BTU, photo de la plaque)');
  end if;
  return m;
end $$;
create or replace function app.facture_avant() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_manques text[];
begin
  if tg_op = 'INSERT' then
    if new.statut <> 'brouillon' or new.numero is not null then
      raise exception 'Une facture est créée en brouillon, sans numéro' using errcode = '42501';
    end if;
    new.sous_total_cents := 0; new.tps_cents := 0; new.tvq_cents := 0;
    new.total_cents := 0; new.montant_paye_cents := 0;
    return new;
  end if;
  if pg_trigger_depth() = 1 then
    new.sous_total_cents := old.sous_total_cents; new.tps_cents := old.tps_cents;
    new.tvq_cents := old.tvq_cents; new.total_cents := old.total_cents;
    new.montant_paye_cents := old.montant_paye_cents;
  end if;
  if new.numero is distinct from old.numero and old.numero is not null then
    raise exception 'Le numéro de facture ne se modifie pas' using errcode = '42501';
  end if;
  if old.statut = 'brouillon' and new.statut = 'emise' then
    if new.type in ('solde','finale') then
      v_manques := app.manques_logisvert(new.id);
      if array_length(v_manques, 1) > 0 and app.parametre_bool('bloquer_facture_logisvert_incomplete', true) then
        raise exception 'Facture non conforme LogisVert : %', array_to_string(v_manques, ', ') using errcode = 'P0001';
      end if;
    end if;
    new.emise_le := now();
    new.numero := app.prochain_numero(case when new.type = 'credit' then 'note_credit' else 'facture' end,
                                      new.succursale_code, null, new.emise_le::date);
  elsif old.statut <> 'brouillon' then
    if (new.type, new.client_id, new.projet_id, new.sous_total_cents, new.tps_cents, new.tvq_cents,
        new.total_cents, new.emise_le, new.succursale_code)
       is distinct from
       (old.type, old.client_id, old.projet_id, old.sous_total_cents, old.tps_cents, old.tvq_cents,
        old.total_cents, old.emise_le, old.succursale_code) then
      raise exception 'Facture émise : non modifiable. Faire une note de crédit.' using errcode = '42501';
    end if;
    if new.statut = 'brouillon' then
      raise exception 'Une facture émise ne revient pas en brouillon' using errcode = '42501';
    end if;
    if pg_trigger_depth() = 1 and new.statut is distinct from old.statut then
      raise exception 'Le statut payé découle des paiements saisis' using errcode = '42501';
    end if;
  elsif new.statut = 'payee' then
    raise exception 'Une facture doit être émise avant d''être payée' using errcode = 'P0001';
  end if;
  return new;
end $$;
create trigger trg_facture_avant before insert or update on public.factures
  for each row execute function app.facture_avant();
create trigger trg_facture_delete before delete on public.factures
  for each row execute function app.interdit();
create trigger trg_audit after insert or update on public.factures
  for each row execute function app.audit();
create or replace function app.paiement_apres() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_paye bigint; v_total bigint; v_statut text;
begin
  select statut, total_cents into v_statut, v_total from public.factures where id = new.facture_id;
  if v_statut = 'brouillon' then
    raise exception 'Paiement sur une facture en brouillon' using errcode = 'P0001';
  end if;
  select coalesce(sum(montant_cents), 0) into v_paye from public.paiements where facture_id = new.facture_id;
  update public.factures
     set montant_paye_cents = v_paye,
         statut = case when v_paye >= v_total then 'payee' else 'emise' end
   where id = new.facture_id;
  return null;
end $$;
create trigger trg_paiement_apres after insert on public.paiements
  for each row execute function app.paiement_apres();
create trigger trg_paiement_immuable before update or delete on public.paiements
  for each row execute function app.interdit();
create trigger trg_audit after insert on public.paiements
  for each row execute function app.audit();

-- ===== 20261022000800_rls.sql =====
create or replace function app.acces_succursale(p_code text) returns boolean
language sql stable as $$
  select app.voit_tout()
      or (coalesce(app.role() in ('Gérant de succursale','Vendeur','Coordonnateur'), false)
          and p_code = any(app.mes_succursales()))
$$;
create or replace function app.est_facturation() returns boolean
language sql stable as $$
  select coalesce(app.role() in ('Admin tout','Direction','Comptabilité','Coordonnateur','Gérant de succursale'), false)
$$;
create or replace function app.technicien_sur_projet(p_projet uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.bons_travail
                  where projet_id = p_projet and assigne_employe_id = app.employe_id() and statut <> 'annule')
$$;
create or replace function app.technicien_voit_client(p_client uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.bons_travail bt
                   left join public.projets p on p.id = bt.projet_id
                   left join public.appels_service a on a.id = bt.appel_service_id
                  where bt.assigne_employe_id = app.employe_id() and bt.statut <> 'annule'
                    and (p.client_id = p_client or a.client_id = p_client))
      or exists (select 1 from public.appels_service
                  where technicien_id = app.employe_id() and client_id = p_client)
      or exists (select 1 from public.inspections
                  where inspecteur_id = app.employe_id() and client_id = p_client)
$$;
create or replace function app.voit_client(p_client uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select app.acces_succursale((select succursale_code from public.clients where id = p_client))
      or app.technicien_voit_client(p_client)
$$;
create or replace function app.voit_devis(p_devis uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select app.acces_succursale((select succursale_code from public.devis where id = p_devis))
$$;
create or replace function app.voit_projet(p_projet uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select app.acces_succursale((select succursale_code from public.projets where id = p_projet))
      or app.technicien_sur_projet(p_projet)
$$;
create or replace function app.voit_bt(p_bt uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.bons_travail
                  where id = p_bt and (assigne_employe_id = app.employe_id() or app.acces_succursale(succursale_code)))
$$;
create or replace function app.voit_facture(p_facture uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select app.acces_succursale((select succursale_code from public.factures where id = p_facture))
$$;
revoke all on all tables in schema public from anon;
revoke all on all sequences in schema public from anon;
grant usage on schema app to authenticated;
grant execute on all functions in schema app to authenticated;
revoke execute on function app.prochain_numero(text, text, text, date) from authenticated;
do $$
declare t text;
begin
  for t in select tablename from pg_tables where schemaname = 'public' loop
    execute format('alter table public.%I enable row level security', t);
  end loop;
end $$;
do $$
declare t text;
begin
  foreach t in array array['succursales','divisions','parametres','taux_taxes','formats_numerotation',
                           'marques','produits','kits','kit_items','fournisseurs','employes','employe_succursales'] loop
    execute format('create policy lecture on public.%I for select to authenticated using (app.employe_id() is not null)', t);
    execute format('create policy ajout_admin on public.%I for insert to authenticated with check (app.est_admin())', t);
    execute format('create policy maj_admin on public.%I for update to authenticated using (app.est_admin()) with check (app.est_admin())', t);
  end loop;
end $$;
create policy lecture_admin on public.journal_audit for select to authenticated using (app.est_admin());
create policy lecture on public.certifications for select to authenticated
  using (app.est_admin() or app.role() = 'Gérant de succursale' or employe_id = app.employe_id());
create policy ecriture on public.certifications for insert to authenticated
  with check (app.est_admin() or app.role() = 'Gérant de succursale');
create policy maj on public.certifications for update to authenticated
  using (app.est_admin() or app.role() = 'Gérant de succursale');
create policy lecture on public.clients for select to authenticated
  using (app.acces_succursale(succursale_code) or app.technicien_voit_client(id));
create policy ajout on public.clients for insert to authenticated
  with check (app.acces_succursale(succursale_code));
create policy maj on public.clients for update to authenticated
  using (app.acces_succursale(succursale_code)) with check (app.acces_succursale(succursale_code));
create policy lecture on public.sites for select to authenticated using (app.voit_client(client_id));
create policy ajout on public.sites for insert to authenticated
  with check (app.acces_succursale((select succursale_code from public.clients c where c.id = client_id)));
create policy maj on public.sites for update to authenticated
  using (app.acces_succursale((select succursale_code from public.clients c where c.id = client_id)));
do $$
declare t text;
begin
  foreach t in array array['leads','devis','contrats_entretien','financements','subventions'] loop
    execute format('create policy lecture on public.%I for select to authenticated using (app.acces_succursale(succursale_code))', t);
    execute format('create policy ajout on public.%I for insert to authenticated with check (app.acces_succursale(succursale_code))', t);
    execute format('create policy maj on public.%I for update to authenticated using (app.acces_succursale(succursale_code)) with check (app.acces_succursale(succursale_code))', t);
  end loop;
end $$;
create policy lecture on public.inspections for select to authenticated
  using (app.acces_succursale(succursale_code) or inspecteur_id = app.employe_id());
create policy ajout on public.inspections for insert to authenticated
  with check (app.acces_succursale(succursale_code));
create policy maj on public.inspections for update to authenticated
  using (app.acces_succursale(succursale_code) or inspecteur_id = app.employe_id());
create policy lecture on public.devis_lignes for select to authenticated using (app.voit_devis(devis_id));
create policy ajout on public.devis_lignes for insert to authenticated with check (app.voit_devis(devis_id));
create policy maj on public.devis_lignes for update to authenticated using (app.voit_devis(devis_id));
create policy retrait on public.devis_lignes for delete to authenticated using (app.voit_devis(devis_id));
create policy lecture on public.approbations_rabais for select to authenticated
  using (app.voit_devis(devis_id) or app.peut_approuver_rabais());
create policy demande on public.approbations_rabais for insert to authenticated
  with check (app.voit_devis(devis_id) and statut = 'en_attente');
create policy decision on public.approbations_rabais for update to authenticated
  using (app.peut_approuver_rabais()) with check (app.peut_approuver_rabais());
create policy lecture on public.delegations_rabais for select to authenticated
  using (employe_id = app.employe_id() or app.peut_approuver_rabais() or app.est_admin());
create policy ajout on public.delegations_rabais for insert to authenticated with check (app.peut_approuver_rabais());
create policy maj on public.delegations_rabais for update to authenticated using (app.peut_approuver_rabais());
create policy lecture on public.projets for select to authenticated using (app.voit_projet(id));
create policy ajout on public.projets for insert to authenticated with check (app.acces_succursale(succursale_code));
create policy maj on public.projets for update to authenticated
  using (app.acces_succursale(succursale_code)) with check (app.acces_succursale(succursale_code));
create policy lecture on public.equipements_installes for select to authenticated
  using (app.voit_client(client_id));
create policy ajout on public.equipements_installes for insert to authenticated
  with check (app.voit_client(client_id) and (projet_id is null or app.voit_projet(projet_id)));
create policy maj on public.equipements_installes for update to authenticated
  using (app.voit_client(client_id) and (projet_id is null or app.voit_projet(projet_id)));
create policy lecture on public.appels_service for select to authenticated
  using (app.acces_succursale(succursale_code) or technicien_id = app.employe_id());
create policy ajout on public.appels_service for insert to authenticated with check (app.acces_succursale(succursale_code));
create policy maj on public.appels_service for update to authenticated
  using (app.acces_succursale(succursale_code) or technicien_id = app.employe_id());
create policy lecture on public.bons_travail for select to authenticated using (app.voit_bt(id));
create policy ajout on public.bons_travail for insert to authenticated with check (app.acces_succursale(succursale_code));
create policy maj on public.bons_travail for update to authenticated
  using (app.acces_succursale(succursale_code) or assigne_employe_id = app.employe_id());
create policy lecture on public.bt_lignes for select to authenticated using (app.voit_bt(bon_travail_id));
create policy ajout on public.bt_lignes for insert to authenticated with check (app.voit_bt(bon_travail_id));
create policy maj on public.bt_lignes for update to authenticated using (app.voit_bt(bon_travail_id));
create policy lecture on public.factures for select to authenticated using (app.acces_succursale(succursale_code));
create policy ajout on public.factures for insert to authenticated
  with check (app.est_facturation() and app.acces_succursale(succursale_code));
create policy maj on public.factures for update to authenticated
  using (app.est_facturation() and app.acces_succursale(succursale_code));
create policy lecture on public.facture_lignes for select to authenticated using (app.voit_facture(facture_id));
create policy ajout on public.facture_lignes for insert to authenticated
  with check (app.est_facturation() and app.voit_facture(facture_id));
create policy maj on public.facture_lignes for update to authenticated
  using (app.est_facturation() and app.voit_facture(facture_id));
create policy retrait on public.facture_lignes for delete to authenticated
  using (app.est_facturation() and app.voit_facture(facture_id));
create policy lecture on public.paiements for select to authenticated using (app.voit_facture(facture_id));
create policy ajout on public.paiements for insert to authenticated
  with check (app.est_facturation() and app.voit_facture(facture_id));
create policy lecture on public.documents for select to authenticated
  using (app.acces_succursale(succursale_code) or created_by = app.employe_id());
create policy ajout on public.documents for insert to authenticated
  with check (app.employe_id() is not null and succursale_code = any(app.mes_succursales())
              or app.voit_tout());
create policy maj on public.documents for update to authenticated
  using (app.acces_succursale(succursale_code));

-- ===== 20261022000900_referentiels.sql =====
insert into public.succursales (code, nom, ville, est_entrepot) values
  ('HO', 'Head Office | Saint-Jérôme (succursale et entrepôt central)', 'Saint-Jérôme', true),
  ('ST', 'St-Sauveur',    'Saint-Sauveur', false),
  ('RO', 'Rosemère',      'Rosemère',      false),
  ('DR', 'Drummondville', 'Drummondville', false),
  ('GA', 'Gatineau',      'Gatineau',      false);
insert into public.divisions (nom, lettre, code_generique, est_hvac) values
  ('Ventilation',   'V', 'VTC', true),
  ('Climatisation', 'V', 'VTC', true),
  ('Foyer',         'F', 'FYR', false),
  ('Foyer-Gaz',     'F', 'FYG', false),
  ('Gaz',           'F', 'FYG', false),
  ('BBQ',           'B', 'BBQ', false);
insert into public.taux_taxes (code, taux_pcm, en_vigueur_du) values
  ('TPS', 5000, '2008-01-01'),
  ('TVQ', 9975, '2013-01-01');
insert into public.formats_numerotation (cle, modele, prefixe, portee, description) values
  ('devis',       '{prefixe}-{annee}-{seq:5}', 'D',   'annuelle',  'Provisoire. Format de Mike à confirmer.'),
  ('facture',     '{prefixe}-{annee}-{seq:5}', 'F',   'annuelle',  'Provisoire. Série unique, sans trou.'),
  ('note_credit', '{prefixe}-{annee}-{seq:5}', 'NC',  'annuelle',  'Provisoire. Série distincte des factures, à confirmer.'),
  ('projet',      '{succ}{div}-{seq:3}-{aa}',  '',    'succursale_annuelle', 'Provisoire. Format XXX-XXX-XXX de Mike à confirmer (2e et 3e segments inconnus).'),
  ('bt',          '{prefixe}-{annee}-{seq:5}', 'BT',  'annuelle',  'Provisoire.'),
  ('asv',         '{prefixe}-{annee}-{seq:5}', 'ASV', 'annuelle',  'Appel de service ventilation. Provisoire.'),
  ('contrat',     '{prefixe}-{annee}-{seq:4}', 'CE',  'annuelle',  'Contrat d''entretien. Provisoire.');
insert into public.parametres (cle, valeur, description) values
  ('bloquer_certifs_expirees', 'false', 'Refuser l''assignation d''un BT si une certification est expirée (ADR-015).'),
  ('bloquer_facture_logisvert_incomplete', 'true', 'Refuser l''émission d''une facture de solde ou finale si une pièce LogisVert manque (ADR-008).'),
  ('delai_solde_heures', '72', 'Le solde est dû X heures avant l''installation (ADR-009).');

-- ===== 20261023000100_session.sql =====
create or replace function public.hvac_session() returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_email text := lower(auth.jwt() ->> 'email'); e public.employes%rowtype;
begin
  if auth.uid() is null then return null; end if;
  update public.employes set auth_user_id = auth.uid()
   where auth_user_id is null and lower(email) = v_email and actif;
  select * into e from public.employes where auth_user_id = auth.uid() and actif;
  if not found then return null; end if;
  return jsonb_build_object('id', e.id, 'monday_item_id', e.monday_item_id, 'email', e.email,
    'prenom', e.prenom, 'nom', e.nom, 'role', e.role, 'succursale_code', e.succursale_code,
    'peut_approuver_rabais', e.peut_approuver_rabais);
end $$;
create or replace function public.hvac_impersonation(p_employe uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare e public.employes%rowtype;
begin
  if coalesce(app.role(), '') <> 'Admin tout' then
    raise exception 'Impersonation réservée à « Admin tout »' using errcode = '42501';
  end if;
  select * into e from public.employes where id = p_employe and actif;
  if not found then raise exception 'Employé introuvable' using errcode = 'P0002'; end if;
  perform app.journaliser('impersonation', 'employes', e.id::text, jsonb_build_object('cible', e.email));
  return jsonb_build_object('id', e.id, 'monday_item_id', e.monday_item_id, 'email', e.email,
    'prenom', e.prenom, 'nom', e.nom, 'role', e.role, 'succursale_code', e.succursale_code,
    'peut_approuver_rabais', e.peut_approuver_rabais);
end $$;
revoke all on function public.hvac_session() from public, anon;
revoke all on function public.hvac_impersonation(uuid) from public, anon;
grant execute on function public.hvac_session() to authenticated;
grant execute on function public.hvac_impersonation(uuid) to authenticated;

-- ===== 20261023000200_devis_module.sql =====
insert into public.parametres (cle, valeur, description) values
  ('validite_devis_jours', '30', 'Un devis envoyé est valide X jours, puis il expire.')
on conflict (cle) do nothing;
create or replace function app.devis_ligne_calcul() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_vendeur uuid; v_statut text;
begin
  select vendeur_id, statut into v_vendeur, v_statut from public.devis
   where id = coalesce(new.devis_id, old.devis_id);
  if v_statut <> 'brouillon' then
    raise exception 'Devis non modifiable (statut %)', v_statut using errcode = '42501';
  end if;
  if tg_op = 'DELETE' then return old; end if;
  if new.produit_id is not null then
    select prix_cents into new.prix_unitaire_cents from public.produits where id = new.produit_id;
  elsif new.kit_id is not null then
    new.prix_unitaire_cents := public.hvac_prix_kit(new.kit_id);
  end if;
  new.montant_cents := round(new.quantite * new.prix_unitaire_cents * (10000 - new.rabais_bp) / 10000.0)::bigint;
  new.plafond_bp := case
    when new.kit_id is not null then 0
    when new.produit_id is not null then app.plafond_rabais_bp(new.produit_id, v_vendeur)
    else app.plafond_rabais_bp(null, v_vendeur) end;
  new.approbation_requise := new.rabais_bp > new.plafond_bp;
  return new;
end $$;
create or replace function app.devis_statut_garde() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_jours int := coalesce((select (valeur #>> '{}')::int from public.parametres where cle = 'validite_devis_jours'), 30);
begin
  if new.statut = old.statut then return new; end if;
  if new.statut in ('envoye','accepte') then
    if exists (
      select 1 from public.devis_lignes l
       where l.devis_id = new.id and l.approbation_requise
         and not exists (select 1 from public.approbations_rabais a
                          where a.devis_ligne_id = l.id and a.statut = 'approuvee'
                            and a.rabais_bp >= l.rabais_bp)
    ) then
      raise exception 'Devis % : rabais hors plafond en attente d''approbation', new.numero using errcode = 'P0001';
    end if;
    if not exists (select 1 from public.devis_lignes where devis_id = new.id) then
      raise exception 'Devis % : aucune ligne', new.numero using errcode = 'P0001';
    end if;
  end if;
  if new.statut = 'envoye' then
    if old.statut <> 'brouillon' then
      raise exception 'Seul un brouillon peut être envoyé' using errcode = 'P0001';
    end if;
    new.valide_jusqu := current_date + v_jours;
  end if;
  if new.statut in ('accepte','refuse') then
    if old.statut <> 'envoye' then
      raise exception 'Seul un devis envoyé peut être accepté ou refusé' using errcode = 'P0001';
    end if;
    if new.statut = 'accepte' and current_date > old.valide_jusqu then
      raise exception 'Devis % expiré le % : le renouveler', new.numero, old.valide_jusqu using errcode = 'P0001';
    end if;
  end if;
  if new.statut = 'accepte' then new.accepte_le := coalesce(new.accepte_le, now()); end if;
  if new.statut = 'refuse'  then new.refuse_le  := coalesce(new.refuse_le, now()); end if;
  return new;
end $$;
create or replace function app.approbation_garde() returns trigger
language plpgsql security definer set search_path = public as $$
declare l public.devis_lignes%rowtype;
begin
  if tg_op = 'INSERT' then
    if new.statut <> 'en_attente' or new.decide_par is not null then
      raise exception 'Une demande d''approbation est créée en attente' using errcode = '42501';
    end if;
    select * into l from public.devis_lignes where id = new.devis_ligne_id;
    if not found then raise exception 'Ligne de devis introuvable' using errcode = 'P0002'; end if;
    if not l.approbation_requise then
      raise exception 'Ce rabais est dans le plafond : aucune approbation requise' using errcode = 'P0001';
    end if;
    new.devis_id := l.devis_id; new.rabais_bp := l.rabais_bp; new.plafond_bp := l.plafond_bp;
    return new;
  end if;
  if (new.rabais_bp, new.plafond_bp, new.devis_ligne_id, new.demande_par)
     is distinct from (old.rabais_bp, old.plafond_bp, old.devis_ligne_id, old.demande_par) then
    raise exception 'Une demande d''approbation ne se modifie pas' using errcode = '42501';
  end if;
  if new.statut <> old.statut then
    if old.statut <> 'en_attente' then
      raise exception 'Décision déjà rendue' using errcode = '42501';
    end if;
    new.decide_par := coalesce(new.decide_par, app.employe_id());
    new.decide_le  := now();
    if not exists (select 1 from public.employes where id = new.decide_par and peut_approuver_rabais and actif) then
      raise exception 'Seuls Mike ou Simon peuvent approuver un rabais hors plafond' using errcode = '42501';
    end if;
  end if;
  return new;
end $$;
create or replace view public.devis_v with (security_invoker = true) as
  select d.*,
         case when d.statut = 'envoye' and d.valide_jusqu < current_date then 'expire' else d.statut end as statut_effectif,
         c.prenom as client_prenom, c.nom as client_nom, c.entreprise as client_entreprise,
         e.prenom || ' ' || e.nom as vendeur_nom,
         (select count(*) from public.approbations_rabais a where a.devis_id = d.id and a.statut = 'en_attente') as approbations_en_attente,
         exists (select 1 from public.devis_lignes l where l.devis_id = d.id and l.approbation_requise
                   and not exists (select 1 from public.approbations_rabais a where a.devis_ligne_id = l.id
                                    and a.statut = 'approuvee' and a.rabais_bp >= l.rabais_bp)) as bloque_par_rabais
    from public.devis d
    join public.clients c on c.id = d.client_id
    left join public.employes e on e.id = d.vendeur_id;
grant select on public.devis_v to authenticated;
revoke all on public.devis_v from anon;
create or replace function public.hvac_prix_kit(p_kit uuid) returns bigint
language sql stable security invoker set search_path = public as $$
  select coalesce(k.prix_cents,
                  (select coalesce(sum(round(ki.quantite * p.prix_cents)::bigint), 0)
                     from public.kit_items ki join public.produits p on p.id = ki.produit_id where ki.kit_id = k.id))
    from public.kits k where k.id = p_kit
$$;
create or replace function public.hvac_dupliquer_devis(p_devis uuid) returns uuid
language plpgsql security invoker set search_path = public as $$
declare d public.devis%rowtype; v_id uuid;
begin
  select * into d from public.devis where id = p_devis;
  if not found then raise exception 'Devis introuvable' using errcode = 'P0002'; end if;
  insert into public.devis (division, succursale_code, client_id, site_id, lead_id, inspection_id, vendeur_id,
                            mode_paiement, depot_bp, notes_client, notes_internes)
  values (d.division, d.succursale_code, d.client_id, d.site_id, d.lead_id, d.inspection_id,
          coalesce(app.employe_id(), d.vendeur_id), d.mode_paiement, d.depot_bp, d.notes_client,
          concat_ws(E'\n', d.notes_internes, 'Renouvellement du devis ' || d.numero))
  returning id into v_id;
  insert into public.devis_lignes (devis_id, position, produit_id, kit_id, description, quantite, prix_unitaire_cents, rabais_bp, taxable)
  select v_id, position, produit_id, kit_id, description, quantite, prix_unitaire_cents, rabais_bp, taxable
    from public.devis_lignes where devis_id = p_devis order by position;
  return v_id;
end $$;
revoke all on function public.hvac_prix_kit(uuid) from public, anon;
revoke all on function public.hvac_dupliquer_devis(uuid) from public, anon;
grant execute on function public.hvac_prix_kit(uuid) to authenticated;
grant execute on function public.hvac_dupliquer_devis(uuid) to authenticated;

-- ===== 20261023000300_installation.sql =====
insert into public.parametres (cle, valeur, description) values
  ('marge_installation_bp', '3000', 'Marge sur le prix de vente de l''installation, en points de base (3000 = 30 %). VALEUR PROVISOIRE, à fixer par Simon.')
on conflict (cle) do nothing;
create or replace function app.marge_installation_bp() returns integer
language sql stable as $$
  select coalesce((select (valeur #>> '{}')::int from public.parametres where cle = 'marge_installation_bp'), 3000)
$$;
create or replace function app.prix_avec_marge(p_cout bigint, p_marge_bp integer) returns bigint
language sql immutable as $$
  select round(p_cout * 10000.0 / (10000 - p_marge_bp))::bigint
$$;
create table public.types_travaux (
  id          uuid primary key default gen_random_uuid(),
  code        text not null unique,
  nom         text not null,
  division    text not null default 'Ventilation' references public.divisions(nom),
  description text,
  actif       boolean not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
call app.preparer_table('public.types_travaux');
create table public.tarifs_sous_traitants (
  id              uuid primary key default gen_random_uuid(),
  fournisseur_id  uuid not null references public.fournisseurs(id),
  type_travail_id uuid not null references public.types_travaux(id),
  cout_cents      bigint not null check (cout_cents > 0),
  en_vigueur_du   date not null default current_date,
  notes           text,
  created_by      uuid references public.employes(id) default app.employe_id(),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  unique (fournisseur_id, type_travail_id, en_vigueur_du)
);
call app.preparer_table('public.tarifs_sous_traitants', false);
create trigger trg_tarif_immuable before update or delete on public.tarifs_sous_traitants
  for each row execute function app.interdit();
create trigger trg_audit after insert on public.tarifs_sous_traitants
  for each row execute function app.audit();
create or replace function public.hvac_cout_installation(p_sous_traitant uuid, p_type uuid, p_date date default current_date)
returns bigint language sql stable security invoker set search_path = public as $$
  select cout_cents from public.tarifs_sous_traitants
   where fournisseur_id = p_sous_traitant and type_travail_id = p_type and en_vigueur_du <= p_date
   order by en_vigueur_du desc limit 1
$$;
revoke all on function public.hvac_cout_installation(uuid, uuid, date) from public, anon;
grant execute on function public.hvac_cout_installation(uuid, uuid, date) to authenticated;
alter table public.devis_lignes
  add column type_ligne text not null default 'libre'
    check (type_ligne in ('produit','kit','installation','libre')),
  add column type_travail_id uuid references public.types_travaux(id),
  add column sous_traitant_id uuid references public.fournisseurs(id),
  add column cout_cents bigint check (cout_cents is null or cout_cents > 0),
  add column source_cout text check (source_cout in ('grille','soumission')),
  add column reference_soumission text,
  add column marge_bp integer check (marge_bp is null or (marge_bp >= 0 and marge_bp < 10000));
update public.devis_lignes set type_ligne = case when kit_id is not null then 'kit'
                                                  when produit_id is not null then 'produit' else 'libre' end;
alter table public.devis_lignes add constraint devis_lignes_installation_chk check (
  type_ligne <> 'installation' or (type_travail_id is not null and produit_id is null and kit_id is null));
create or replace function app.devis_ligne_calcul() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_vendeur uuid; v_statut text; v_date date;
begin
  select vendeur_id, statut, date_devis into v_vendeur, v_statut, v_date from public.devis
   where id = coalesce(new.devis_id, old.devis_id);
  if v_statut <> 'brouillon' then
    raise exception 'Devis non modifiable (statut %)', v_statut using errcode = '42501';
  end if;
  if tg_op = 'DELETE' then return old; end if;
  new.type_ligne := case when new.type_ligne = 'installation' then 'installation'
                         when new.kit_id is not null then 'kit'
                         when new.produit_id is not null then 'produit' else 'libre' end;
  if new.type_ligne = 'produit' then
    select prix_cents into new.prix_unitaire_cents from public.produits where id = new.produit_id;
  elsif new.type_ligne = 'kit' then
    new.prix_unitaire_cents := public.hvac_prix_kit(new.kit_id);
  elsif new.type_ligne = 'installation' then
    if new.source_cout is distinct from 'soumission' then
      if new.sous_traitant_id is null then
        raise exception 'Installation : sous-traitant requis pour utiliser la grille' using errcode = 'P0001';
      end if;
      new.source_cout := 'grille';
      new.cout_cents := public.hvac_cout_installation(new.sous_traitant_id, new.type_travail_id, v_date);
      if new.cout_cents is null then
        raise exception 'Aucun prix dans la grille pour ce sous-traitant et ce type de travail : saisir une soumission'
          using errcode = 'P0001';
      end if;
    elsif new.cout_cents is null or coalesce(trim(new.reference_soumission), '') = '' then
      raise exception 'Soumission : coût et référence (no de soumission du sous-traitant) requis' using errcode = 'P0001';
    end if;
    new.marge_bp := case when tg_op = 'UPDATE' and old.marge_bp is not null then old.marge_bp
                         else app.marge_installation_bp() end;
    new.prix_unitaire_cents := app.prix_avec_marge(new.cout_cents, new.marge_bp);
  end if;
  new.montant_cents := round(new.quantite * new.prix_unitaire_cents * (10000 - new.rabais_bp) / 10000.0)::bigint;
  new.plafond_bp := case
    when new.type_ligne in ('kit','installation') then 0     -- Simon ou Mike décide
    when new.type_ligne = 'produit' then app.plafond_rabais_bp(new.produit_id, v_vendeur)
    else app.plafond_rabais_bp(null, v_vendeur) end;
  new.approbation_requise := new.rabais_bp > new.plafond_bp;
  return new;
end $$;
create or replace function public.hvac_dupliquer_devis(p_devis uuid) returns uuid
language plpgsql security invoker set search_path = public as $$
declare d public.devis%rowtype; v_id uuid;
begin
  select * into d from public.devis where id = p_devis;
  if not found then raise exception 'Devis introuvable' using errcode = 'P0002'; end if;
  insert into public.devis (division, succursale_code, client_id, site_id, lead_id, inspection_id, vendeur_id,
                            mode_paiement, depot_bp, notes_client, notes_internes)
  values (d.division, d.succursale_code, d.client_id, d.site_id, d.lead_id, d.inspection_id,
          coalesce(app.employe_id(), d.vendeur_id), d.mode_paiement, d.depot_bp, d.notes_client,
          concat_ws(E'\n', d.notes_internes, 'Renouvellement du devis ' || d.numero))
  returning id into v_id;
  insert into public.devis_lignes (devis_id, position, type_ligne, produit_id, kit_id, type_travail_id, sous_traitant_id,
                                   cout_cents, source_cout, reference_soumission, description, quantite,
                                   prix_unitaire_cents, rabais_bp, taxable)
  select v_id, position, type_ligne, produit_id, kit_id, type_travail_id, sous_traitant_id,
         case when source_cout = 'soumission' then cout_cents end, source_cout, reference_soumission,
         description, quantite, prix_unitaire_cents, rabais_bp, taxable
    from public.devis_lignes where devis_id = p_devis order by position;
  return v_id;
end $$;
alter table public.types_travaux enable row level security;
alter table public.tarifs_sous_traitants enable row level security;
revoke all on public.types_travaux, public.tarifs_sous_traitants from anon;
create policy lecture on public.types_travaux for select to authenticated using (app.employe_id() is not null);
create policy ajout_admin on public.types_travaux for insert to authenticated with check (app.est_admin());
create policy maj_admin on public.types_travaux for update to authenticated using (app.est_admin()) with check (app.est_admin());
create policy lecture on public.tarifs_sous_traitants for select to authenticated
  using (app.voit_tout() or app.est_commercial());
create policy ajout_admin on public.tarifs_sous_traitants for insert to authenticated with check (app.est_admin());

-- ===== 20261023000400_installation_regles.sql =====
update public.parametres
   set valeur = '2500',
       description = 'Marge sur le prix de vente de l''installation, en points de base (2500 = 25 %). Fixée par Simon et Mike.'
 where cle = 'marge_installation_bp' and valeur = '3000'::jsonb;
create or replace function app.marge_installation_bp() returns integer
language sql stable as $$
  select coalesce((select (valeur #>> '{}')::int from public.parametres where cle = 'marge_installation_bp'), 2500)
$$;
alter table public.devis_lignes drop constraint devis_lignes_installation_chk;
alter table public.devis_lignes add constraint devis_lignes_installation_chk check (
  type_ligne <> 'installation'
  or (type_travail_id is not null and sous_traitant_id is not null and produit_id is null and kit_id is null));

-- ===== 20261023000500_code_projet.sql =====
insert into public.formats_numerotation (cle, modele, prefixe, portee, description) values
  ('code_projet', '{prefixe}-{seq:3}', '', 'globale', 'Code projet Belleflamme : compteur par préfixe [SUCC][DIV]-[PRÉ]-[NOM].')
on conflict (cle) do update set modele = excluded.modele, description = excluded.description;
create or replace function app.code3(p_texte text) returns text
language sql immutable as $$
  select rpad(left(regexp_replace(upper(translate(
           replace(replace(replace(replace(coalesce(p_texte, ''), 'œ', 'oe'), 'Œ', 'OE'), 'æ', 'ae'), 'Æ', 'AE'),
           'àâäáãåçéèêëíìîïñóòôöõúùûüýÿÀÂÄÁÃÅÇÉÈÊËÍÌÎÏÑÓÒÔÖÕÚÙÛÜÝŸ',
           'aaaaaaceeeeiiiinooooouuuuyyAAAAAACEEEEIIIINOOOOOUUUUYY')), '[^A-Z]', '', 'g'), 3), 3, 'X')
$$;
create or replace function app.prefixe_code_projet(p_succursale text, p_division text, p_client uuid) returns text
language sql stable security definer set search_path = public as $$
  select p_succursale || d.lettre || '-' || app.code3(coalesce(nullif(c.prenom, ''), c.entreprise, c.nom)) || '-' || app.code3(c.nom)
    from public.clients c, public.divisions d
   where c.id = p_client and d.nom = p_division
$$;
create or replace function app.prochain_code_projet(p_succursale text, p_division text, p_client uuid) returns text
language plpgsql security definer set search_path = public as $$
declare v_prefixe text := app.prefixe_code_projet(p_succursale, p_division, p_client); v_n bigint;
begin
  if v_prefixe is null then raise exception 'Code projet : client ou division introuvable'; end if;
  insert into public.compteurs(cle, periode) values ('code_projet', v_prefixe) on conflict do nothing;
  update public.compteurs set prochain = prochain + 1, updated_at = now()
   where cle = 'code_projet' and periode = v_prefixe
  returning prochain - 1 into v_n;
  if v_n > 999 then raise exception 'Code projet : plus de 999 devis pour %', v_prefixe; end if;
  return v_prefixe || '-' || lpad(v_n::text, 3, '0');
end $$;
revoke all on function app.prochain_code_projet(text, text, uuid) from public, authenticated;
alter table public.devis add column code_projet text unique;
create or replace function app.devis_numero() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    new.numero := app.prochain_numero('devis', new.succursale_code, null, new.date_devis);
    new.code_projet := app.prochain_code_projet(new.succursale_code, new.division, new.client_id);
    new.sous_total_cents := 0; new.rabais_cents := 0; new.tps_cents := 0;
    new.tvq_cents := 0; new.total_cents := 0; new.depot_cents := 0;
    return new;
  end if;
  if new.numero is distinct from old.numero or new.code_projet is distinct from old.code_projet then
    raise exception 'Le numéro et le code projet d''un devis ne se modifient pas' using errcode = '42501';
  end if;
  if pg_trigger_depth() = 1 then
    new.sous_total_cents := old.sous_total_cents; new.rabais_cents := old.rabais_cents;
    new.tps_cents := old.tps_cents; new.tvq_cents := old.tvq_cents;
    new.total_cents := old.total_cents; new.depot_cents := old.depot_cents;
    if new.depot_bp is distinct from old.depot_bp or new.client_id is distinct from old.client_id
       or new.date_devis is distinct from old.date_devis then
      if old.statut <> 'brouillon' then
        raise exception 'Devis non modifiable (statut %)', old.statut using errcode = '42501';
      end if;
    end if;
    if new.client_id is distinct from old.client_id then
      raise exception 'Le client d''un devis ne se change pas (le code projet en dépend) : créer un nouveau devis'
        using errcode = '42501';
    end if;
  end if;
  return new;
end $$;
create or replace function app.projet_avant() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    if new.devis_id is not null then
      select code_projet into new.code_projet from public.devis where id = new.devis_id;
    end if;
    if new.code_projet is null then
      new.code_projet := app.prochain_code_projet(new.succursale_code, new.division, new.client_id);
    end if;
  elsif new.code_projet is distinct from old.code_projet then
    raise exception 'Le code projet ne se modifie pas' using errcode = '42501';
  end if;
  new.solde_du_le := new.installation_prevue_le
    - coalesce((select (valeur #>> '{}')::int from public.parametres where cle = 'delai_solde_heures'), 72)
      * interval '1 hour';
  return new;
end $$;
drop view public.devis_v;
create view public.devis_v with (security_invoker = true) as
  select d.*,
         case when d.statut = 'envoye' and d.valide_jusqu < current_date then 'expire' else d.statut end as statut_effectif,
         c.prenom as client_prenom, c.nom as client_nom, c.entreprise as client_entreprise,
         e.prenom || ' ' || e.nom as vendeur_nom,
         (select count(*) from public.approbations_rabais a where a.devis_id = d.id and a.statut = 'en_attente') as approbations_en_attente,
         exists (select 1 from public.devis_lignes l where l.devis_id = d.id and l.approbation_requise
                   and not exists (select 1 from public.approbations_rabais a where a.devis_ligne_id = l.id
                                    and a.statut = 'approuvee' and a.rabais_bp >= l.rabais_bp)) as bloque_par_rabais
    from public.devis d
    join public.clients c on c.id = d.client_id
    left join public.employes e on e.id = d.vendeur_id;
grant select on public.devis_v to authenticated;
revoke all on public.devis_v from anon;

-- ===== 20261023000600_extension_devis.sql =====
insert into public.formats_numerotation (cle, modele, prefixe, portee, description) values
  ('extension_devis', '{prefixe}-E{seq:2}', '', 'globale', 'Extension d''un devis renouvelé : compteur par code d''origine.')
on conflict (cle) do nothing;
alter table public.devis add column devis_origine_id uuid references public.devis(id);
create or replace function app.prochain_code_extension(p_origine uuid) returns text
language plpgsql security definer set search_path = public as $$
declare v_code text; v_n bigint;
begin
  select code_projet into v_code from public.devis where id = p_origine;
  if v_code is null then raise exception 'Devis d''origine introuvable' using errcode = 'P0002'; end if;
  insert into public.compteurs(cle, periode) values ('extension_devis', v_code) on conflict do nothing;
  update public.compteurs set prochain = prochain + 1, updated_at = now()
   where cle = 'extension_devis' and periode = v_code
  returning prochain - 1 into v_n;
  if v_n > 99 then raise exception 'Plus de 99 extensions pour %', v_code; end if;
  return v_code || '-E' || lpad(v_n::text, 2, '0');
end $$;
revoke all on function app.prochain_code_extension(uuid) from public, authenticated;
create or replace function app.devis_numero() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    new.numero := app.prochain_numero('devis', new.succursale_code, null, new.date_devis);
    if new.devis_origine_id is not null then
      select coalesce(devis_origine_id, id) into new.devis_origine_id from public.devis where id = new.devis_origine_id;
      new.code_projet := app.prochain_code_extension(new.devis_origine_id);
    else
      new.code_projet := app.prochain_code_projet(new.succursale_code, new.division, new.client_id);
    end if;
    new.sous_total_cents := 0; new.rabais_cents := 0; new.tps_cents := 0;
    new.tvq_cents := 0; new.total_cents := 0; new.depot_cents := 0;
    return new;
  end if;
  if new.numero is distinct from old.numero or new.code_projet is distinct from old.code_projet
     or new.devis_origine_id is distinct from old.devis_origine_id then
    raise exception 'Le numéro, le code projet et l''origine d''un devis ne se modifient pas' using errcode = '42501';
  end if;
  if pg_trigger_depth() = 1 then
    new.sous_total_cents := old.sous_total_cents; new.rabais_cents := old.rabais_cents;
    new.tps_cents := old.tps_cents; new.tvq_cents := old.tvq_cents;
    new.total_cents := old.total_cents; new.depot_cents := old.depot_cents;
    if new.depot_bp is distinct from old.depot_bp or new.date_devis is distinct from old.date_devis then
      if old.statut <> 'brouillon' then
        raise exception 'Devis non modifiable (statut %)', old.statut using errcode = '42501';
      end if;
    end if;
    if new.client_id is distinct from old.client_id then
      raise exception 'Le client d''un devis ne se change pas (le code projet en dépend) : créer un nouveau devis'
        using errcode = '42501';
    end if;
  end if;
  return new;
end $$;
create or replace function public.hvac_dupliquer_devis(p_devis uuid) returns uuid
language plpgsql security invoker set search_path = public as $$
declare d public.devis%rowtype; v_id uuid;
begin
  select * into d from public.devis where id = p_devis;
  if not found then raise exception 'Devis introuvable' using errcode = 'P0002'; end if;
  insert into public.devis (division, succursale_code, client_id, site_id, lead_id, inspection_id, vendeur_id,
                            mode_paiement, depot_bp, notes_client, notes_internes, devis_origine_id)
  values (d.division, d.succursale_code, d.client_id, d.site_id, d.lead_id, d.inspection_id,
          coalesce(app.employe_id(), d.vendeur_id), d.mode_paiement, d.depot_bp, d.notes_client,
          concat_ws(E'\n', d.notes_internes, 'Renouvellement du devis ' || d.numero || ' (' || d.code_projet || ')'),
          d.id)
  returning id into v_id;
  insert into public.devis_lignes (devis_id, position, type_ligne, produit_id, kit_id, type_travail_id, sous_traitant_id,
                                   cout_cents, source_cout, reference_soumission, description, quantite,
                                   prix_unitaire_cents, rabais_bp, taxable)
  select v_id, position, type_ligne, produit_id, kit_id, type_travail_id, sous_traitant_id,
         case when source_cout = 'soumission' then cout_cents end, source_cout, reference_soumission,
         description, quantite, prix_unitaire_cents, rabais_bp, taxable
    from public.devis_lignes where devis_id = p_devis order by position;
  return v_id;
end $$;
drop view public.devis_v;
create view public.devis_v with (security_invoker = true) as
  select d.*,
         case when d.statut = 'envoye' and d.valide_jusqu < current_date then 'expire' else d.statut end as statut_effectif,
         c.prenom as client_prenom, c.nom as client_nom, c.entreprise as client_entreprise,
         e.prenom || ' ' || e.nom as vendeur_nom,
         (select count(*) from public.approbations_rabais a where a.devis_id = d.id and a.statut = 'en_attente') as approbations_en_attente,
         exists (select 1 from public.devis_lignes l where l.devis_id = d.id and l.approbation_requise
                   and not exists (select 1 from public.approbations_rabais a where a.devis_ligne_id = l.id
                                    and a.statut = 'approuvee' and a.rabais_bp >= l.rabais_bp)) as bloque_par_rabais
    from public.devis d
    join public.clients c on c.id = d.client_id
    left join public.employes e on e.id = d.vendeur_id;
grant select on public.devis_v to authenticated;
revoke all on public.devis_v from anon;
