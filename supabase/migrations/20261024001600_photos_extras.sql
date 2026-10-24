-- Photos des extras (ADR-082) : preuve d'un oubli ou d'un imprévu, jointe par le sous-traitant à son brouillon.
-- Bucket PRIVÉ « extras-photos » (Supabase Storage). Aucune clé service_role : la fonction serverless téléverse et
-- signe les URL avec le jeton de l'utilisateur ; la RLS de storage.objects décide (doc Supabase, Storage Access Control :
-- INSERT pour téléverser, SELECT pour une URL signée). Une photo envoyée pour approbation ne se change plus.
-- Loi 25 : les photos montrent la maison du client ; jamais publiques, URL signées de 10 minutes.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('extras-photos', 'extras-photos', false, 5242880, array['image/jpeg','image/png','image/webp'])
on conflict (id) do nothing;

create table public.projet_extra_photos (
  id              uuid primary key default gen_random_uuid(),
  extra_id        uuid not null references public.projet_extras(id),
  chemin          text not null unique,              -- {projet}/{extra}/{uuid}.{ext} dans le bucket extras-photos
  type_mime       text not null check (type_mime in ('image/jpeg','image/png','image/webp')),
  taille_octets   integer not null check (taille_octets > 0 and taille_octets <= 5242880),
  statut          text not null default 'prevue' check (statut in ('prevue','televersee','retiree')),
  ajoute_par_auth uuid not null default auth.uid(),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
call app.preparer_table('public.projet_extra_photos', false);
create index projet_extra_photos_extra on public.projet_extra_photos (extra_id) where statut = 'televersee';
alter table public.projet_extra_photos enable row level security;
create policy lecture on public.projet_extra_photos for select to authenticated
  using (app.est_interne() and exists (select 1 from public.projet_extras x where x.id = extra_id and app.voit_projet(x.projet_id)));
create trigger trg_audit_projet_extra_photos after insert or update on public.projet_extra_photos for each row execute function app.audit();

-- Droits sur les fichiers (appelés par les politiques de storage.objects)
create or replace function app.photo_extra_ecriture(p_nom text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.projet_extra_photos where chemin = p_nom and statut = 'prevue' and ajoute_par_auth = auth.uid())
$$;
create or replace function app.photo_extra_lecture(p_nom text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.projet_extra_photos ph join public.projet_extras x on x.id = ph.extra_id
                  where ph.chemin = p_nom and ph.statut = 'televersee'
                    and coalesce((app.est_interne() and app.voit_projet(x.projet_id)) or x.fournisseur_id = app.mon_fournisseur(), false))
$$;
create policy extras_photos_televerser on storage.objects for insert to authenticated
  with check (bucket_id = 'extras-photos' and app.photo_extra_ecriture(name));
create policy extras_photos_lire on storage.objects for select to authenticated
  using (bucket_id = 'extras-photos' and app.photo_extra_lecture(name));

-- Le sous-traitant prépare une photo sur SON brouillon : 5 photos au plus par extra
create or replace function public.hvac_extra_photo_preparer(p_extra uuid, p_type text, p_taille integer) returns jsonb
language plpgsql security definer set search_path = public as $$
declare x public.projet_extras%rowtype; v_chemin text; v_id uuid;
begin
  select * into x from public.projet_extras where id = p_extra;
  if x.id is null or x.fournisseur_id is distinct from app.mon_fournisseur() then raise exception 'Extra introuvable' using errcode = '42501'; end if;
  perform app.projet_extras_ouvert(x.projet_id);
  if x.statut <> 'brouillon' then raise exception 'Les photos s''ajoutent au brouillon, avant l''envoi pour approbation' using errcode = 'P0001'; end if;
  if p_type not in ('image/jpeg','image/png','image/webp') then raise exception 'Photo : JPEG, PNG ou WebP' using errcode = 'P0001'; end if;
  if p_taille is null or p_taille <= 0 or p_taille > 5242880 then raise exception 'Photo trop lourde (5 Mo au plus)' using errcode = 'P0001'; end if;
  if (select count(*) from public.projet_extra_photos where extra_id = x.id and statut <> 'retiree') >= 5 then
    raise exception '5 photos au plus par extra' using errcode = 'P0001';
  end if;
  v_chemin := format('%s/%s/%s.%s', x.projet_id, x.id, gen_random_uuid(), case p_type when 'image/png' then 'png' when 'image/webp' then 'webp' else 'jpg' end);
  insert into public.projet_extra_photos (extra_id, chemin, type_mime, taille_octets) values (x.id, v_chemin, p_type, p_taille) returning id into v_id;
  return jsonb_build_object('id', v_id, 'chemin', v_chemin);
end $$;

-- Confirmée seulement si le fichier est bien dans le bucket
create or replace function public.hvac_extra_photo_confirmer(p_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare ph public.projet_extra_photos%rowtype;
begin
  select * into ph from public.projet_extra_photos where id = p_id;
  if ph.id is null or ph.ajoute_par_auth is distinct from auth.uid() or ph.statut <> 'prevue' then raise exception 'Photo introuvable' using errcode = '42501'; end if;
  if not exists (select 1 from storage.objects where bucket_id = 'extras-photos' and name = ph.chemin) then
    raise exception 'Fichier non reçu' using errcode = 'P0001';
  end if;
  update public.projet_extra_photos set statut = 'televersee' where id = p_id;
end $$;

-- Retirer une photo du brouillon (le fichier reste, pour la trace ; il n'est plus montré)
create or replace function public.hvac_extra_photo_retirer(p_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare ph public.projet_extra_photos%rowtype; x public.projet_extras%rowtype;
begin
  select * into ph from public.projet_extra_photos where id = p_id;
  select * into x from public.projet_extras where id = ph.extra_id;
  if ph.id is null or x.fournisseur_id is distinct from app.mon_fournisseur() then raise exception 'Photo introuvable' using errcode = '42501'; end if;
  perform app.projet_extras_ouvert(x.projet_id);
  if x.statut <> 'brouillon' then raise exception 'Une photo envoyée pour approbation ne se retire plus' using errcode = 'P0001'; end if;
  update public.projet_extra_photos set statut = 'retiree' where id = p_id;
end $$;

-- Photos d'un extra (Belleflamme selon le projet, ou le sous-traitant de l'extra)
create or replace function public.hvac_extra_photos(p_extra uuid) returns table (id uuid, chemin text)
language plpgsql stable security definer set search_path = public as $$
declare x public.projet_extras%rowtype;
begin
  select * into x from public.projet_extras pe where pe.id = p_extra;
  if x.id is null or not coalesce((app.est_interne() and app.voit_projet(x.projet_id)) or x.fournisseur_id = app.mon_fournisseur(), false) then
    raise exception 'Extra introuvable' using errcode = '42501';
  end if;
  return query select ph.id, ph.chemin from public.projet_extra_photos ph where ph.extra_id = x.id and ph.statut = 'televersee' order by ph.created_at;
end $$;

revoke all on function public.hvac_extra_photo_preparer(uuid, text, integer), public.hvac_extra_photo_confirmer(uuid),
  public.hvac_extra_photo_retirer(uuid), public.hvac_extra_photos(uuid) from public, anon;
grant execute on function public.hvac_extra_photo_preparer(uuid, text, integer), public.hvac_extra_photo_confirmer(uuid),
  public.hvac_extra_photo_retirer(uuid), public.hvac_extra_photos(uuid) to authenticated;

-- Nombre de photos dans la file d'approbation (colonne ajoutée à la fin)
create or replace view public.extras_v with (security_invoker = true) as
select x.id, x.projet_id, p.code_projet, p.statut as projet_statut, p.succursale_code, coalesce(s.ville, l.ville) as ville,
       p.vendeur_id, trim(e.prenom || ' ' || e.nom) as vendeur_nom, x.fournisseur_id, f.nom as sous_traitant_nom,
       x.type_travail_id, x.description, x.quantite, x.cout_cents, round(x.quantite * x.cout_cents)::bigint as total_cents,
       x.hors_liste, x.justification, x.cause, x.note, x.statut, x.soumis_le, x.decide_le, x.raison_refus,
       trim(d.prenom || ' ' || d.nom) as decide_par_nom, x.created_at,
       (select count(*)::int from public.projet_extra_photos ph where ph.extra_id = x.id and ph.statut = 'televersee') as nb_photos
  from public.projet_extras x
  join public.projets p on p.id = x.projet_id
  join public.fournisseurs f on f.id = x.fournisseur_id
  left join public.sites s on s.id = p.site_id
  left join public.leads l on l.id = p.lead_id
  left join public.employes e on e.id = p.vendeur_id
  left join public.employes d on d.id = x.decide_par
 where x.statut <> 'retire';

-- Mes jobs : nombre de photos par extra
create or replace function public.hvac_mes_projets(p_fournisseur uuid default null)
returns table (id uuid, code_projet text, statut text, ville text, type_systeme text, signe_le timestamptz,
               installation_prevue_le timestamptz, client_nom text, client_telephone text, adresse text,
               lignes jsonb, total_cents bigint, extras jsonb, extras_approuves_cents bigint, extras_en_attente_cents bigint,
               total_final_cents bigint, facture_soumise_le timestamptz, extras_ouverts boolean)
language plpgsql stable security definer set search_path = public as $$
declare v_f uuid := coalesce(app.mon_fournisseur(), case when app.est_admin() or app.est_planification() then p_fournisseur end);
begin
  if v_f is null then raise exception 'Sous-traitant requis' using errcode = '42501'; end if;
  return query
  with base as (
    select p.*, coalesce(s.ville, ld.ville) as v_ville, s.adresse as v_adresse, c.telephone as v_tel,
           trim(coalesce(c.prenom || ' ', '') || c.nom) as v_client,
           coalesce((select sum(round(pl.quantite * pl.cout_cents))::bigint from public.projet_lignes pl
                      where pl.projet_id = p.id and pl.type_ligne = 'installation'), 0) as v_install,
           coalesce((select sum(round(x.quantite * x.cout_cents))::bigint from public.projet_extras x
                      where x.projet_id = p.id and x.statut = 'approuve'), 0) as v_ext_ok,
           coalesce((select sum(round(x.quantite * x.cout_cents))::bigint from public.projet_extras x
                      where x.projet_id = p.id and x.statut in ('brouillon','soumis')), 0) as v_ext_att
      from public.projets p
      join public.clients c on c.id = p.client_id
      left join public.sites s on s.id = p.site_id
      left join public.leads ld on ld.id = p.lead_id
     where p.sous_traitant_id = v_f and p.statut not in ('annule','ferme'))
  select b.id, b.code_projet, b.statut, b.v_ville, b.type_systeme, b.signe_le, b.installation_prevue_le,
         case when b.statut <> 'attente_paiement' then b.v_client end,
         case when b.statut <> 'attente_paiement' then b.v_tel end,
         case when b.statut <> 'attente_paiement' then b.v_adresse end,
         coalesce((select jsonb_agg(jsonb_build_object('type_ligne', pl.type_ligne, 'description', pl.description, 'quantite', pl.quantite,
                     'prix_cents', case when pl.type_ligne = 'installation' then pl.cout_cents else 0 end,
                     'total_cents', case when pl.type_ligne = 'installation' then round(pl.quantite * pl.cout_cents)::bigint else 0 end)
                     order by pl.position)
                     from public.projet_lignes pl where pl.projet_id = b.id), '[]'::jsonb),
         b.v_install,
         coalesce((select jsonb_agg(jsonb_build_object('id', x.id, 'description', x.description, 'quantite', x.quantite, 'prix_cents', x.cout_cents,
                     'total_cents', round(x.quantite * x.cout_cents)::bigint, 'hors_liste', x.hors_liste, 'cause', x.cause,
                     'justification', x.justification, 'note', x.note, 'statut', x.statut, 'raison_refus', x.raison_refus,
                     'nb_photos', (select count(*) from public.projet_extra_photos ph where ph.extra_id = x.id and ph.statut = 'televersee')) order by x.created_at)
                     from public.projet_extras x where x.projet_id = b.id and x.statut <> 'retire'), '[]'::jsonb),
         b.v_ext_ok, b.v_ext_att,
         coalesce(b.facture_st_total_cents, b.v_install + b.v_ext_ok),
         b.facture_st_soumise_le,
         b.statut in ('a_planifier','planifie','en_cours','termine') and b.facture_st_soumise_le is null
    from base b
   order by b.signe_le desc nulls last;
end $$;
revoke all on function public.hvac_mes_projets(uuid) from public, anon;
grant execute on function public.hvac_mes_projets(uuid) to authenticated;
