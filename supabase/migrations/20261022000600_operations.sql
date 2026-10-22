-- Phase 1 | Opérations : projets (Macro), équipements installés, bons de travail,
-- appels de service (ASV), contrats d'entretien.

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
  -- Solde de 60 % dû 72 h avant l'installation (ADR-009)
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

-- Équipements installés : numéros de série pour LogisVert.
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

-- Bons de travail. id généré côté client possible (mode hors ligne, ADR-011).
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

-- Certification expirée : bloquant seulement si le paramètre est activé (ADR-015).
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
