-- Registre des versions de la liste de prix de chaque sous-traitant (ADR-065).
-- Chaque enregistrement qui change la liste (prix modifié par le sous-traitant ou par Belleflamme, travail confié
-- ajouté ou retiré) crée une version figée : date, heure, auteur, lignes, changements et empreinte SHA-256.
-- Le PDF est produit à partir de cette copie figée ; la version elle-même ne se modifie ni ne s'efface jamais.
-- Alerte : quand un sous-traitant modifie sa liste trop souvent (paramètre seuil_versions_liste_30j, 3 par défaut).

create table public.listes_prix_versions (
  id                 uuid primary key default gen_random_uuid(),
  fournisseur_id     uuid not null references public.fournisseurs(id),
  numero             integer not null check (numero > 0),
  cree_le            timestamptz not null default now(),
  auteur_employe_id  uuid references public.employes(id),
  auteur_nom         text not null,
  par_sous_traitant  boolean not null default false,
  motif              text not null,
  lignes             jsonb not null,      -- [{ code, nom, categorie, unite, cout_cents, en_vigueur_du }]
  changements        jsonb not null,      -- [{ type: ajout | retrait | prix, code, nom, avant, apres }]
  nb_lignes          integer not null,
  nb_changements     integer not null,
  empreinte          text not null,       -- SHA-256 des lignes : prouve que le PDF n'a pas été retouché
  unique (fournisseur_id, numero)
);
create index listes_prix_versions_recent on public.listes_prix_versions (fournisseur_id, cree_le desc);
alter table public.listes_prix_versions enable row level security;
-- Lecture : Belleflamme (admin, planification, direction) et le sous-traitant pour son propre registre.
-- Aucune politique d'écriture : seules les fonctions ci-dessous (security definer) ajoutent une version.
create policy lecture on public.listes_prix_versions for select to authenticated
  using (app.est_admin() or app.est_planification() or app.voit_tout() or fournisseur_id = app.mon_fournisseur());
revoke all on public.listes_prix_versions from anon;
grant select on public.listes_prix_versions to authenticated;

create or replace function app.version_immuable() returns trigger language plpgsql as $$
begin
  raise exception '% interdit sur listes_prix_versions (une version archivée ne se modifie pas)', tg_op using errcode = '42501';
end $$;
create trigger trg_version_immuable before update or delete on public.listes_prix_versions
  for each row execute function app.version_immuable();

insert into public.parametres (cle, valeur, description)
values ('seuil_versions_liste_30j', '3', 'Alerte quand un sous-traitant modifie sa liste de prix ce nombre de fois ou plus en 30 jours (ADR-065)')
on conflict (cle) do nothing;

-- Crée une version si la liste a changé depuis la dernière (ou la première version). Retourne le numéro, ou null.
create or replace function app.versionner_liste(p_fournisseur uuid, p_motif text) returns integer
language plpgsql security definer set search_path = public as $$
declare
  v_jour date := (now() at time zone 'America/Toronto')::date;
  v_lignes jsonb; v_prec jsonb; v_chg jsonb; v_num integer; v_emp uuid := app.employe_id();
  v_auteur text; v_st boolean := app.mon_fournisseur() is not null; v_seuil integer; v_n30 integer;
begin
  perform pg_advisory_xact_lock(hashtext('liste_prix:' || p_fournisseur));
  select coalesce(jsonb_agg(jsonb_build_object(
           'code', t.code, 'nom', t.nom, 'categorie', coalesce(c.nom, t.categorie), 'unite', t.unite,
           'cout_cents', public.hvac_cout_installation(p_fournisseur, t.id, v_jour),
           'en_vigueur_du', (select max(x.en_vigueur_du) from public.tarifs_sous_traitants x
                              where x.fournisseur_id = p_fournisseur and x.type_travail_id = t.id and x.en_vigueur_du <= v_jour))
         order by c.ordre nulls last, t.ordre, t.code), '[]')
    into v_lignes
    from public.travaux_sous_traitants ts
    join public.types_travaux t on t.id = ts.type_travail_id
    left join public.categories_travaux c on c.code = t.categorie
   where ts.fournisseur_id = p_fournisseur;

  select lignes, numero into v_prec, v_num from public.listes_prix_versions
   where fournisseur_id = p_fournisseur order by numero desc limit 1;

  if v_prec is null then
    if jsonb_array_length(v_lignes) = 0 then return null; end if;
    v_chg := '[]';
  else
    select coalesce(jsonb_agg(x order by x->>'code'), '[]') into v_chg from (
      select jsonb_build_object('type', 'ajout', 'code', n->>'code', 'nom', n->>'nom', 'avant', null, 'apres', n->'cout_cents') as x
        from jsonb_array_elements(v_lignes) n
       where not exists (select 1 from jsonb_array_elements(v_prec) o where o->>'code' = n->>'code')
      union all
      select jsonb_build_object('type', 'retrait', 'code', o->>'code', 'nom', o->>'nom', 'avant', o->'cout_cents', 'apres', null)
        from jsonb_array_elements(v_prec) o
       where not exists (select 1 from jsonb_array_elements(v_lignes) n where n->>'code' = o->>'code')
      union all
      select jsonb_build_object('type', 'prix', 'code', n->>'code', 'nom', n->>'nom', 'avant', o->'cout_cents', 'apres', n->'cout_cents')
        from jsonb_array_elements(v_lignes) n join jsonb_array_elements(v_prec) o on o->>'code' = n->>'code'
       where (o->'cout_cents') is distinct from (n->'cout_cents')
    ) s;
    if jsonb_array_length(v_chg) = 0 then return null; end if;
  end if;

  select coalesce(nullif(trim(e.prenom || ' ' || e.nom), ''), e.email) into v_auteur from public.employes e where e.id = v_emp;
  v_num := coalesce(v_num, 0) + 1;
  insert into public.listes_prix_versions (fournisseur_id, numero, auteur_employe_id, auteur_nom, par_sous_traitant, motif,
                                           lignes, changements, nb_lignes, nb_changements, empreinte)
  values (p_fournisseur, v_num, v_emp, coalesce(v_auteur, 'Système'), v_st, p_motif,
          v_lignes, v_chg, jsonb_array_length(v_lignes), jsonb_array_length(v_chg),
          encode(sha256(convert_to(v_lignes::text, 'UTF8')), 'hex'));

  -- Alerte : modifications trop fréquentes par le sous-traitant
  if v_st then
    v_seuil := coalesce((select (valeur #>> '{}')::integer from public.parametres where cle = 'seuil_versions_liste_30j'), 3);
    select count(*) into v_n30 from public.listes_prix_versions
     where fournisseur_id = p_fournisseur and par_sous_traitant and cree_le > now() - interval '30 days';
    if v_n30 >= v_seuil then
      insert into public.notifications (destinataire_employe_id, type, titre, message, lien)
      select emp.id, 'liste_prix_frequente', 'Liste de prix modifiée souvent',
             format('%s a modifié sa liste de prix %s fois en 30 jours (version %s).',
                    (select nom from public.fournisseurs where id = p_fournisseur), v_n30, v_num),
             '/installation-grille?fournisseur=' || p_fournisseur
        from public.employes emp where emp.actif and emp.role = 'Admin tout';
    end if;
  end if;
  return v_num;
end $$;
revoke all on function app.versionner_liste(uuid, text) from public;

-- Le sous-traitant (ou Belleflamme) modifie les prix : version au registre à la fin.
-- Belleflamme qui met un prix sur un travail non confié le confie du même coup (un prix = un travail offert).
create or replace function public.hvac_maj_mes_prix(p_prix jsonb, p_fournisseur uuid default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_f uuid := coalesce(app.mon_fournisseur(), case when app.est_admin() or app.est_planification() then p_fournisseur end);
  v_st boolean := app.mon_fournisseur() is not null;
  v_jour date := (now() at time zone 'America/Toronto')::date;
  x jsonb; v_type uuid; v_cout bigint; v_ancien bigint; n integer := 0; v_types uuid[] := '{}'; v_version integer;
begin
  if v_f is null then raise exception 'Sous-traitant requis' using errcode = '42501'; end if;
  perform set_config('app.tarif_meme_jour', 'oui', true);
  for x in select * from jsonb_array_elements(coalesce(p_prix, '[]')) loop
    v_type := (x->>'type_travail_id')::uuid;
    v_cout := (x->>'cout_cents')::bigint;
    if v_cout is null or v_cout <= 0 then raise exception 'Prix invalide' using errcode = 'P0001'; end if;
    if not exists (select 1 from public.types_travaux where id = v_type) then raise exception 'Travail inconnu' using errcode = 'P0001'; end if;
    if not exists (select 1 from public.travaux_sous_traitants where fournisseur_id = v_f and type_travail_id = v_type) then
      if v_st then raise exception 'Ce travail n''est pas confié à ce sous-traitant' using errcode = '42501'; end if;
      insert into public.travaux_sous_traitants (fournisseur_id, type_travail_id) values (v_f, v_type);
    end if;
    v_ancien := public.hvac_cout_installation(v_f, v_type, v_jour);
    if v_ancien is not distinct from v_cout then continue; end if;
    insert into public.tarifs_sous_traitants (fournisseur_id, type_travail_id, cout_cents, en_vigueur_du, notes)
    values (v_f, v_type, v_cout, v_jour, case when v_st then 'Modifié par le sous-traitant' else 'Modifié par Belleflamme' end)
    on conflict (fournisseur_id, type_travail_id, en_vigueur_du) do update set cout_cents = excluded.cout_cents, notes = excluded.notes;
    n := n + 1; v_types := v_types || v_type;
    insert into public.notifications (destinataire_employe_id, type, titre, message, lien)
    select distinct e.vendeur_id, 'prix_sous_traitant',
           'Nouveau prix d''installation',
           format('%s : %s passe de %s $ à %s $. Ton devis #%s garde l''ancien prix%s ; au renouvellement, le nouveau prix s''appliquera.',
                  (select nom from public.fournisseurs where id = v_f), e.travail,
                  to_char(e.cout_cents / 100.0, 'FM999G990D00'), to_char(v_cout / 100.0, 'FM999G990D00'), e.numero,
                  case when e.honorer_jusqu is not null then ' jusqu''au ' || to_char(e.honorer_jusqu, 'YYYY-MM-DD') else '' end),
           '/devis?id=' || e.devis_id
      from app.engagements(v_f, array[v_type]) e where e.vendeur_id is not null;
  end loop;
  perform set_config('app.tarif_meme_jour', '', true);
  if n > 0 then
    insert into public.notifications (destinataire_employe_id, type, titre, message, lien)
    select emp.id, 'prix_sous_traitant', 'Liste de prix modifiée',
           (select nom from public.fournisseurs where id = v_f) || ' a modifié ' || n || ' prix.', '/mes-prix?fournisseur=' || v_f
      from public.employes emp where emp.actif and emp.role = 'Admin tout';
  end if;
  v_version := app.versionner_liste(v_f, case when v_st then 'Prix modifiés par le sous-traitant' else 'Prix modifiés par Belleflamme' end);
  return jsonb_build_object('changes', n, 'version', v_version,
                            'engagements', (select coalesce(jsonb_agg(to_jsonb(e)), '[]') from app.engagements(v_f, v_types) e));
end $$;

-- Travaux confiés : ajout et retrait en une seule opération, une seule version au registre.
create or replace function public.hvac_confier_travaux(p_fournisseur uuid, p_ajouter uuid[] default '{}', p_retirer uuid[] default '{}')
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_a integer; v_r integer;
begin
  if not (app.est_admin() or app.est_planification()) then raise exception 'Réservé à la planification' using errcode = '42501'; end if;
  insert into public.travaux_sous_traitants (fournisseur_id, type_travail_id)
  select p_fournisseur, unnest(coalesce(p_ajouter, '{}')) on conflict do nothing;
  get diagnostics v_a = row_count;
  delete from public.travaux_sous_traitants where fournisseur_id = p_fournisseur and type_travail_id = any(coalesce(p_retirer, '{}'));
  get diagnostics v_r = row_count;
  return jsonb_build_object('ajoutes', v_a, 'retires', v_r,
                            'version', app.versionner_liste(p_fournisseur, 'Travaux confiés modifiés par Belleflamme'));
end $$;
revoke all on function public.hvac_confier_travaux(uuid, uuid[], uuid[]) from public, anon;
grant execute on function public.hvac_confier_travaux(uuid, uuid[], uuid[]) to authenticated;

-- Point d'entrée pour les autres chemins (ex. tarif daté ajouté par l'admin) : version si la liste a changé.
create or replace function public.hvac_versionner_liste(p_fournisseur uuid, p_motif text default 'Liste modifiée')
returns integer language plpgsql security definer set search_path = public as $$
begin
  if not (app.est_admin() or app.est_planification() or app.mon_fournisseur() = p_fournisseur) then
    raise exception 'Accès refusé' using errcode = '42501';
  end if;
  return app.versionner_liste(p_fournisseur, left(coalesce(p_motif, 'Liste modifiée'), 120));
end $$;
revoke all on function public.hvac_versionner_liste(uuid, text) from public, anon;
grant execute on function public.hvac_versionner_liste(uuid, text) to authenticated;

-- Reprise : première version pour chaque sous-traitant qui a déjà des travaux confiés
do $$
declare f uuid;
begin
  for f in select distinct fournisseur_id from public.travaux_sous_traitants loop
    perform app.versionner_liste(f, 'Première version (reprise de la liste existante)');
  end loop;
end $$;
