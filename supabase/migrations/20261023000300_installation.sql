-- Phase 3 | Installation au coût du sous-traitant + marge (Simon, 22 oct. 2026).
--   prix = coût / (1 - marge)   (marge sur le PRIX DE VENTE, pas une majoration du coût)
--   coût : grille du sous-traitant par type de travail, ou soumission propre au job
--   marge : taux unique, réglé par Simon ou Mike (paramètre marge_installation_bp)
--   rabais sur l'installation : toujours une approbation de Simon ou Mike

insert into public.parametres (cle, valeur, description) values
  ('marge_installation_bp', '3000', 'Marge sur le prix de vente de l''installation, en points de base (3000 = 30 %). VALEUR PROVISOIRE, à fixer par Simon.')
on conflict (cle) do nothing;

create or replace function app.marge_installation_bp() returns integer
language sql stable as $$
  select coalesce((select (valeur #>> '{}')::int from public.parametres where cle = 'marge_installation_bp'), 3000)
$$;

-- Prix de vente à partir du coût, arrondi au cent.
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

-- Grille de prix des sous-traitants. Un prix ne se modifie pas : on ajoute une ligne datée.
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

-- Coût en vigueur selon la grille.
create or replace function public.hvac_cout_installation(p_sous_traitant uuid, p_type uuid, p_date date default current_date)
returns bigint language sql stable security invoker set search_path = public as $$
  select cout_cents from public.tarifs_sous_traitants
   where fournisseur_id = p_sous_traitant and type_travail_id = p_type and en_vigueur_du <= p_date
   order by en_vigueur_du desc limit 1
$$;
revoke all on function public.hvac_cout_installation(uuid, uuid, date) from public, anon;
grant execute on function public.hvac_cout_installation(uuid, uuid, date) to authenticated;

-- Lignes de devis : type de ligne et instantané du coût et de la marge.
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

  -- Prix imposé : catalogue (produit, kit) ou coût du sous-traitant + marge (installation)
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
    -- La marge est figée sur la ligne au moment du calcul.
    -- Jamais saisie par le vendeur : taux en vigueur à la création, conservé ensuite.
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

-- Le renouvellement recopie aussi l'installation. La grille et la marge sont relues
-- à la date du nouveau devis (prix à jour), sauf pour une soumission.
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

-- Sécurité
alter table public.types_travaux enable row level security;
alter table public.tarifs_sous_traitants enable row level security;
revoke all on public.types_travaux, public.tarifs_sous_traitants from anon;
create policy lecture on public.types_travaux for select to authenticated using (app.employe_id() is not null);
create policy ajout_admin on public.types_travaux for insert to authenticated with check (app.est_admin());
create policy maj_admin on public.types_travaux for update to authenticated using (app.est_admin()) with check (app.est_admin());
-- Les coûts des sous-traitants : rôles commerciaux et admin seulement (pas les techniciens).
create policy lecture on public.tarifs_sous_traitants for select to authenticated
  using (app.voit_tout() or app.est_commercial());
create policy ajout_admin on public.tarifs_sous_traitants for insert to authenticated with check (app.est_admin());
