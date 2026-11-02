-- Phase 1 | CRM : clients, lieux d'installation, leads, inspections, documents.

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
  -- LogisVert : seul le propriétaire est admissible, nom identique à la preuve de propriété
  est_proprietaire        boolean,
  nom_preuve_propriete    text,
  -- Numéros Hydro-Québec : renseignements personnels, stockés seulement avec consentement
  hq_numero_client        text check (hq_numero_client is null or hq_numero_client ~ '^1\d{8}$'),
  hq_numero_compteur      text check (hq_numero_compteur is null or length(hq_numero_compteur) between 11 and 12),
  consentement_hq_le      timestamptz,
  -- Exemption de taxes (ADR-016), règles exactes à valider par un professionnel
  exemption_taxes         text not null default 'aucune'
                          check (exemption_taxes in ('aucune','autochtone','revendeur','organisme','autre')),
  exemption_tps           boolean not null default false,
  exemption_tvq           boolean not null default false,
  exemption_numero        text,
  exemption_document_id   uuid,
  -- Loi 25 : consentement aux communications
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

-- Lieux d'installation : un client peut avoir plusieurs adresses (chalet, immeuble).
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

-- Inspection pré-installation, AVANT le devis (ADR-007).
-- Les colonnes du board Monday (1175 items) sont inconnues : contenu du formulaire en jsonb.
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

-- Fichiers (Supabase Storage). Rattachement polymorphe à une entité.
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
