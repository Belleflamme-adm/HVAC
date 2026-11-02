-- Taxes : vente en Ontario (TVH 13 %) et client autochtone exonéré, comme dans l'app de Mike (ADR-054).
-- Deux cases sur le devis :
--   « Vente Ontario | TVH (HST) 13 % au lieu de TPS/TVQ »  -> regime_taxes = 'ON'
--   « Client autochtone | exonéré (art. 87, Loi sur les Indiens) » -> autochtone = true
-- La facture reprend les cases de son devis. Le calcul reste fait par la base, en cents.
-- À valider par le comptable : traitement de la TVH pour un client autochtone, pièces justificatives.

alter table public.taux_taxes drop constraint taux_taxes_code_check;
alter table public.taux_taxes add constraint taux_taxes_code_check check (code in ('TPS','TVQ','TVH_ON'));
insert into public.taux_taxes (code, taux_pcm, en_vigueur_du) values ('TVH_ON', 13000, '2010-07-01')
on conflict do nothing;

alter table public.devis
  add column regime_taxes text not null default 'QC' check (regime_taxes in ('QC','ON')),
  add column autochtone boolean not null default false,
  add column autochtone_no_registre text,
  add column tvh_cents bigint not null default 0;
alter table public.factures
  add column regime_taxes text not null default 'QC' check (regime_taxes in ('QC','ON')),
  add column autochtone boolean not null default false,
  add column autochtone_no_registre text,
  add column tvh_cents bigint not null default 0;

-- Calcul : autochtone -> aucune taxe ; Ontario -> TVH seule ; Québec -> TPS + TVQ (exemptions du client).
create or replace function app.taxes_regime(
  p_montant bigint, p_date date, p_regime text, p_exempt_tps boolean, p_exempt_tvq boolean, p_autochtone boolean,
  out tps bigint, out tvq bigint, out tvh bigint
) language plpgsql stable as $$
begin
  tps := 0; tvq := 0; tvh := 0;
  if p_autochtone then return; end if;
  if p_regime = 'ON' then
    -- Un client exempté des deux taxes (ex. organisme) l'est aussi de la TVH
    if not (p_exempt_tps and p_exempt_tvq) then tvh := app.arrondi_taxe(p_montant, app.taux_pcm('TVH_ON', p_date)); end if;
    return;
  end if;
  select t.tps, t.tvq into tps, tvq from app.taxes(p_montant, p_date, p_exempt_tps, p_exempt_tvq) t;
end $$;

-- Recalcul du devis (reprend ADR-042/043, ajoute la TVH)
create or replace function app.recalculer_devis(p_devis uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  d public.devis%rowtype; c public.clients%rowtype;
  v_base bigint; v_brut bigint; v_net bigint; v_taxable bigint; v_tps bigint; v_tvq bigint; v_tvh bigint;
begin
  select * into d from public.devis where id = p_devis;
  select * into c from public.clients where id = d.client_id;
  if d.statut = 'brouillon' then
    select coalesce(sum(montant_cents), 0) into v_base from public.devis_lignes
     where devis_id = p_devis and type_ligne <> 'rabais';
    update public.devis_lignes
       set prix_unitaire_cents = -round(v_base * rabais_valeur / 10000.0)::bigint
     where devis_id = p_devis and type_ligne = 'rabais' and rabais_mode = 'pourcentage'
       and prix_unitaire_cents <> -round(v_base * rabais_valeur / 10000.0)::bigint;
  end if;
  select coalesce(sum(round(quantite * prix_unitaire_cents)::bigint) filter (where type_ligne <> 'rabais'), 0),
         coalesce(sum(montant_cents), 0),
         coalesce(sum(montant_cents) filter (where taxable), 0)
    into v_brut, v_net, v_taxable
    from public.devis_lignes where devis_id = p_devis;
  if v_net < 0 then
    raise exception 'Le rabais global dépasse le sous-total du devis' using errcode = 'P0001';
  end if;
  select t.tps, t.tvq, t.tvh into v_tps, v_tvq, v_tvh
    from app.taxes_regime(greatest(v_taxable, 0), d.date_devis, d.regime_taxes,
                          c.exemption_tps, c.exemption_tvq, d.autochtone) t;
  update public.devis set
    sous_total_cents = v_net,
    rabais_cents     = v_brut - v_net,
    tps_cents        = v_tps,
    tvq_cents        = v_tvq,
    tvh_cents        = v_tvh,
    total_cents      = v_net + v_tps + v_tvq + v_tvh,
    depot_cents      = round((v_net + v_tps + v_tvq + v_tvh) * depot_bp / 10000.0)::bigint
  where id = p_devis;
end $$;

create or replace function app.recalculer_facture(p_facture uuid) returns void
language plpgsql security definer set search_path = public as $$
declare f public.factures%rowtype; c public.clients%rowtype;
        v_net bigint; v_taxable bigint; v_tps bigint; v_tvq bigint; v_tvh bigint;
begin
  select * into f from public.factures where id = p_facture;
  select * into c from public.clients where id = f.client_id;
  select coalesce(sum(montant_cents), 0), coalesce(sum(montant_cents) filter (where taxable), 0)
    into v_net, v_taxable from public.facture_lignes where facture_id = p_facture;
  select t.tps, t.tvq, t.tvh into v_tps, v_tvq, v_tvh
    from app.taxes_regime(v_taxable, coalesce(f.emise_le, now())::date, f.regime_taxes,
                          c.exemption_tps, c.exemption_tvq, f.autochtone) t;
  update public.factures set sous_total_cents = v_net, tps_cents = v_tps, tvq_cents = v_tvq, tvh_cents = v_tvh,
         total_cents = v_net + v_tps + v_tvq + v_tvh
   where id = p_facture;
end $$;

-- ---------------------------------------------------------------------------
-- Devis : valeurs par défaut, verrou après le brouillon, recalcul quand une case change
-- ---------------------------------------------------------------------------
create or replace function app.devis_regime_avant() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    -- Cases précochées d'après le chantier et le client ; l'employé peut les changer en brouillon.
    if new.regime_taxes = 'QC' and exists (select 1 from public.sites s where s.id = new.site_id and s.province = 'ON') then
      new.regime_taxes := 'ON';
    end if;
    if not new.autochtone and exists (select 1 from public.clients c where c.id = new.client_id and c.exemption_taxes = 'autochtone') then
      new.autochtone := true;
      new.autochtone_no_registre := coalesce(new.autochtone_no_registre,
        (select exemption_numero from public.clients where id = new.client_id));
    end if;
    new.tvh_cents := 0;
    return new;
  end if;
  if pg_trigger_depth() = 1 then new.tvh_cents := old.tvh_cents; end if;
  if (new.regime_taxes, new.autochtone, new.autochtone_no_registre)
     is distinct from (old.regime_taxes, old.autochtone, old.autochtone_no_registre)
     and old.statut <> 'brouillon' then
    raise exception 'Devis non modifiable (statut %) : les taxes sont figées', old.statut using errcode = '42501';
  end if;
  -- Envoi : la case Ontario doit correspondre à la province du chantier
  if new.statut = 'envoye' and old.statut = 'brouillon' then
    if exists (select 1 from public.sites s where s.id = new.site_id and s.province <> new.regime_taxes
                                              and s.province in ('QC','ON')) then
      raise exception 'Devis % : le chantier est en % mais les taxes sont celles de %. Corriger la case « Vente Ontario ».',
        new.numero, (select province from public.sites where id = new.site_id), new.regime_taxes using errcode = 'P0001';
    end if;
  end if;
  return new;
end $$;
create trigger trg_devis_regime_avant before insert or update on public.devis
  for each row execute function app.devis_regime_avant();

create or replace function app.devis_regime_apres() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform app.recalculer_devis(new.id);
  return null;
end $$;
create trigger trg_devis_regime_apres after update of regime_taxes, autochtone on public.devis
  for each row when ((new.regime_taxes, new.autochtone) is distinct from (old.regime_taxes, old.autochtone))
  execute function app.devis_regime_apres();

-- ---------------------------------------------------------------------------
-- Facture : reprend les cases du devis, figées à l'émission
-- ---------------------------------------------------------------------------
create or replace function app.facture_regime_avant() returns trigger
language plpgsql security definer set search_path = public as $$
declare d public.devis%rowtype;
begin
  if tg_op = 'INSERT' then
    select * into d from public.devis
     where id = coalesce(new.devis_id, (select devis_id from public.projets where id = new.projet_id));
    if found then
      new.regime_taxes := d.regime_taxes; new.autochtone := d.autochtone;
      new.autochtone_no_registre := d.autochtone_no_registre;
    end if;
    new.tvh_cents := 0;
    return new;
  end if;
  if pg_trigger_depth() = 1 then new.tvh_cents := old.tvh_cents; end if;
  if (new.regime_taxes, new.autochtone, new.autochtone_no_registre, new.tvh_cents)
     is distinct from (old.regime_taxes, old.autochtone, old.autochtone_no_registre, old.tvh_cents)
     and old.statut <> 'brouillon' then
    raise exception 'Facture émise : non modifiable. Faire une note de crédit.' using errcode = '42501';
  end if;
  return new;
end $$;
create trigger trg_facture_regime_avant before insert or update on public.factures
  for each row execute function app.facture_regime_avant();

create or replace function app.facture_regime_apres() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform app.recalculer_facture(new.id);
  return null;
end $$;
create trigger trg_facture_regime_apres after update of regime_taxes, autochtone on public.factures
  for each row when ((new.regime_taxes, new.autochtone) is distinct from (old.regime_taxes, old.autochtone))
  execute function app.facture_regime_apres();
