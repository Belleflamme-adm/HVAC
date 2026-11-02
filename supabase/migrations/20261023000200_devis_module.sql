-- Phase 3 | Module Clients + Devis : règles confirmées par Simon le 22 oct. 2026.
--   * rabais sur un kit : aucun plafond automatique ni délégué, décidé par Simon ou Mike (approbation)
--   * taxes sur le montant global (déjà le cas, ADR-018)
--   * validité : 30 jours à partir de l'envoi, puis le devis expire

insert into public.parametres (cle, valeur, description) values
  ('validite_devis_jours', '30', 'Un devis envoyé est valide X jours, puis il expire.')
on conflict (cle) do nothing;

-- Plafond d'une ligne : kit = 0 (toujours approuvé par Simon ou Mike).
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
  -- Prix imposé par le catalogue : un vendeur ne peut pas baisser le prix pour contourner le plafond.
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

-- Validité recalculée à l'envoi ; acceptation refusée après expiration.
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

-- Demande d'approbation : rabais, plafond et devis viennent de la ligne, jamais du client.
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

-- Statut effectif : un devis envoyé dont la validité est passée est « expire »,
-- sans tâche planifiée (calcul à la lecture). La vue respecte la RLS de l'appelant.
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

-- Prix d'un kit : son prix fixe, sinon la somme de ses composantes.
create or replace function public.hvac_prix_kit(p_kit uuid) returns bigint
language sql stable security invoker set search_path = public as $$
  select coalesce(k.prix_cents,
                  (select coalesce(sum(round(ki.quantite * p.prix_cents)::bigint), 0)
                     from public.kit_items ki join public.produits p on p.id = ki.produit_id where ki.kit_id = k.id))
    from public.kits k where k.id = p_kit
$$;

-- Renouveler un devis (expiré, refusé ou à réviser) : nouveau numéro, mêmes lignes,
-- en brouillon. Les approbations ne suivent pas : un rabais hors plafond est à réapprouver.
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
