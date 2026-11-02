-- Phase 1 | Ventes : taxes, devis, lignes, plafonds et approbations de rabais.

-- ---------------------------------------------------------------------------
-- Taxes (TPS 5 %, TVQ 9,975 %), calcul en cents, arrondi au cent le plus proche
-- (demi-cent arrondi en s'éloignant de zéro). TVQ calculée sur le montant avant TPS.
-- ---------------------------------------------------------------------------

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

-- ---------------------------------------------------------------------------
-- Délégations de rabais (ADR-010) : Mike ou Simon accorde un plafond à un employé.
-- ---------------------------------------------------------------------------

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
    -- Seule la révocation est permise : le plafond accordé ne se modifie pas, on en crée un nouveau.
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

-- Plafond de rabais applicable à un produit pour un employé, en bp.
-- Règle : escompte fournisseur - 35 points (ex. 40 % -> 5 %), ou exception de la marque,
-- et au moins le plafond délégué à l'employé.
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

-- ---------------------------------------------------------------------------
-- Devis
-- ---------------------------------------------------------------------------

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

-- Numéro de devis attribué à la création, jamais modifié.
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
  -- Les totaux sont calculés par app.recalculer_devis seulement (trigger imbriqué).
  -- Une mise à jour directe ne peut pas les modifier.
  if pg_trigger_depth() = 1 then
    new.sous_total_cents := old.sous_total_cents; new.rabais_cents := old.rabais_cents;
    new.tps_cents := old.tps_cents; new.tvq_cents := old.tvq_cents;
    new.total_cents := old.total_cents; new.depot_cents := old.depot_cents;
    if new.depot_bp is distinct from old.depot_bp or new.client_id is distinct from old.client_id
       or new.date_devis is distinct from old.date_devis then
      if old.statut <> 'brouillon' then
        raise exception 'Devis non modifiable (statut %)', old.statut using errcode = '42501';
      end if;
      -- le recalcul se fait après la mise à jour (trg_devis_apres_maj)
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

-- Calcul de la ligne : montant après rabais et plafond applicable.
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
  -- Kit ou ligne libre : seule la délégation de l'employé s'applique (à confirmer).
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

-- Envoi ou acceptation bloqué tant qu'un rabais hors plafond n'est pas approuvé.
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
