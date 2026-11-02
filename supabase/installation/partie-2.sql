-- Installation HVAC Belleflamme | partie 2 sur 6 | à coller dans Supabase > SQL Editor > Run
-- Généré depuis supabase/migrations (commentaires retirés). Les parties s'exécutent DANS L'ORDRE, une seule fois.

-- ===== 20261023000700_rabais_global.sql =====
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
alter table public.approbations_rabais
  add column rabais_mode text,
  add column rabais_valeur bigint;
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

-- ===== 20261023000800_numero_devis_mike.sql =====
update public.formats_numerotation
   set modele = '{seq}', prefixe = '', portee = 'globale',
       description = 'Même série que l''app de Mike (#120815). Départ de démo : 900001, aligné à la greffe.'
 where cle = 'devis';
insert into public.compteurs (cle, periode, prochain) values ('devis', '*', 900001)
on conflict (cle, periode) do update set prochain = greatest(public.compteurs.prochain, 900001);

-- ===== 20261023000900_sous_traitants.sql =====
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
create or replace function app.est_planification() returns boolean
language sql stable as $$ select coalesce(app.role() in ('Admin tout','Direction','Coordonnateur'), false) $$;
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
create policy ajout_planif on public.fournisseurs for insert to authenticated with check (app.est_planification());
create policy maj_planif on public.fournisseurs for update to authenticated using (app.est_planification());
create policy ajout_planif on public.employes for insert to authenticated
  with check (app.est_planification() and role = 'Sous-traitant');

-- ===== 20261024000100_commande.sql =====
insert into public.parametres (cle, valeur, description) values
  ('adresse_entrepot', '"1090 boul. des Laurentides, local 108, Saint-Jérôme (Québec) J7Z 7L1"',
   'Adresse de livraison par défaut des bons de commande (entrepôt).')
on conflict (cle) do nothing;
insert into public.formats_numerotation (cle, modele, prefixe, portee, description) values
  ('bt_projet', 'RV{seq:3}', 'RV', 'globale', 'BT « Vendu » d''un projet : RV001, RV002... par code projet.'),
  ('bc', '{prefixe}-{seq}', '', 'globale', 'Bon de commande : préfixe du code projet + série à partir de 100.')
on conflict (cle) do nothing;
alter table public.fournisseurs add column adresse text;
create or replace function app.prefixe_de_code(p_code text) returns text
language sql immutable as $$ select substring(p_code from '^[A-Z]{3}-[A-Z]{3}-[A-Z]{3}') $$;
alter table public.bons_travail drop constraint bons_travail_statut_check;
alter table public.bons_travail add constraint bons_travail_statut_check
  check (statut in ('brouillon','planifie','en_cours','termine','annule'));
alter table public.bons_travail add column type text not null default 'RV';
create or replace function app.bt_numero() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_code text; v_n bigint;
begin
  if tg_op = 'INSERT' then
    if new.projet_id is not null then
      select code_projet into v_code from public.projets where id = new.projet_id;
      insert into public.compteurs(cle, periode) values ('bt_projet', v_code) on conflict do nothing;
      update public.compteurs set prochain = prochain + 1, updated_at = now()
       where cle = 'bt_projet' and periode = v_code returning prochain - 1 into v_n;
      new.numero := new.type || lpad(v_n::text, 3, '0') || ' ' || v_code;
    else
      new.numero := app.prochain_numero('bt', new.succursale_code, null, current_date);
    end if;
  elsif new.numero is distinct from old.numero then
    raise exception 'Le numéro ne se modifie pas' using errcode = '42501';
  end if;
  return new;
end $$;
drop trigger trg_numero on public.bons_travail;
create trigger trg_numero before insert or update on public.bons_travail
  for each row execute function app.bt_numero();
alter table public.bt_lignes
  add column position integer not null default 1,
  add column devis_ligne_id uuid references public.devis_lignes(id),
  add column type_ligne text not null default 'produit' check (type_ligne in ('produit','installation','service')),
  add column provenance text check (provenance in ('a_determiner','entrepot','a_commander')),
  add column quantite_installee numeric(10,2);
create table public.bons_commande (
  id                uuid primary key default gen_random_uuid(),
  numero            text unique,
  division          text not null default 'Ventilation' references public.divisions(nom),
  succursale_code   text not null references public.succursales(code),
  projet_id         uuid references public.projets(id),
  bon_travail_id    uuid references public.bons_travail(id),
  fournisseur_id    uuid not null references public.fournisseurs(id),
  statut            text not null default 'brouillon' check (statut in ('brouillon','envoye','confirme','recu','annule')),
  mode_livraison    text not null default 'entrepot' check (mode_livraison in ('entrepot','ramassage')),
  ramassage_par     uuid references public.fournisseurs(id),     -- sous-traitant qui ramasse chez le fournisseur
  adresse_livraison text,
  date_livraison    date,                                        -- null = « TBD »
  sous_total_cents  bigint not null default 0,
  tps_cents         bigint not null default 0,
  tvq_cents         bigint not null default 0,
  total_cents       bigint not null default 0,
  notes             text,
  envoye_le         timestamptz,
  recu_le           timestamptz,
  created_by        uuid references public.employes(id) default app.employe_id(),
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  check (mode_livraison <> 'ramassage' or ramassage_par is not null)
);
call app.preparer_table('public.bons_commande');
create index on public.bons_commande (projet_id);
create table public.bc_lignes (
  id                  uuid primary key default gen_random_uuid(),
  bon_commande_id     uuid not null references public.bons_commande(id),
  position            integer not null default 1,
  produit_id          uuid not null references public.produits(id),
  bt_ligne_id         uuid references public.bt_lignes(id),
  description         text not null,
  quantite            numeric(10,2) not null check (quantite > 0),
  cout_unitaire_cents bigint not null default 0,
  montant_cents       bigint not null default 0,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);
call app.preparer_table('public.bc_lignes', false);
alter table public.bt_lignes add column bc_ligne_id uuid references public.bc_lignes(id);
create or replace function app.bc_avant() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_code text; v_prefixe text; v_n bigint;
begin
  if tg_op = 'INSERT' then
    select code_projet into v_code from public.projets where id = new.projet_id;
    v_prefixe := coalesce(app.prefixe_de_code(v_code), 'HVAC');
    insert into public.compteurs(cle, periode, prochain) values ('bc', v_prefixe, 100) on conflict do nothing;
    update public.compteurs set prochain = prochain + 1, updated_at = now()
     where cle = 'bc' and periode = v_prefixe returning prochain - 1 into v_n;
    new.numero := v_prefixe || '-' || v_n;
    new.adresse_livraison := coalesce(new.adresse_livraison,
      (select valeur #>> '{}' from public.parametres where cle = 'adresse_entrepot'));
    return new;
  end if;
  if new.numero is distinct from old.numero then
    raise exception 'Le numéro de BC ne se modifie pas' using errcode = '42501';
  end if;
  if pg_trigger_depth() = 1 then   -- totaux : calculés par la base seulement
    new.sous_total_cents := old.sous_total_cents; new.tps_cents := old.tps_cents;
    new.tvq_cents := old.tvq_cents; new.total_cents := old.total_cents;
  end if;
  if new.statut <> old.statut then
    if not (old.statut, new.statut) in (('brouillon','envoye'),('brouillon','annule'),('envoye','confirme'),
                                        ('envoye','recu'),('confirme','recu'),('envoye','annule'),('confirme','annule')) then
      raise exception 'Passage de BC non permis : % -> %', old.statut, new.statut using errcode = 'P0001';
    end if;
    if new.statut = 'envoye' then
      if not exists (select 1 from public.bc_lignes where bon_commande_id = new.id) then
        raise exception 'BC % vide', new.numero using errcode = 'P0001';
      end if;
      new.envoye_le := now();
    end if;
    if new.statut = 'recu' then new.recu_le := now(); end if;
  elsif old.statut <> 'brouillon' and pg_trigger_depth() = 1
        and (new.fournisseur_id, new.projet_id) is distinct from (old.fournisseur_id, old.projet_id) then
    raise exception 'BC envoyé : fournisseur et projet figés' using errcode = '42501';
  end if;
  return new;
end $$;
create trigger trg_bc_avant before insert or update on public.bons_commande
  for each row execute function app.bc_avant();
create trigger trg_bc_delete before delete on public.bons_commande
  for each row execute function app.interdit();
create trigger trg_audit after insert or update on public.bons_commande
  for each row execute function app.audit();
create or replace function app.bc_ligne_avant() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_statut text;
begin
  select statut into v_statut from public.bons_commande where id = coalesce(new.bon_commande_id, old.bon_commande_id);
  if v_statut <> 'brouillon' then
    raise exception 'BC non modifiable (statut %)', v_statut using errcode = '42501';
  end if;
  if tg_op = 'DELETE' then return old; end if;
  select cout_cents into new.cout_unitaire_cents from public.produits where id = new.produit_id;
  new.montant_cents := round(new.quantite * new.cout_unitaire_cents)::bigint;
  return new;
end $$;
create trigger trg_bc_ligne_avant before insert or update or delete on public.bc_lignes
  for each row execute function app.bc_ligne_avant();
create or replace function app.recalculer_bc(p_bc uuid) returns void
language plpgsql security definer set search_path = public as $$
declare v_net bigint; v_tps bigint; v_tvq bigint;
begin
  select coalesce(sum(montant_cents), 0) into v_net from public.bc_lignes where bon_commande_id = p_bc;
  select t.tps, t.tvq into v_tps, v_tvq from app.taxes(v_net, current_date) t;
  update public.bons_commande set sous_total_cents = v_net, tps_cents = v_tps, tvq_cents = v_tvq,
         total_cents = v_net + v_tps + v_tvq where id = p_bc;
end $$;
create or replace function app.bc_lignes_apres() returns trigger
language plpgsql security definer set search_path = public as $$
begin perform app.recalculer_bc(coalesce(new.bon_commande_id, old.bon_commande_id)); return null; end $$;
create trigger trg_bc_lignes_apres after insert or update or delete on public.bc_lignes
  for each row execute function app.bc_lignes_apres();
create table public.notifications (
  id                     uuid primary key default gen_random_uuid(),
  destinataire_employe_id uuid references public.employes(id),
  destinataire_fournisseur_id uuid references public.fournisseurs(id),   -- tous les comptes de ce sous-traitant
  type                   text not null,
  titre                  text not null,
  message                text,
  lien                   text,
  lu_le                  timestamptz,
  created_at             timestamptz not null default now(),
  check (destinataire_employe_id is not null or destinataire_fournisseur_id is not null)
);
create table public.envois (
  id              uuid primary key default gen_random_uuid(),
  notification_id uuid references public.notifications(id),
  canal           text not null check (canal in ('courriel','sms')),
  destinataire    text not null,
  sujet           text,
  corps           text not null,
  statut          text not null default 'en_attente' check (statut in ('en_attente','envoye','echec','annule')),
  essais          integer not null default 0,
  derniere_erreur text,
  created_at      timestamptz not null default now(),
  envoye_le       timestamptz
);
create or replace function app.notifier_fournisseur(p_fournisseur uuid, p_type text, p_titre text, p_message text, p_lien text)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid; f public.fournisseurs%rowtype;
begin
  insert into public.notifications (destinataire_fournisseur_id, type, titre, message, lien)
  values (p_fournisseur, p_type, p_titre, p_message, p_lien) returning id into v_id;
  select * into f from public.fournisseurs where id = p_fournisseur;
  if f.courriel is not null then
    insert into public.envois (notification_id, canal, destinataire, sujet, corps) values (v_id, 'courriel', f.courriel, p_titre, p_message);
  end if;
  if f.telephone is not null then
    insert into public.envois (notification_id, canal, destinataire, corps) values (v_id, 'sms', f.telephone, p_titre || ' : ' || p_message);
  end if;
  return v_id;
end $$;
create or replace function app.fournisseur_produit(p_produit uuid) returns uuid
language sql stable security definer set search_path = public as $$
  select coalesce(p.fournisseur_id, m.fournisseur_id)
    from public.produits p left join public.marques m on m.id = p.marque_id where p.id = p_produit
$$;
create or replace function app.creer_commande(p_devis uuid) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  d public.devis%rowtype; v_projet uuid; v_bt uuid; v_st uuid; v_pos int := 0; v_bc uuid;
  l record; c record;
begin
  select * into d from public.devis where id = p_devis;
  if exists (select 1 from public.projets where devis_id = p_devis) then
    return (select id from public.projets where devis_id = p_devis);
  end if;
  select sous_traitant_id into v_st from public.devis_lignes
   where devis_id = p_devis and type_ligne = 'installation' order by position limit 1;
  insert into public.projets (division, succursale_code, client_id, site_id, devis_id, vendeur_id, statut)
  values (d.division, d.succursale_code, d.client_id, d.site_id, d.id, d.vendeur_id, 'a_planifier')
  returning id into v_projet;
  insert into public.bons_travail (division, succursale_code, projet_id, assigne_fournisseur_id, statut, travaux)
  values (d.division, d.succursale_code, v_projet, v_st, 'brouillon',
          'Brouillon automatique à l''acceptation du devis #' || d.numero || '. À planifier (sous-traitant et date).')
  returning id into v_bt;
  for l in
    select dl.id as devis_ligne_id, dl.position, 'produit' as type_ligne, dl.produit_id, dl.description, dl.quantite
      from public.devis_lignes dl where dl.devis_id = p_devis and dl.type_ligne = 'produit'
    union all
    select dl.id, dl.position, 'produit', ki.produit_id, p.nom, dl.quantite * ki.quantite
      from public.devis_lignes dl join public.kit_items ki on ki.kit_id = dl.kit_id join public.produits p on p.id = ki.produit_id
     where dl.devis_id = p_devis and dl.type_ligne = 'kit'
    union all
    select dl.id, dl.position, case when dl.type_ligne = 'installation' then 'installation' else 'service' end, null, dl.description, dl.quantite
      from public.devis_lignes dl where dl.devis_id = p_devis and dl.type_ligne in ('installation','libre')
    order by 2
  loop
    v_pos := v_pos + 1;
    insert into public.bt_lignes (bon_travail_id, position, devis_ligne_id, type_ligne, produit_id, description, quantite, provenance)
    values (v_bt, v_pos, l.devis_ligne_id, l.type_ligne, l.produit_id, l.description, l.quantite,
            case when l.type_ligne <> 'produit' then null
                 when app.fournisseur_produit(l.produit_id) is not null
                      and exists (select 1 from public.produits p where p.id = l.produit_id and p.stocke)
                   then 'a_commander' else 'a_determiner' end);
  end loop;
  for c in
    select app.fournisseur_produit(bl.produit_id) as fournisseur_id from public.bt_lignes bl
     where bl.bon_travail_id = v_bt and bl.provenance = 'a_commander' group by 1
  loop
    insert into public.bons_commande (division, succursale_code, projet_id, bon_travail_id, fournisseur_id, mode_livraison, ramassage_par)
    values (d.division, d.succursale_code, v_projet, v_bt, c.fournisseur_id,
            case when v_st is not null then 'ramassage' else 'entrepot' end, v_st)
    returning id into v_bc;
    insert into public.bc_lignes (bon_commande_id, position, produit_id, bt_ligne_id, description, quantite)
    select v_bc, bl.position, bl.produit_id, bl.id, bl.description, bl.quantite
      from public.bt_lignes bl
     where bl.bon_travail_id = v_bt and bl.provenance = 'a_commander' and app.fournisseur_produit(bl.produit_id) = c.fournisseur_id;
    update public.bt_lignes bl set bc_ligne_id = x.id
      from public.bc_lignes x where x.bt_ligne_id = bl.id and x.bon_commande_id = v_bc;
  end loop;
  return v_projet;
end $$;
create or replace function app.devis_accepte_apres() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform app.creer_commande(new.id);
  return null;
end $$;
create trigger trg_devis_accepte after update of statut on public.devis
  for each row when (new.statut = 'accepte' and old.statut is distinct from 'accepte')
  execute function app.devis_accepte_apres();
create or replace function app.paiement_permet_planif(p_projet uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.factures f where f.projet_id = p_projet and f.type = 'depot' and f.statut = 'payee')
      or exists (select 1 from public.financements fi where fi.projet_id = p_projet and fi.statut in ('approuve','finance'))
$$;
create or replace function public.hvac_planifier_bt(p_bt uuid, p_jour date, p_heure time default '08:00',
                                                    p_fuseau text default 'America/Toronto')
returns jsonb language plpgsql security definer set search_path = public as $$
declare b public.bons_travail%rowtype; v_debut timestamptz; v_code text; v_adresse text;
begin
  if not app.est_planification() then
    raise exception 'Planification réservée à la coordination, Simon et Mike' using errcode = '42501';
  end if;
  select * into b from public.bons_travail where id = p_bt for update;
  if not found then raise exception 'BT introuvable' using errcode = 'P0002'; end if;
  if b.statut not in ('brouillon','planifie') then
    raise exception 'BT % : statut % non planifiable', b.numero, b.statut using errcode = 'P0001';
  end if;
  if b.assigne_fournisseur_id is null then
    raise exception 'BT % : aucun sous-traitant assigné', b.numero using errcode = 'P0001';
  end if;
  if p_jour < current_date then raise exception 'Date passée' using errcode = 'P0001'; end if;
  if not exists (select 1 from public.disponibilites_sous_traitants
                  where fournisseur_id = b.assigne_fournisseur_id and jour = p_jour and statut = 'disponible') then
    raise exception 'Le sous-traitant n''est pas disponible le %', p_jour using errcode = 'P0001';
  end if;
  if not app.paiement_permet_planif(b.projet_id) then
    raise exception 'Planification bloquée : dépôt non payé et financement non approuvé' using errcode = 'P0001';
  end if;
  v_debut := (p_jour + p_heure) at time zone p_fuseau;
  update public.bons_travail set prevu_le = v_debut, statut = 'planifie' where id = p_bt;
  update public.projets set installation_prevue_le = v_debut, statut = 'planifie' where id = b.projet_id;
  select p.code_projet, s.adresse || ', ' || s.ville into v_code, v_adresse
    from public.projets p left join public.sites s on s.id = p.site_id where p.id = b.projet_id;
  perform app.notifier_fournisseur(b.assigne_fournisseur_id, 'job_planifiee',
    'Nouvelle job planifiée le ' || to_char(p_jour, 'YYYY-MM-DD'),
    'Projet ' || v_code || coalesce(' | ' || v_adresse, '') || ' | ' || to_char(p_heure, 'HH24:MI') || '. Détails dans l''app (Mes jobs).',
    '/jobs');
  return jsonb_build_object('bt', b.numero, 'prevu_le', v_debut);
end $$;
revoke all on function public.hvac_planifier_bt(uuid, date, time, text) from public, anon;
grant execute on function public.hvac_planifier_bt(uuid, date, time, text) to authenticated;
create or replace function public.hvac_mes_jobs() returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_f uuid := app.mon_fournisseur(); v_res jsonb;
begin
  if v_f is null then raise exception 'Réservé aux sous-traitants' using errcode = '42501'; end if;
  select coalesce(jsonb_agg(j order by j->>'prevu_le'), '[]'::jsonb) into v_res from (
    select jsonb_build_object(
      'id', b.id, 'numero', b.numero, 'statut', b.statut, 'prevu_le', b.prevu_le, 'code_projet', p.code_projet,
      'client', concat_ws(' ', c.prenom, c.nom), 'telephone', c.telephone,
      'adresse', s.adresse, 'ville', s.ville, 'code_postal', s.code_postal,
      'lignes', (select coalesce(jsonb_agg(jsonb_build_object('description', bl.description, 'quantite', bl.quantite,
                   'type', bl.type_ligne, 'provenance', bl.provenance) order by bl.position), '[]'::jsonb)
                   from public.bt_lignes bl where bl.bon_travail_id = b.id),
      'materiel', (select coalesce(jsonb_agg(jsonb_build_object('bc', bc.numero, 'statut', bc.statut, 'mode', bc.mode_livraison,
                   'fournisseur', fo.nom, 'adresse_fournisseur', fo.adresse, 'date_livraison', bc.date_livraison,
                   'adresse_livraison', bc.adresse_livraison)), '[]'::jsonb)
                   from public.bons_commande bc join public.fournisseurs fo on fo.id = bc.fournisseur_id
                  where bc.bon_travail_id = b.id and bc.statut <> 'annule')) as j
      from public.bons_travail b
      join public.projets p on p.id = b.projet_id
      join public.clients c on c.id = p.client_id
      left join public.sites s on s.id = p.site_id
     where b.assigne_fournisseur_id = v_f and b.statut in ('planifie','en_cours','termine')
  ) x;
  perform app.journaliser('lecture', 'jobs_sous_traitant', v_f::text, jsonb_build_object('nb', jsonb_array_length(v_res)));
  return v_res;
end $$;
revoke all on function public.hvac_mes_jobs() from public, anon;
grant execute on function public.hvac_mes_jobs() to authenticated;
create or replace function public.hvac_job_statut(p_bt uuid, p_statut text) returns void
language plpgsql security definer set search_path = public as $$
declare b public.bons_travail%rowtype;
begin
  select * into b from public.bons_travail where id = p_bt;
  if b.assigne_fournisseur_id is distinct from app.mon_fournisseur() then
    raise exception 'Cette job ne t''est pas assignée' using errcode = '42501';
  end if;
  if not (b.statut, p_statut) in (('planifie','en_cours'),('en_cours','termine')) then
    raise exception 'Passage non permis : % -> %', b.statut, p_statut using errcode = 'P0001';
  end if;
  update public.bons_travail set statut = p_statut,
         debut_le = case when p_statut = 'en_cours' then now() else debut_le end,
         fin_le = case when p_statut = 'termine' then now() else fin_le end
   where id = p_bt;
end $$;
revoke all on function public.hvac_job_statut(uuid, text) from public, anon;
grant execute on function public.hvac_job_statut(uuid, text) to authenticated;
alter table public.bons_commande enable row level security;
alter table public.bc_lignes enable row level security;
alter table public.notifications enable row level security;
alter table public.envois enable row level security;
revoke all on public.bons_commande, public.bc_lignes, public.notifications, public.envois from anon;
create or replace function app.voit_bc(p_bc uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select app.acces_succursale((select succursale_code from public.bons_commande where id = p_bc))
$$;
create or replace function app.gere_achats() returns boolean
language sql stable as $$ select app.est_planification() or coalesce(app.role() = 'Comptabilité', false) $$;
create policy lecture on public.bons_commande for select to authenticated using (app.acces_succursale(succursale_code));
create policy maj on public.bons_commande for update to authenticated
  using (app.gere_achats() and app.acces_succursale(succursale_code));
create policy lecture on public.bc_lignes for select to authenticated using (app.voit_bc(bon_commande_id));
create policy ajout on public.bc_lignes for insert to authenticated with check (app.gere_achats() and app.voit_bc(bon_commande_id));
create policy maj on public.bc_lignes for update to authenticated using (app.gere_achats() and app.voit_bc(bon_commande_id));
create policy retrait on public.bc_lignes for delete to authenticated using (app.gere_achats() and app.voit_bc(bon_commande_id));
create policy maj_planif on public.bt_lignes for update to authenticated using (app.est_planification());
create policy lecture on public.notifications for select to authenticated
  using (destinataire_employe_id = app.employe_id()
         or (destinataire_fournisseur_id is not null and destinataire_fournisseur_id = app.mon_fournisseur()));
create policy lu on public.notifications for update to authenticated
  using (destinataire_employe_id = app.employe_id()
         or (destinataire_fournisseur_id is not null and destinataire_fournisseur_id = app.mon_fournisseur()));
create policy lecture_admin on public.envois for select to authenticated using (app.est_admin());

-- ===== 20261024000200_sequence_hvac.sql =====
insert into public.parametres (cle, valeur, description) values
  ('exiger_preinstallation', 'true', 'Un devis ne s''envoie pas sans visite de pré-installation réalisée (ADR-049).')
on conflict (cle) do nothing;
alter table public.projets drop constraint projets_statut_check;
alter table public.projets add constraint projets_statut_check check (statut in (
  'attente_paiement','a_planifier','planifie','en_cours','termine','facture','ferme','annule'));
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
create or replace function app.paiement_recu_apres() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.projet_id is not null and app.paiement_permet_planif(new.projet_id) then
    perform app.creer_bt_bc(new.projet_id);
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
