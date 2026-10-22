-- Rabais global sur le devis (Simon, 22 oct. 2026) : en dollars OU en pourcentage du
-- sous-total, TOUJOURS approuvé par Simon ou Mike. Remplace la ligne négative libre
-- « RABAIS SUPPLÉMENTAIRE » de l'app de Mike (ADR-032, ADR-039).

alter table public.devis_lignes drop constraint devis_lignes_prix_unitaire_cents_check;
alter table public.devis_lignes drop constraint devis_lignes_type_ligne_check;
alter table public.devis_lignes
  add constraint devis_lignes_type_ligne_check check (type_ligne in ('produit','kit','installation','libre','rabais')),
  add column rabais_mode text check (rabais_mode in ('montant','pourcentage')),
  add column rabais_valeur bigint check (rabais_valeur > 0),   -- cents (montant) ou bp (pourcentage)
  add constraint devis_lignes_prix_chk check (prix_unitaire_cents >= 0 or type_ligne = 'rabais'),
  add constraint devis_lignes_rabais_chk check (
    (type_ligne = 'rabais') = (rabais_mode is not null and rabais_valeur is not null)
    and (rabais_mode is distinct from 'pourcentage' or rabais_valeur <= 10000));

-- L'approbation garde le mode et la valeur approuvés : elle ne couvre que ce montant ou moins.
alter table public.approbations_rabais
  add column rabais_mode text,
  add column rabais_valeur bigint;

-- Une ligne est couverte par une approbation si le rabais (ligne) et la valeur (rabais global)
-- ne dépassent pas ce qui a été approuvé, dans le même mode.
create or replace function app.ligne_approuvee(p_ligne uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.devis_lignes l join public.approbations_rabais a on a.devis_ligne_id = l.id
     where l.id = p_ligne and a.statut = 'approuvee'
       and a.rabais_bp >= l.rabais_bp
       and a.rabais_mode is not distinct from l.rabais_mode
       and coalesce(a.rabais_valeur, 0) >= coalesce(l.rabais_valeur, 0))
$$;

create or replace function app.devis_ligne_calcul() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_vendeur uuid; v_statut text; v_date date; v_base bigint;
begin
  select vendeur_id, statut, date_devis into v_vendeur, v_statut, v_date from public.devis
   where id = coalesce(new.devis_id, old.devis_id);
  if v_statut <> 'brouillon' then
    raise exception 'Devis non modifiable (statut %)', v_statut using errcode = '42501';
  end if;
  if tg_op = 'DELETE' then return old; end if;

  new.type_ligne := case when new.type_ligne in ('installation','rabais') then new.type_ligne
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
  elsif new.type_ligne = 'rabais' then
    -- Montant négatif calculé par la base : jamais saisi.
    new.quantite := 1; new.rabais_bp := 0; new.taxable := true;
    if new.rabais_mode = 'montant' then
      new.prix_unitaire_cents := -new.rabais_valeur;
    else
      select coalesce(sum(montant_cents), 0) into v_base from public.devis_lignes
       where devis_id = new.devis_id and type_ligne <> 'rabais' and id <> new.id;
      new.prix_unitaire_cents := -round(v_base * new.rabais_valeur / 10000.0)::bigint;
    end if;
  end if;

  new.montant_cents := round(new.quantite * new.prix_unitaire_cents * (10000 - new.rabais_bp) / 10000.0)::bigint;
  new.plafond_bp := case
    when new.type_ligne in ('kit','installation','rabais') then 0     -- Simon ou Mike décide
    when new.type_ligne = 'produit' then app.plafond_rabais_bp(new.produit_id, v_vendeur)
    else app.plafond_rabais_bp(null, v_vendeur) end;
  new.approbation_requise := new.type_ligne = 'rabais' or new.rabais_bp > new.plafond_bp;
  return new;
end $$;

-- Recalcul : un rabais en % suit le sous-total ; le total ne peut pas devenir négatif.
create or replace function app.recalculer_devis(p_devis uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  d public.devis%rowtype; c public.clients%rowtype;
  v_base bigint; v_brut bigint; v_net bigint; v_taxable bigint; v_tps bigint; v_tvq bigint;
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
  select t.tps, t.tvq into v_tps, v_tvq
    from app.taxes(greatest(v_taxable, 0), d.date_devis, c.exemption_tps, c.exemption_tvq) t;
  update public.devis set
    sous_total_cents = v_net,
    rabais_cents     = v_brut - v_net,
    tps_cents        = v_tps,
    tvq_cents        = v_tvq,
    total_cents      = v_net + v_tps + v_tvq,
    depot_cents      = round((v_net + v_tps + v_tvq) * depot_bp / 10000.0)::bigint
  where id = p_devis;
end $$;

-- La demande recopie aussi le mode et la valeur du rabais global.
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
    new.rabais_mode := l.rabais_mode; new.rabais_valeur := l.rabais_valeur;
    return new;
  end if;
  if (new.rabais_bp, new.plafond_bp, new.devis_ligne_id, new.demande_par, new.rabais_mode, new.rabais_valeur)
     is distinct from (old.rabais_bp, old.plafond_bp, old.devis_ligne_id, old.demande_par, old.rabais_mode, old.rabais_valeur) then
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

create or replace function app.devis_statut_garde() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_jours int := coalesce((select (valeur #>> '{}')::int from public.parametres where cle = 'validite_devis_jours'), 30);
begin
  if new.statut = old.statut then return new; end if;
  if new.statut in ('envoye','accepte') then
    if exists (select 1 from public.devis_lignes l
                where l.devis_id = new.id and l.approbation_requise and not app.ligne_approuvee(l.id)) then
      raise exception 'Devis % : rabais en attente d''approbation de Simon ou Mike', new.numero using errcode = 'P0001';
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

-- Le renouvellement recopie aussi le rabais global (à réapprouver).
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
                                   prix_unitaire_cents, rabais_bp, taxable, rabais_mode, rabais_valeur)
  select v_id, position, type_ligne, produit_id, kit_id, type_travail_id, sous_traitant_id,
         case when source_cout = 'soumission' then cout_cents end, source_cout, reference_soumission,
         description, quantite, prix_unitaire_cents, rabais_bp, taxable, rabais_mode, rabais_valeur
    from public.devis_lignes where devis_id = p_devis
   order by (type_ligne = 'rabais'), position;   -- le rabais en % se calcule après les autres lignes
  return v_id;
end $$;

-- devis_v : « bloqué » selon la nouvelle règle d'approbation
drop view public.devis_v;
create view public.devis_v with (security_invoker = true) as
  select d.*,
         case when d.statut = 'envoye' and d.valide_jusqu < current_date then 'expire' else d.statut end as statut_effectif,
         c.prenom as client_prenom, c.nom as client_nom, c.entreprise as client_entreprise,
         e.prenom || ' ' || e.nom as vendeur_nom,
         (select count(*) from public.approbations_rabais a where a.devis_id = d.id and a.statut = 'en_attente') as approbations_en_attente,
         exists (select 1 from public.devis_lignes l
                  where l.devis_id = d.id and l.approbation_requise and not app.ligne_approuvee(l.id)) as bloque_par_rabais
    from public.devis d
    join public.clients c on c.id = d.client_id
    left join public.employes e on e.id = d.vendeur_id;
grant select on public.devis_v to authenticated;
revoke all on public.devis_v from anon;
