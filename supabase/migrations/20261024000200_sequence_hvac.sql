-- Séquence HVAC confirmée par Simon (22 oct. 2026, ADR-049) :
--   lead -> visite de pré-installation (vendeur) -> devis -> acceptation -> dépôt OU Financeit
--   -> BC -> BT -> cédule de la job -> solde 72 h avant (dépôt 40 % seulement, pas Financeit)
--   -> installation -> facturation -> paiement du sous-traitant
-- Changements :
--   1. un devis ne s'envoie pas sans visite de pré-installation réalisée (paramètre)
--   2. l'acceptation crée seulement le projet (« attente_paiement ») ;
--      le BT et les BC naissent au dépôt payé ou au financement approuvé
--   3. aucun solde « 72 h avant » pour un projet financé par Financeit

insert into public.parametres (cle, valeur, description) values
  ('exiger_preinstallation', 'true', 'Un devis ne s''envoie pas sans visite de pré-installation réalisée (ADR-049).')
on conflict (cle) do nothing;

alter table public.projets drop constraint projets_statut_check;
alter table public.projets add constraint projets_statut_check check (statut in (
  'attente_paiement','a_planifier','planifie','en_cours','termine','facture','ferme','annule'));

-- 1. Envoi du devis : pré-installation réalisée requise
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
    if app.parametre_bool('exiger_preinstallation', true) and not exists (
         select 1 from public.inspections i where i.id = new.inspection_id and i.statut = 'realisee') then
      raise exception 'Devis % : visite de pré-installation réalisée requise avant l''envoi', new.numero using errcode = 'P0001';
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

-- 2a. Acceptation : projet seulement
create or replace function app.creer_projet_devis(p_devis uuid) returns uuid
language plpgsql security definer set search_path = public as $$
declare d public.devis%rowtype; v_projet uuid;
begin
  select id into v_projet from public.projets where devis_id = p_devis;
  if v_projet is not null then return v_projet; end if;
  select * into d from public.devis where id = p_devis;
  insert into public.projets (division, succursale_code, client_id, site_id, devis_id, vendeur_id, statut)
  values (d.division, d.succursale_code, d.client_id, d.site_id, d.id, d.vendeur_id, 'attente_paiement')
  returning id into v_projet;
  return v_projet;
end $$;

-- 2b. Dépôt payé ou financement approuvé : BT + BC brouillons (une seule fois par projet)
create or replace function app.creer_bt_bc(p_projet uuid) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  p public.projets%rowtype; d public.devis%rowtype; v_bt uuid; v_st uuid; v_pos int := 0; v_bc uuid;
  l record; c record;
begin
  select * into p from public.projets where id = p_projet;
  if p.devis_id is null then return null; end if;
  select id into v_bt from public.bons_travail where projet_id = p_projet and type = 'RV' order by created_at limit 1;
  if v_bt is not null then return v_bt; end if;
  select * into d from public.devis where id = p.devis_id;
  select sous_traitant_id into v_st from public.devis_lignes
   where devis_id = d.id and type_ligne = 'installation' order by position limit 1;

  insert into public.bons_travail (division, succursale_code, projet_id, assigne_fournisseur_id, statut, travaux)
  values (d.division, d.succursale_code, p_projet, v_st, 'brouillon',
          'Brouillon automatique (devis #' || d.numero || ', paiement reçu). À cédule : date dans les disponibilités du sous-traitant.')
  returning id into v_bt;

  for l in
    select dl.id as devis_ligne_id, dl.position, 'produit' as type_ligne, dl.produit_id, dl.description, dl.quantite
      from public.devis_lignes dl where dl.devis_id = d.id and dl.type_ligne = 'produit'
    union all
    select dl.id, dl.position, 'produit', ki.produit_id, pr.nom, dl.quantite * ki.quantite
      from public.devis_lignes dl join public.kit_items ki on ki.kit_id = dl.kit_id join public.produits pr on pr.id = ki.produit_id
     where dl.devis_id = d.id and dl.type_ligne = 'kit'
    union all
    select dl.id, dl.position, case when dl.type_ligne = 'installation' then 'installation' else 'service' end, null, dl.description, dl.quantite
      from public.devis_lignes dl where dl.devis_id = d.id and dl.type_ligne in ('installation','libre')
    order by 2
  loop
    v_pos := v_pos + 1;
    insert into public.bt_lignes (bon_travail_id, position, devis_ligne_id, type_ligne, produit_id, description, quantite, provenance)
    values (v_bt, v_pos, l.devis_ligne_id, l.type_ligne, l.produit_id, l.description, l.quantite,
            case when l.type_ligne <> 'produit' then null
                 when app.fournisseur_produit(l.produit_id) is not null
                      and exists (select 1 from public.produits x where x.id = l.produit_id and x.stocke)
                   then 'a_commander' else 'a_determiner' end);
  end loop;

  for c in
    select app.fournisseur_produit(bl.produit_id) as fournisseur_id from public.bt_lignes bl
     where bl.bon_travail_id = v_bt and bl.provenance = 'a_commander' group by 1
  loop
    insert into public.bons_commande (division, succursale_code, projet_id, bon_travail_id, fournisseur_id, mode_livraison, ramassage_par)
    values (d.division, d.succursale_code, p_projet, v_bt, c.fournisseur_id,
            case when v_st is not null then 'ramassage' else 'entrepot' end, v_st)
    returning id into v_bc;
    insert into public.bc_lignes (bon_commande_id, position, produit_id, bt_ligne_id, description, quantite)
    select v_bc, bl.position, bl.produit_id, bl.id, bl.description, bl.quantite
      from public.bt_lignes bl
     where bl.bon_travail_id = v_bt and bl.provenance = 'a_commander' and app.fournisseur_produit(bl.produit_id) = c.fournisseur_id;
    update public.bt_lignes bl set bc_ligne_id = x.id
      from public.bc_lignes x where x.bt_ligne_id = bl.id and x.bon_commande_id = v_bc;
  end loop;

  update public.projets set statut = 'a_planifier' where id = p_projet and statut = 'attente_paiement';
  return v_bt;
end $$;

-- Compatibilité : ancienne fonction = projet, puis BT/BC si le paiement est déjà là.
create or replace function app.creer_commande(p_devis uuid) returns uuid
language plpgsql security definer set search_path = public as $$
declare v_projet uuid := app.creer_projet_devis(p_devis);
begin
  if app.paiement_permet_planif(v_projet) then perform app.creer_bt_bc(v_projet); end if;
  return v_projet;
end $$;

create or replace function app.devis_accepte_apres() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform app.creer_commande(new.id);
  return null;
end $$;

-- Déclencheurs de paiement : dépôt payé, financement approuvé ou financé
create or replace function app.paiement_recu_apres() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.projet_id is not null and app.paiement_permet_planif(new.projet_id) then
    perform app.creer_bt_bc(new.projet_id);
    -- Financeit : aucun solde « 72 h avant »
    update public.projets set solde_du_le = solde_du_le where id = new.projet_id;
  end if;
  return null;
end $$;
create trigger trg_depot_recu after update of statut on public.factures
  for each row when (new.type = 'depot' and new.statut = 'payee' and old.statut is distinct from 'payee')
  execute function app.paiement_recu_apres();
create trigger trg_financement_recu after insert or update of statut on public.financements
  for each row when (new.statut in ('approuve','finance'))
  execute function app.paiement_recu_apres();

-- 3. Solde 72 h avant : seulement pour un dépôt de 40 %, pas pour Financeit
create or replace function app.projet_avant() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_finance boolean;
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
  v_finance := exists (select 1 from public.devis d where d.id = new.devis_id and d.mode_paiement = 'financeit')
            or (tg_op = 'UPDATE' and exists (select 1 from public.financements f
                                              where f.projet_id = new.id and f.statut in ('approuve','finance')));
  new.solde_du_le := case when v_finance then null else
    new.installation_prevue_le
      - coalesce((select (valeur #>> '{}')::int from public.parametres where cle = 'delai_solde_heures'), 72) * interval '1 hour' end;
  return new;
end $$;
