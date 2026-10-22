-- Phase 1 | Catalogue HVAC : marques, produits, kits.
-- Les colonnes des boards Catalogue (9677840877) et Kits de Mike sont à confirmer.

create table public.marques (
  id                       uuid primary key default gen_random_uuid(),
  nom                      text not null unique,
  fournisseur_id           uuid references public.fournisseurs(id),
  escompte_fournisseur_bp  integer not null default 0 check (escompte_fournisseur_bp between 0 and 10000),
  -- Exception au plafond de rabais (ADR-010). Null = règle générale (escompte - 35 points).
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
  -- Escompte propre au produit, sinon celui de la marque
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

-- Kits (ex. kit thermopompe : unité ext. + int. + support + conduits + main-d'oeuvre).
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
