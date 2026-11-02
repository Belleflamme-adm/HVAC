-- Lot A | Sous-traitants : compte limité, territoire par municipalité, sous-traitant principal,
-- disponibilités, supplément de ville dans le prix de l'installation (ADR-037, ADR-038).

-- ---------------------------------------------------------------------------
-- Municipalités (limites : jeu « Découpages administratifs » du MRNF, CC-BY 4.0).
-- Les lignes sont chargées par une migration générée (scripts/municipalites/).
-- ---------------------------------------------------------------------------
create table public.municipalites (
  code        text primary key,          -- code géographique officiel
  nom         text not null,
  mrc         text,
  region      text,
  actif       boolean not null default true,
  source      text not null default 'Découpages administratifs, MRNF (CC-BY 4.0)',
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
call app.preparer_table('public.municipalites', false);
create index on public.municipalites (lower(nom));

alter table public.sites add column municipalite_code text references public.municipalites(code);

-- ---------------------------------------------------------------------------
-- Compte « Sous-traitant » : un employé (au sens de l'app) rattaché à un fournisseur.
-- ---------------------------------------------------------------------------
alter table public.employes drop constraint employes_role_check;
alter table public.employes
  add column fournisseur_id uuid references public.fournisseurs(id),
  add constraint employes_role_check check (role in (
    'Admin tout','Direction','Gérant de succursale','Vendeur','Coordonnateur','Technicien','Comptabilité','Sous-traitant')),
  add constraint employes_sous_traitant_chk check ((role = 'Sous-traitant') = (fournisseur_id is not null));

create or replace function app.est_sous_traitant() returns boolean
language sql stable as $$ select coalesce(app.role() = 'Sous-traitant', false) $$;

create or replace function app.mon_fournisseur() returns uuid
language sql stable security definer set search_path = public as $$
  select fournisseur_id from public.employes where auth_user_id = auth.uid() and actif and role = 'Sous-traitant'
$$;

-- Planification (Coordonnateur, admin) : gère sous-traitants, principaux, et voit les disponibilités.
create or replace function app.est_planification() returns boolean
language sql stable as $$ select coalesce(app.role() in ('Admin tout','Direction','Coordonnateur'), false) $$;

-- ---------------------------------------------------------------------------
-- Territoire : le sous-traitant indique, ville par ville, s'il accepte, accepte avec supplément, ou refuse.
-- ---------------------------------------------------------------------------
create table public.territoires_sous_traitants (
  fournisseur_id    uuid not null references public.fournisseurs(id),
  municipalite_code text not null references public.municipalites(code),
  statut            text not null check (statut in ('accepte','supplement','refuse')),
  supplement_cents  bigint,
  modifie_par       uuid references public.employes(id) default app.employe_id(),
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  primary key (fournisseur_id, municipalite_code),
  check ((statut = 'supplement') = (supplement_cents is not null and supplement_cents > 0))
);
call app.preparer_table('public.territoires_sous_traitants', false);
create trigger trg_audit after insert or update or delete on public.territoires_sous_traitants
  for each row execute function app.audit();

-- Sous-traitant principal par municipalité : désigné par Simon ou Mike (ou la coordination).
create table public.principaux_municipalites (
  municipalite_code text primary key references public.municipalites(code),
  fournisseur_id    uuid references public.fournisseurs(id),
  designe_par       uuid references public.employes(id) default app.employe_id(),
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);
call app.preparer_table('public.principaux_municipalites', false);
create trigger trg_audit after insert or update on public.principaux_municipalites
  for each row execute function app.audit();

create or replace function app.principal_garde() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.fournisseur_id is not null and not exists (
       select 1 from public.territoires_sous_traitants
        where fournisseur_id = new.fournisseur_id and municipalite_code = new.municipalite_code
          and statut in ('accepte','supplement')) then
    raise exception 'Ce sous-traitant ne dessert pas cette municipalité' using errcode = 'P0001';
  end if;
  new.designe_par := coalesce(app.employe_id(), new.designe_par);
  return new;
end $$;
create trigger trg_principal_garde before insert or update on public.principaux_municipalites
  for each row execute function app.principal_garde();

-- Si le principal refuse désormais la ville, la ville n'a plus de principal (à redésigner).
create or replace function app.territoire_apres() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.statut = 'refuse' then
    update public.principaux_municipalites set fournisseur_id = null
     where municipalite_code = new.municipalite_code and fournisseur_id = new.fournisseur_id;
  end if;
  return null;
end $$;
create trigger trg_territoire_apres after insert or update on public.territoires_sous_traitants
  for each row execute function app.territoire_apres();

-- ---------------------------------------------------------------------------
-- Disponibilités : inscrites par le sous-traitant lui-même.
-- ---------------------------------------------------------------------------
create table public.disponibilites_sous_traitants (
  fournisseur_id uuid not null references public.fournisseurs(id),
  jour           date not null,
  statut         text not null check (statut in ('disponible','indisponible')),
  note           text,
  modifie_par    uuid references public.employes(id) default app.employe_id(),
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  primary key (fournisseur_id, jour)
);
call app.preparer_table('public.disponibilites_sous_traitants', false);

-- ---------------------------------------------------------------------------
-- Sous-traitants pour une municipalité : ceux qui acceptent, principal en premier.
-- ---------------------------------------------------------------------------
create or replace function public.hvac_sous_traitants_pour(p_municipalite text)
returns table (fournisseur_id uuid, nom text, statut text, supplement_cents bigint, principal boolean)
language sql stable security invoker set search_path = public as $$
  select t.fournisseur_id, f.nom, t.statut, t.supplement_cents,
         coalesce(p.fournisseur_id = t.fournisseur_id, false) as principal
    from public.territoires_sous_traitants t
    join public.fournisseurs f on f.id = t.fournisseur_id and f.actif
    left join public.principaux_municipalites p on p.municipalite_code = t.municipalite_code
   where t.municipalite_code = p_municipalite and t.statut in ('accepte','supplement')
   order by principal desc, coalesce(t.supplement_cents, 0), f.nom
$$;
revoke all on function public.hvac_sous_traitants_pour(text) from public, anon;
grant execute on function public.hvac_sous_traitants_pour(text) to authenticated;

-- ---------------------------------------------------------------------------
-- Installation : supplément de ville ajouté au coût AVANT la marge (ADR-038).
-- La ville vient du lieu d'installation du devis. Refus du sous-traitant = ligne refusée.
-- ---------------------------------------------------------------------------
alter table public.devis_lignes add column supplement_cents bigint check (supplement_cents is null or supplement_cents >= 0);

create or replace function app.supplement_installation(p_devis uuid, p_sous_traitant uuid) returns bigint
language plpgsql stable security definer set search_path = public as $$
declare v_muni text; t public.territoires_sous_traitants%rowtype;
begin
  select s.municipalite_code into v_muni from public.devis d join public.sites s on s.id = d.site_id where d.id = p_devis;
  if v_muni is null then return 0; end if;     -- lieu sans municipalité : aucune vérification possible
  select * into t from public.territoires_sous_traitants where fournisseur_id = p_sous_traitant and municipalite_code = v_muni;
  if not found or t.statut = 'refuse' then
    raise exception 'Ce sous-traitant ne dessert pas la municipalité du lieu d''installation' using errcode = 'P0001';
  end if;
  return coalesce(t.supplement_cents, 0);
end $$;

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
      new.source_cout := 'grille';
      new.cout_cents := public.hvac_cout_installation(new.sous_traitant_id, new.type_travail_id, v_date);
      if new.cout_cents is null then
        raise exception 'Aucun prix dans la grille pour ce sous-traitant et ce type de travail : saisir une soumission'
          using errcode = 'P0001';
      end if;
      -- Supplément de ville (grille seulement : une soumission inclut déjà le déplacement).
      new.supplement_cents := app.supplement_installation(new.devis_id, new.sous_traitant_id);
    else
      if new.cout_cents is null or coalesce(trim(new.reference_soumission), '') = '' then
        raise exception 'Soumission : coût et référence (no de soumission du sous-traitant) requis' using errcode = 'P0001';
      end if;
      perform app.supplement_installation(new.devis_id, new.sous_traitant_id);   -- vérifie le territoire
      new.supplement_cents := 0;
    end if;
    new.marge_bp := case when tg_op = 'UPDATE' and old.marge_bp is not null then old.marge_bp
                         else app.marge_installation_bp() end;
    new.prix_unitaire_cents := app.prix_avec_marge(new.cout_cents + new.supplement_cents, new.marge_bp);
  elsif new.type_ligne = 'rabais' then
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
    when new.type_ligne in ('kit','installation','rabais') then 0
    when new.type_ligne = 'produit' then app.plafond_rabais_bp(new.produit_id, v_vendeur)
    else app.plafond_rabais_bp(null, v_vendeur) end;
  new.approbation_requise := new.type_ligne = 'rabais' or new.rabais_bp > new.plafond_bp;
  return new;
end $$;

-- ---------------------------------------------------------------------------
-- Session : le contrat expose le fournisseur d'un sous-traitant.
-- ---------------------------------------------------------------------------
create or replace function public.hvac_session() returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_email text := lower(auth.jwt() ->> 'email'); e public.employes%rowtype;
begin
  if auth.uid() is null then return null; end if;
  update public.employes set auth_user_id = auth.uid()
   where auth_user_id is null and lower(email) = v_email and actif;
  select * into e from public.employes where auth_user_id = auth.uid() and actif;
  if not found then return null; end if;
  return jsonb_build_object('id', e.id, 'monday_item_id', e.monday_item_id, 'email', e.email,
    'prenom', e.prenom, 'nom', e.nom, 'role', e.role, 'succursale_code', e.succursale_code,
    'peut_approuver_rabais', e.peut_approuver_rabais, 'fournisseur_id', e.fournisseur_id);
end $$;

-- ---------------------------------------------------------------------------
-- Sécurité. Un sous-traitant ne voit ni les coûts, ni les marges, ni les autres employés.
-- ---------------------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array['succursales','divisions','parametres','taux_taxes','formats_numerotation',
                           'marques','produits','kits','kit_items','fournisseurs','employes','employe_succursales'] loop
    execute format('drop policy lecture on public.%I', t);
    execute format('create policy lecture on public.%I for select to authenticated using (app.employe_id() is not null and not app.est_sous_traitant())', t);
  end loop;
end $$;
create policy lecture_soi on public.employes for select to authenticated using (auth_user_id = auth.uid());
create policy lecture_soi on public.fournisseurs for select to authenticated using (id = app.mon_fournisseur());
create policy lecture_sous_traitant on public.tarifs_sous_traitants for select to authenticated
  using (fournisseur_id = app.mon_fournisseur());

alter table public.municipalites enable row level security;
alter table public.territoires_sous_traitants enable row level security;
alter table public.principaux_municipalites enable row level security;
alter table public.disponibilites_sous_traitants enable row level security;
revoke all on public.municipalites, public.territoires_sous_traitants, public.principaux_municipalites,
              public.disponibilites_sous_traitants from anon;

create policy lecture on public.municipalites for select to authenticated using (app.employe_id() is not null);
create policy ajout_admin on public.municipalites for insert to authenticated with check (app.est_admin());
create policy maj_admin on public.municipalites for update to authenticated using (app.est_admin());

-- Territoire : le sous-traitant gère le sien ; la planification et les vendeurs le lisent ;
-- la planification peut le corriger à sa demande.
create policy lecture on public.territoires_sous_traitants for select to authenticated
  using (fournisseur_id = app.mon_fournisseur() or app.est_planification() or app.est_commercial() or app.voit_tout());
create policy ecriture on public.territoires_sous_traitants for insert to authenticated
  with check (fournisseur_id = app.mon_fournisseur() or app.est_planification());
create policy maj on public.territoires_sous_traitants for update to authenticated
  using (fournisseur_id = app.mon_fournisseur() or app.est_planification())
  with check (fournisseur_id = app.mon_fournisseur() or app.est_planification());
create policy retrait on public.territoires_sous_traitants for delete to authenticated
  using (fournisseur_id = app.mon_fournisseur() or app.est_planification());

create policy lecture on public.principaux_municipalites for select to authenticated
  using (app.employe_id() is not null and not app.est_sous_traitant() or fournisseur_id = app.mon_fournisseur());
create policy ecriture on public.principaux_municipalites for insert to authenticated with check (app.est_planification());
create policy maj on public.principaux_municipalites for update to authenticated using (app.est_planification());

create policy lecture on public.disponibilites_sous_traitants for select to authenticated
  using (fournisseur_id = app.mon_fournisseur() or app.est_planification() or app.est_commercial() or app.voit_tout());
create policy ecriture on public.disponibilites_sous_traitants for insert to authenticated
  with check (fournisseur_id = app.mon_fournisseur());
create policy maj on public.disponibilites_sous_traitants for update to authenticated
  using (fournisseur_id = app.mon_fournisseur()) with check (fournisseur_id = app.mon_fournisseur());
create policy retrait on public.disponibilites_sous_traitants for delete to authenticated
  using (fournisseur_id = app.mon_fournisseur());

-- La planification crée les sous-traitants et leurs comptes.
create policy ajout_planif on public.fournisseurs for insert to authenticated with check (app.est_planification());
create policy maj_planif on public.fournisseurs for update to authenticated using (app.est_planification());
create policy ajout_planif on public.employes for insert to authenticated
  with check (app.est_planification() and role = 'Sous-traitant');
