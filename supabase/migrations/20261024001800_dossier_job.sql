-- Dossier de job LogisVert (ADR-084, demande de Simon) : pour CHAQUE job, extras ou pas, le sous-traitant inscrit
-- le numéro de certificat AHRI du système, chaque appareil installé (marque, modèle, numéro de série) et ses photos :
-- plaque signalétique de chaque appareil extérieur et intérieur, et chaque appareil installé.
-- Sans dossier complet : pas de facture finale du sous-traitant, et personne ne passe le projet à « Terminé ».
-- Conservation (Loi 25, décision de Simon) : photos gardées 5 ans après le passage à « Terminé », puis purgées.
-- Exigences LogisVert vérifiées dans des sources secondaires seulement (guide officiel non consulté) : à valider.

-- 1. Numéro AHRI du système (combinaison extérieure + intérieure), sur le projet
alter table public.projets add column numero_ahri text check (numero_ahri is null or numero_ahri ~ '^[0-9]{5,12}$');

-- 2. Photos de la job (bucket privé, même modèle que les photos d'extras)
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('jobs-photos', 'jobs-photos', false, 5242880, array['image/jpeg','image/png','image/webp'])
on conflict (id) do nothing;

create table public.projet_photos (
  id              uuid primary key default gen_random_uuid(),
  projet_id       uuid not null references public.projets(id),
  equipement_id   uuid references public.equipements_installes(id),
  categorie       text not null check (categorie in ('plaque','installe','autre')),
  check (categorie = 'autre' or equipement_id is not null),
  chemin          text not null unique,              -- {projet}/{uuid}.{ext} dans le bucket jobs-photos
  type_mime       text not null check (type_mime in ('image/jpeg','image/png','image/webp')),
  taille_octets   integer not null check (taille_octets > 0 and taille_octets <= 5242880),
  statut          text not null default 'prevue' check (statut in ('prevue','televersee','retiree','purgee')),
  ajoute_par_auth uuid not null default auth.uid(),
  purge_le        timestamptz,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
call app.preparer_table('public.projet_photos', false);
create index projet_photos_projet on public.projet_photos (projet_id) where statut = 'televersee';
alter table public.projet_photos enable row level security;
create policy lecture on public.projet_photos for select to authenticated using (app.est_interne() and app.voit_projet(projet_id));
create trigger trg_audit_projet_photos after insert or update on public.projet_photos for each row execute function app.audit();

-- Les photos d'extras peuvent aussi être purgées
alter table public.projet_extra_photos drop constraint projet_extra_photos_statut_check;
alter table public.projet_extra_photos add constraint projet_extra_photos_statut_check check (statut in ('prevue','televersee','retiree','purgee'));
alter table public.projet_extra_photos add column purge_le timestamptz;

create or replace function app.photo_job_ecriture(p_nom text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.projet_photos where chemin = p_nom and statut = 'prevue' and ajoute_par_auth = auth.uid())
$$;
create or replace function app.photo_job_lecture(p_nom text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.projet_photos ph join public.projets p on p.id = ph.projet_id
                  where ph.chemin = p_nom and ph.statut = 'televersee'
                    and coalesce((app.est_interne() and app.voit_projet(p.id)) or p.sous_traitant_id = app.mon_fournisseur(), false))
$$;
create policy jobs_photos_televerser on storage.objects for insert to authenticated
  with check (bucket_id = 'jobs-photos' and app.photo_job_ecriture(name));
create policy jobs_photos_lire on storage.objects for select to authenticated
  using (bucket_id = 'jobs-photos' and app.photo_job_lecture(name));

-- 3. Le dossier : ce qui manque (liste vide = complet). Appareils comptés : extérieur, intérieur, fournaise.
create or replace function app.dossier_job(p_projet uuid) returns text[]
language plpgsql stable security definer set search_path = public as $$
declare p public.projets%rowtype; m text[] := '{}'; e record; n_ext int; n_int int;
begin
  select * into p from public.projets where id = p_projet;
  if p.numero_ahri is null then m := array_append(m, 'numéro AHRI du système'); end if;
  select count(*) filter (where role = 'exterieur'), count(*) filter (where role in ('interieur','fournaise'))
    into n_ext, n_int from public.equipements_installes where projet_id = p_projet and actif;
  if n_ext = 0 then m := array_append(m, 'au moins un appareil extérieur (marque, modèle, numéro de série)'); end if;
  if n_int = 0 then m := array_append(m, 'au moins un appareil intérieur (marque, modèle, numéro de série)'); end if;
  for e in select ei.id, ei.role, ei.modele, ei.numero_serie from public.equipements_installes ei
            where ei.projet_id = p_projet and ei.actif and ei.role in ('exterieur','interieur','fournaise') order by ei.created_at loop
    if not exists (select 1 from public.projet_photos where equipement_id = e.id and categorie = 'plaque' and statut in ('televersee','purgee')) then
      m := array_append(m, format('photo de la plaque : %s %s', e.modele, coalesce(e.numero_serie, '')));
    end if;
    if not exists (select 1 from public.projet_photos where equipement_id = e.id and categorie = 'installe' and statut in ('televersee','purgee')) then
      m := array_append(m, format('photo de l''appareil installé : %s %s', e.modele, coalesce(e.numero_serie, '')));
    end if;
  end loop;
  return m;
end $$;

-- Ouvert au sous-traitant : dépôt reçu, pas encore facturé, facture finale pas soumise
create or replace function app.dossier_ouvert(p_projet uuid) returns public.projets
language plpgsql stable security definer set search_path = public as $$
declare p public.projets%rowtype;
begin
  select * into p from public.projets where id = p_projet;
  if p.id is null then raise exception 'Job introuvable' using errcode = '42501'; end if;
  if not coalesce(p.sous_traitant_id = app.mon_fournisseur() or app.est_admin() or app.est_planification(), false) then
    raise exception 'Job introuvable' using errcode = '42501';
  end if;
  if app.mon_fournisseur() is not null then
    if p.statut not in ('a_planifier','planifie','en_cours','termine') then raise exception 'Dossier fermé pour cette job (étape : %)', p.statut using errcode = 'P0001'; end if;
    if p.facture_st_soumise_le is not null then raise exception 'Facture finale déjà soumise : dossier figé' using errcode = 'P0001'; end if;
  end if;
  return p;
end $$;

-- 4. Saisie : AHRI, appareils, photos (sous-traitant ; Simon, Mike et la planification peuvent corriger)
create or replace function public.hvac_job_ahri(p_projet uuid, p_numero text) returns void
language plpgsql security definer set search_path = public as $$
declare v text := nullif(regexp_replace(coalesce(p_numero, ''), '\s', '', 'g'), '');
begin
  perform app.dossier_ouvert(p_projet);
  if v is null or v !~ '^[0-9]{5,12}$' then raise exception 'Numéro AHRI : 5 à 12 chiffres' using errcode = 'P0001'; end if;
  update public.projets set numero_ahri = v where id = p_projet;
  update public.equipements_installes set ahri = v where projet_id = p_projet and actif;   -- même certificat pour le système
end $$;

create or replace function public.hvac_job_equipement_ajouter(p_projet uuid, p jsonb) returns uuid
language plpgsql security definer set search_path = public as $$
declare pr public.projets%rowtype; v_id uuid;
  v_role text := p->>'role'; v_marque text := nullif(trim(p->>'marque'), ''); v_modele text := nullif(trim(p->>'modele'), '');
  v_serie text := nullif(upper(regexp_replace(coalesce(p->>'numero_serie', ''), '\s', '', 'g')), '');
begin
  pr := app.dossier_ouvert(p_projet);
  if v_role not in ('exterieur','interieur','fournaise','autre') then raise exception 'Type d''appareil : extérieur, intérieur, fournaise ou autre' using errcode = 'P0001'; end if;
  if v_marque is null or v_modele is null or v_serie is null then raise exception 'Marque, modèle et numéro de série requis' using errcode = 'P0001'; end if;
  if exists (select 1 from public.equipements_installes where lower(marque) = lower(v_marque) and lower(numero_serie) = lower(v_serie)) then
    raise exception 'Ce numéro de série est déjà inscrit (%, %)', v_marque, v_serie using errcode = 'P0001';
  end if;
  insert into public.equipements_installes (projet_id, client_id, site_id, role, marque, modele, numero_serie, ahri, installe_le)
  values (pr.id, pr.client_id, pr.site_id, v_role, v_marque, v_modele, v_serie, pr.numero_ahri, (now() at time zone 'America/Toronto')::date)
  returning id into v_id;
  return v_id;
end $$;

-- Retirer un appareil inscrit par erreur (désactivé, pas effacé)
create or replace function public.hvac_job_equipement_retirer(p_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare e public.equipements_installes%rowtype;
begin
  select * into e from public.equipements_installes where id = p_id;
  if e.id is null or e.projet_id is null then raise exception 'Appareil introuvable' using errcode = '42501'; end if;
  perform app.dossier_ouvert(e.projet_id);
  update public.equipements_installes set actif = false where id = p_id;
  update public.projet_photos set statut = 'retiree' where equipement_id = p_id and statut in ('prevue','televersee');
end $$;

create or replace function public.hvac_job_photo_preparer(p_projet uuid, p_equipement uuid, p_categorie text, p_type text, p_taille integer) returns jsonb
language plpgsql security definer set search_path = public as $$
declare pr public.projets%rowtype; v_chemin text; v_id uuid;
begin
  pr := app.dossier_ouvert(p_projet);
  if p_categorie not in ('plaque','installe','autre') then raise exception 'Catégorie de photo inconnue' using errcode = 'P0001'; end if;
  if p_equipement is null and p_categorie <> 'autre' then raise exception 'Choisis l''appareil de la photo' using errcode = 'P0001'; end if;
  if p_equipement is not null and not exists (select 1 from public.equipements_installes where id = p_equipement and projet_id = pr.id and actif) then
    raise exception 'Appareil introuvable sur cette job' using errcode = 'P0001';
  end if;
  if p_type not in ('image/jpeg','image/png','image/webp') then raise exception 'Photo : JPEG, PNG ou WebP' using errcode = 'P0001'; end if;
  if p_taille is null or p_taille <= 0 or p_taille > 5242880 then raise exception 'Photo trop lourde (5 Mo au plus)' using errcode = 'P0001'; end if;
  if (select count(*) from public.projet_photos where projet_id = pr.id and statut in ('prevue','televersee')) >= 40 then
    raise exception '40 photos au plus par job' using errcode = 'P0001';
  end if;
  v_chemin := format('%s/%s.%s', pr.id, gen_random_uuid(), case p_type when 'image/png' then 'png' when 'image/webp' then 'webp' else 'jpg' end);
  insert into public.projet_photos (projet_id, equipement_id, categorie, chemin, type_mime, taille_octets)
  values (pr.id, p_equipement, p_categorie, v_chemin, p_type, p_taille) returning id into v_id;
  return jsonb_build_object('id', v_id, 'chemin', v_chemin);
end $$;

create or replace function public.hvac_job_photo_confirmer(p_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare ph public.projet_photos%rowtype;
begin
  select * into ph from public.projet_photos where id = p_id;
  if ph.id is null or ph.ajoute_par_auth is distinct from auth.uid() or ph.statut <> 'prevue' then raise exception 'Photo introuvable' using errcode = '42501'; end if;
  if not exists (select 1 from storage.objects where bucket_id = 'jobs-photos' and name = ph.chemin) then raise exception 'Fichier non reçu' using errcode = 'P0001'; end if;
  update public.projet_photos set statut = 'televersee' where id = p_id;
end $$;

create or replace function public.hvac_job_photo_retirer(p_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare ph public.projet_photos%rowtype;
begin
  select * into ph from public.projet_photos where id = p_id;
  if ph.id is null then raise exception 'Photo introuvable' using errcode = '42501'; end if;
  perform app.dossier_ouvert(ph.projet_id);
  update public.projet_photos set statut = 'retiree' where id = p_id and statut = 'televersee';
end $$;

-- Dossier complet d'une job : AHRI, appareils et leurs photos, ce qui manque (sous-traitant de la job, ou Belleflamme)
create or replace function public.hvac_job_dossier(p_projet uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare p public.projets%rowtype;
begin
  select * into p from public.projets where id = p_projet;
  if p.id is null or not coalesce((app.est_interne() and app.voit_projet(p.id)) or p.sous_traitant_id = app.mon_fournisseur(), false) then
    raise exception 'Job introuvable' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'numero_ahri', p.numero_ahri,
    'equipements', coalesce((select jsonb_agg(jsonb_build_object('id', e.id, 'role', e.role, 'marque', e.marque, 'modele', e.modele, 'numero_serie', e.numero_serie) order by e.created_at)
                               from public.equipements_installes e where e.projet_id = p.id and e.actif), '[]'::jsonb),
    'photos', coalesce((select jsonb_agg(jsonb_build_object('id', ph.id, 'equipement_id', ph.equipement_id, 'categorie', ph.categorie, 'chemin', ph.chemin) order by ph.created_at)
                          from public.projet_photos ph where ph.projet_id = p.id and ph.statut = 'televersee'), '[]'::jsonb),
    'manques', to_jsonb(app.dossier_job(p.id)),
    'purgees', (select count(*) from public.projet_photos ph where ph.projet_id = p.id and ph.statut = 'purgee'));
end $$;

revoke all on function public.hvac_job_ahri(uuid, text), public.hvac_job_equipement_ajouter(uuid, jsonb), public.hvac_job_equipement_retirer(uuid),
  public.hvac_job_photo_preparer(uuid, uuid, text, text, integer), public.hvac_job_photo_confirmer(uuid), public.hvac_job_photo_retirer(uuid),
  public.hvac_job_dossier(uuid) from public, anon;
grant execute on function public.hvac_job_ahri(uuid, text), public.hvac_job_equipement_ajouter(uuid, jsonb), public.hvac_job_equipement_retirer(uuid),
  public.hvac_job_photo_preparer(uuid, uuid, text, text, integer), public.hvac_job_photo_confirmer(uuid), public.hvac_job_photo_retirer(uuid),
  public.hvac_job_dossier(uuid) to authenticated;

-- 5. Blocages : « Terminé » (et au-delà) exige le dossier complet pour une job de sous-traitant ; date de fin pour la conservation
create or replace function app.projet_transition() returns trigger
language plpgsql as $$
declare
  ordre text[] := array['attente_paiement','a_planifier','planifie','en_cours','termine','facture','ferme'];
  a int := array_position(ordre, old.statut); n int := array_position(ordre, new.statut); v_manques text[];
begin
  if new.statut = old.statut then return new; end if;
  if new.statut = 'annule' then
    if old.statut in ('facture','ferme') then raise exception 'Un projet facturé ne s''annule pas' using errcode = 'P0001'; end if;
    return new;
  end if;
  if old.statut = 'annule' then raise exception 'Un projet annulé ne revient pas' using errcode = 'P0001'; end if;
  if n < a - 1 then raise exception 'Un projet recule d''une étape à la fois' using errcode = 'P0001'; end if;
  if n >= array_position(ordre, 'termine') and a < array_position(ordre, 'termine') and new.sous_traitant_id is not null then
    v_manques := app.dossier_job(new.id);
    if cardinality(v_manques) > 0 then
      raise exception 'Dossier LogisVert incomplet : %', array_to_string(v_manques, ' ; ') using errcode = 'P0001';
    end if;
  end if;
  if new.statut = 'termine' then new.installation_terminee_le := coalesce(new.installation_terminee_le, now()); end if;
  return new;
end $$;

-- Facture finale : dossier complet exigé (en plus des extras décidés)
create or replace function public.hvac_facture_finale(p_projet uuid) returns bigint
language plpgsql security definer set search_path = public as $$
declare pr public.projets%rowtype; v_total bigint; v_manques text[];
begin
  pr := app.projet_extras_ouvert(p_projet);
  if pr.statut not in ('en_cours','termine') then raise exception 'La facture finale se soumet quand la job est en cours ou terminée' using errcode = 'P0001'; end if;
  if exists (select 1 from public.projet_extras where projet_id = pr.id and statut in ('brouillon','soumis')) then
    raise exception 'Des extras sont en brouillon ou en attente d''approbation' using errcode = 'P0001';
  end if;
  v_manques := app.dossier_job(pr.id);
  if cardinality(v_manques) > 0 then
    raise exception 'Dossier LogisVert incomplet : %', array_to_string(v_manques, ' ; ') using errcode = 'P0001';
  end if;
  select coalesce((select sum(round(quantite * cout_cents)) from public.projet_lignes where projet_id = pr.id and type_ligne = 'installation'), 0)
       + coalesce((select sum(round(quantite * cout_cents)) from public.projet_extras where projet_id = pr.id and statut = 'approuve'), 0)
    into v_total;
  update public.projets set facture_st_soumise_le = now(), facture_st_total_cents = v_total where id = pr.id;
  perform app.notifier_planification('facture_st', 'Facture finale du sous-traitant | ' || coalesce(pr.code_projet, ''),
    format('%s : %s $ avant taxes (installation et extras approuvés). À payer dans l''app de Mike.',
           (select nom from public.fournisseurs where id = pr.sous_traitant_id), to_char(v_total / 100.0, 'FM999G999G990D00')), '/macro');
  return v_total;
end $$;

-- 6. Conservation : 5 ans après « Terminé ». Pour la tâche planifiée seulement (clé service_role, côté serveur).
create or replace function public.hvac_photos_a_purger(p_limite integer default 500)
returns table (source text, id uuid, bucket text, chemin text)
language sql stable security definer set search_path = public as $$
  (select 'job', ph.id, 'jobs-photos', ph.chemin from public.projet_photos ph join public.projets p on p.id = ph.projet_id
    where ph.statut in ('televersee','retiree','prevue') and p.installation_terminee_le < now() - interval '5 years')
  union all
  (select 'extra', ph.id, 'extras-photos', ph.chemin from public.projet_extra_photos ph
     join public.projet_extras x on x.id = ph.extra_id join public.projets p on p.id = x.projet_id
    where ph.statut in ('televersee','retiree','prevue') and p.installation_terminee_le < now() - interval '5 years')
  limit p_limite
$$;
create or replace function public.hvac_photos_purgees(p_job uuid[], p_extra uuid[]) returns integer
language plpgsql security definer set search_path = public as $$
declare n integer; m integer;
begin
  update public.projet_photos set statut = 'purgee', purge_le = now() where id = any(coalesce(p_job, '{}')) and statut <> 'purgee';
  get diagnostics n = row_count;
  update public.projet_extra_photos set statut = 'purgee', purge_le = now() where id = any(coalesce(p_extra, '{}')) and statut <> 'purgee';
  get diagnostics m = row_count;
  return n + m;
end $$;
revoke all on function public.hvac_photos_a_purger(integer), public.hvac_photos_purgees(uuid[], uuid[]) from public, anon, authenticated;
grant execute on function public.hvac_photos_a_purger(integer), public.hvac_photos_purgees(uuid[], uuid[]) to service_role;

-- 7. Macro : état du dossier
create or replace view public.projets_macro_v with (security_invoker = true) as
select p.id, p.code_projet, p.statut, p.succursale_code, p.client_id, trim(coalesce(c.prenom || ' ', '') || c.nom) as client_nom,
       coalesce(s.ville, l.ville) as ville, p.vendeur_id, trim(e.prenom || ' ' || e.nom) as vendeur_nom, p.lead_id, p.devis_numero_mike,
       p.montant_avant_taxes_cents, p.type_systeme, p.signe_le, p.installation_prevue_le, p.created_at, p.updated_at,
       p.sous_traitant_id, f.nom as sous_traitant_nom,
       (select sum(round(pl.quantite * pl.cout_cents))::bigint from public.projet_lignes pl
         where pl.projet_id = p.id and pl.type_ligne = 'installation') as cout_installation_cents,
       (select count(*)::int from public.projet_extras x where x.projet_id = p.id and x.statut = 'soumis') as extras_a_approuver,
       (select sum(round(x.quantite * x.cout_cents))::bigint from public.projet_extras x where x.projet_id = p.id and x.statut = 'approuve') as extras_approuves_cents,
       p.facture_st_soumise_le, p.facture_st_total_cents,
       p.numero_ahri, case when p.sous_traitant_id is null then null else cardinality(app.dossier_job(p.id)) end as dossier_manques
  from public.projets p
  join public.clients c on c.id = p.client_id
  left join public.sites s on s.id = p.site_id
  left join public.leads l on l.id = p.lead_id
  left join public.employes e on e.id = p.vendeur_id
  left join public.fournisseurs f on f.id = p.sous_traitant_id
 where p.division = 'Ventilation';
