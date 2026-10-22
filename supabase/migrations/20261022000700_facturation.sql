-- Phase 1 | Facturation : factures, lignes, paiements, financement (Financeit), subventions.
-- Méthode de facturation de Mike à confirmer (ADR-009). Modèle actuel :
-- dépôt 40 % à l'acceptation, solde 60 % dû 72 h avant l'installation.

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

-- Subventions : LogisVert aujourd'hui, autres programmes (fédéral 2027) plus tard.
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

-- ---------------------------------------------------------------------------
-- Calculs et règles
-- ---------------------------------------------------------------------------

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

-- Pièces manquantes pour LogisVert, d'après le guide client (docs/reference/logisvert-guide-client.md).
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

  -- Totaux et montant payé : calculés par la base seulement (triggers imbriqués).
  if pg_trigger_depth() = 1 then
    new.sous_total_cents := old.sous_total_cents; new.tps_cents := old.tps_cents;
    new.tvq_cents := old.tvq_cents; new.total_cents := old.total_cents;
    new.montant_paye_cents := old.montant_paye_cents;
  end if;

  if new.numero is distinct from old.numero and old.numero is not null then
    raise exception 'Le numéro de facture ne se modifie pas' using errcode = '42501';
  end if;

  -- Émission : numéro, date, conformité LogisVert
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
    -- Après émission, seuls le statut de paiement et le montant payé évoluent.
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
-- Un paiement ne se modifie ni ne se supprime : on saisit un remboursement (montant négatif).
create trigger trg_paiement_immuable before update or delete on public.paiements
  for each row execute function app.interdit();
create trigger trg_audit after insert on public.paiements
  for each row execute function app.audit();
