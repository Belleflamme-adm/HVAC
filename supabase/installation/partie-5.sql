-- Installation HVAC Belleflamme | partie 5 sur 6 | à coller dans Supabase > SQL Editor > Run
-- Généré depuis supabase/migrations (commentaires retirés). Les parties s'exécutent DANS L'ORDRE, une seule fois.

-- ===== 20261024001500_extras_sous_traitant.sql =====
create table public.projet_extras (
  id              uuid primary key default gen_random_uuid(),
  projet_id       uuid not null references public.projets(id),
  fournisseur_id  uuid not null references public.fournisseurs(id),
  division        text not null default 'Ventilation' references public.divisions(nom),
  type_travail_id uuid references public.types_travaux(id),            -- null = hors liste
  description     text not null check (length(trim(description)) > 0),
  quantite        numeric(10,2) not null default 1 check (quantite > 0),
  cout_cents      bigint not null check (cout_cents > 0),              -- prix de sa liste (figé) ou prix proposé hors liste
  hors_liste      boolean generated always as (type_travail_id is null) stored,
  justification   text,
  check (type_travail_id is not null or length(trim(coalesce(justification, ''))) >= 10),
  cause           text not null check (cause in ('oubli_vendeur','imprevu_chantier','demande_client','autre')),
  note            text,
  statut          text not null default 'brouillon' check (statut in ('brouillon','soumis','approuve','refuse','retire')),
  soumis_le       timestamptz,
  decide_par      uuid references public.employes(id),
  decide_le       timestamptz,
  raison_refus    text,
  check (statut <> 'refuse' or length(trim(coalesce(raison_refus, ''))) > 0),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
call app.preparer_table('public.projet_extras');
create index projet_extras_projet on public.projet_extras (projet_id, statut);
create index projet_extras_a_approuver on public.projet_extras (created_at) where statut = 'soumis';
alter table public.projet_extras enable row level security;
create policy lecture on public.projet_extras for select to authenticated using (app.est_interne() and app.voit_projet(projet_id));
create trigger trg_audit_projet_extras after insert or update on public.projet_extras for each row execute function app.audit();
alter table public.projets
  add column facture_st_soumise_le timestamptz,
  add column facture_st_total_cents bigint check (facture_st_total_cents is null or facture_st_total_cents >= 0);
create or replace function app.notifier_planification(p_type text, p_titre text, p_message text, p_lien text)
returns void language sql security definer set search_path = public as $$
  insert into public.notifications (destinataire_employe_id, type, titre, message, lien)
  select id, p_type, p_titre, p_message, p_lien from public.employes where actif and role in ('Admin tout','Direction','Coordonnateur')
$$;
create or replace function app.projet_extras_ouvert(p_projet uuid) returns public.projets
language plpgsql stable security definer set search_path = public as $$
declare p public.projets%rowtype; v_f uuid := app.mon_fournisseur();
begin
  select * into p from public.projets where id = p_projet;
  if p.id is null or v_f is null or p.sous_traitant_id is distinct from v_f then raise exception 'Job introuvable' using errcode = '42501'; end if;
  if p.statut not in ('a_planifier','planifie','en_cours','termine') then raise exception 'Extras fermés pour cette job (étape : %)', p.statut using errcode = 'P0001'; end if;
  if p.facture_st_soumise_le is not null then raise exception 'Facture finale déjà soumise : plus d''extras' using errcode = 'P0001'; end if;
  return p;
end $$;
create or replace function public.hvac_extra_ajouter(p_projet uuid, p jsonb) returns uuid
language plpgsql security definer set search_path = public as $$
declare pr public.projets%rowtype; v_type uuid := nullif(p->>'type_travail_id', '')::uuid; v_cout bigint; v_desc text; v_id uuid;
begin
  pr := app.projet_extras_ouvert(p_projet);
  if v_type is not null then
    if not exists (select 1 from public.travaux_sous_traitants where fournisseur_id = pr.sous_traitant_id and type_travail_id = v_type) then
      raise exception 'Ce travail n''est pas dans ta liste de prix : ajoute-le hors liste avec une justification' using errcode = 'P0001';
    end if;
    v_cout := public.hvac_cout_installation(pr.sous_traitant_id, v_type, (now() at time zone 'America/Toronto')::date);
    if v_cout is null then raise exception 'Aucun prix pour ce travail dans ta liste' using errcode = 'P0001'; end if;
    select nom into v_desc from public.types_travaux where id = v_type;
  else
    v_cout := nullif(p->>'cout_cents', '')::bigint;
    v_desc := nullif(trim(p->>'description'), '');
    if v_desc is null then raise exception 'Description requise' using errcode = 'P0001'; end if;
    if v_cout is null or v_cout <= 0 then raise exception 'Prix requis pour un extra hors liste' using errcode = 'P0001'; end if;
    if length(trim(coalesce(p->>'justification', ''))) < 10 then raise exception 'Justification requise pour un extra hors liste (10 caractères et plus)' using errcode = 'P0001'; end if;
  end if;
  insert into public.projet_extras (projet_id, fournisseur_id, type_travail_id, description, quantite, cout_cents, justification, cause, note)
  values (pr.id, pr.sous_traitant_id, v_type, v_desc, coalesce(nullif(p->>'quantite', '')::numeric, 1), v_cout,
          nullif(trim(p->>'justification'), ''), p->>'cause', nullif(trim(p->>'note'), ''))
  returning id into v_id;
  return v_id;
end $$;
create or replace function public.hvac_extra_retirer(p_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare e public.projet_extras%rowtype;
begin
  select * into e from public.projet_extras where id = p_id;
  if e.id is null then raise exception 'Extra introuvable' using errcode = '42501'; end if;
  perform app.projet_extras_ouvert(e.projet_id);
  if e.statut <> 'brouillon' then raise exception 'Seul un brouillon se retire' using errcode = 'P0001'; end if;
  update public.projet_extras set statut = 'retire' where id = p_id;
end $$;
create or replace function public.hvac_extras_envoyer(p_projet uuid) returns integer
language plpgsql security definer set search_path = public as $$
declare pr public.projets%rowtype; n integer; v_total bigint;
begin
  pr := app.projet_extras_ouvert(p_projet);
  update public.projet_extras set statut = 'soumis', soumis_le = now() where projet_id = pr.id and statut = 'brouillon';
  get diagnostics n = row_count;
  if n = 0 then raise exception 'Aucun extra à envoyer' using errcode = 'P0001'; end if;
  select sum(round(quantite * cout_cents))::bigint into v_total from public.projet_extras where projet_id = pr.id and statut = 'soumis';
  perform app.notifier_planification('extras_a_approuver', 'Extras à approuver | ' || coalesce(pr.code_projet, 'projet'),
    format('%s : %s extra(s) en attente, %s $ avant taxes.', (select nom from public.fournisseurs where id = pr.sous_traitant_id), n,
           to_char(v_total / 100.0, 'FM999G999G990D00')), '/extras');
  return n;
end $$;
create or replace function public.hvac_extra_decider(p_id uuid, p_approuve boolean, p_raison text default null) returns void
language plpgsql security definer set search_path = public as $$
declare e public.projet_extras%rowtype; pr public.projets%rowtype;
begin
  if not (app.est_admin() or app.est_planification()) then raise exception 'Approbation réservée à Simon, Mike et la planification' using errcode = '42501'; end if;
  select * into e from public.projet_extras where id = p_id;
  if e.id is null then raise exception 'Extra introuvable' using errcode = 'P0001'; end if;
  if e.statut <> 'soumis' then raise exception 'Cet extra n''est pas en attente d''approbation' using errcode = 'P0001'; end if;
  if not p_approuve and length(trim(coalesce(p_raison, ''))) = 0 then raise exception 'Raison du refus requise' using errcode = 'P0001'; end if;
  update public.projet_extras set statut = case when p_approuve then 'approuve' else 'refuse' end,
         raison_refus = case when p_approuve then null else trim(p_raison) end, decide_par = app.employe_id(), decide_le = now()
   where id = p_id;
  select * into pr from public.projets where id = e.projet_id;
  perform app.notifier_fournisseur(e.fournisseur_id, case when p_approuve then 'extra_approuve' else 'extra_refuse' end,
    case when p_approuve then 'Extra approuvé' else 'Extra refusé' end || ' | ' || coalesce(pr.code_projet, ''),
    e.description || case when p_approuve then '' else ' : ' || trim(p_raison) end, '/jobs');
  if p_approuve and e.cause = 'oubli_vendeur' and pr.vendeur_id is not null then
    insert into public.notifications (destinataire_employe_id, type, titre, message, lien)
    values (pr.vendeur_id, 'extra_oubli_vendeur', 'Extra pour un oubli | ' || coalesce(pr.code_projet, ''),
            format('Le sous-traitant a facturé un extra approuvé : %s (%s $). À prévoir dans tes prochaines soumissions.',
                   e.description, to_char(round(e.quantite * e.cout_cents) / 100.0, 'FM999G999G990D00')), '/macro');
  end if;
end $$;
create or replace function public.hvac_facture_finale(p_projet uuid) returns bigint
language plpgsql security definer set search_path = public as $$
declare pr public.projets%rowtype; v_total bigint;
begin
  pr := app.projet_extras_ouvert(p_projet);
  if pr.statut not in ('en_cours','termine') then raise exception 'La facture finale se soumet quand la job est en cours ou terminée' using errcode = 'P0001'; end if;
  if exists (select 1 from public.projet_extras where projet_id = pr.id and statut in ('brouillon','soumis')) then
    raise exception 'Des extras sont en brouillon ou en attente d''approbation' using errcode = 'P0001';
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
revoke all on function public.hvac_extra_ajouter(uuid, jsonb), public.hvac_extra_retirer(uuid), public.hvac_extras_envoyer(uuid),
  public.hvac_extra_decider(uuid, boolean, text), public.hvac_facture_finale(uuid) from public, anon;
grant execute on function public.hvac_extra_ajouter(uuid, jsonb), public.hvac_extra_retirer(uuid), public.hvac_extras_envoyer(uuid),
  public.hvac_extra_decider(uuid, boolean, text), public.hvac_facture_finale(uuid) to authenticated;
create or replace view public.extras_v with (security_invoker = true) as
select x.id, x.projet_id, p.code_projet, p.statut as projet_statut, p.succursale_code, coalesce(s.ville, l.ville) as ville,
       p.vendeur_id, trim(e.prenom || ' ' || e.nom) as vendeur_nom, x.fournisseur_id, f.nom as sous_traitant_nom,
       x.type_travail_id, x.description, x.quantite, x.cout_cents, round(x.quantite * x.cout_cents)::bigint as total_cents,
       x.hors_liste, x.justification, x.cause, x.note, x.statut, x.soumis_le, x.decide_le, x.raison_refus,
       trim(d.prenom || ' ' || d.nom) as decide_par_nom, x.created_at
  from public.projet_extras x
  join public.projets p on p.id = x.projet_id
  join public.fournisseurs f on f.id = x.fournisseur_id
  left join public.sites s on s.id = p.site_id
  left join public.leads l on l.id = p.lead_id
  left join public.employes e on e.id = p.vendeur_id
  left join public.employes d on d.id = x.decide_par
 where x.statut <> 'retire';
grant select on public.extras_v to authenticated;
revoke all on public.extras_v from anon;
create or replace view public.projets_macro_v with (security_invoker = true) as
select p.id, p.code_projet, p.statut, p.succursale_code, p.client_id, trim(coalesce(c.prenom || ' ', '') || c.nom) as client_nom,
       coalesce(s.ville, l.ville) as ville, p.vendeur_id, trim(e.prenom || ' ' || e.nom) as vendeur_nom, p.lead_id, p.devis_numero_mike,
       p.montant_avant_taxes_cents, p.type_systeme, p.signe_le, p.installation_prevue_le, p.created_at, p.updated_at,
       p.sous_traitant_id, f.nom as sous_traitant_nom,
       (select sum(round(pl.quantite * pl.cout_cents))::bigint from public.projet_lignes pl
         where pl.projet_id = p.id and pl.type_ligne = 'installation') as cout_installation_cents,
       (select count(*)::int from public.projet_extras x where x.projet_id = p.id and x.statut = 'soumis') as extras_a_approuver,
       (select sum(round(x.quantite * x.cout_cents))::bigint from public.projet_extras x where x.projet_id = p.id and x.statut = 'approuve') as extras_approuves_cents,
       p.facture_st_soumise_le, p.facture_st_total_cents
  from public.projets p
  join public.clients c on c.id = p.client_id
  left join public.sites s on s.id = p.site_id
  left join public.leads l on l.id = p.lead_id
  left join public.employes e on e.id = p.vendeur_id
  left join public.fournisseurs f on f.id = p.sous_traitant_id
 where p.division = 'Ventilation';
drop function public.hvac_mes_projets(uuid);
create function public.hvac_mes_projets(p_fournisseur uuid default null)
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
                     'justification', x.justification, 'note', x.note, 'statut', x.statut, 'raison_refus', x.raison_refus) order by x.created_at)
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

-- ===== 20261024001600_photos_extras.sql =====
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

-- ===== 20261024001700_photo_obligatoire.sql =====
create or replace function public.hvac_extras_envoyer(p_projet uuid) returns integer
language plpgsql security definer set search_path = public as $$
declare pr public.projets%rowtype; n integer; v_total bigint; v_sans text;
begin
  pr := app.projet_extras_ouvert(p_projet);
  select string_agg(x.description, ', ' order by x.created_at) into v_sans
    from public.projet_extras x
   where x.projet_id = pr.id and x.statut = 'brouillon' and (x.hors_liste or x.cause = 'imprevu_chantier')
     and not exists (select 1 from public.projet_extra_photos ph where ph.extra_id = x.id and ph.statut = 'televersee');
  if v_sans is not null then
    raise exception 'Photo obligatoire pour un extra hors liste ou un imprévu de chantier : %', v_sans using errcode = 'P0001';
  end if;
  update public.projet_extras set statut = 'soumis', soumis_le = now() where projet_id = pr.id and statut = 'brouillon';
  get diagnostics n = row_count;
  if n = 0 then raise exception 'Aucun extra à envoyer' using errcode = 'P0001'; end if;
  select sum(round(quantite * cout_cents))::bigint into v_total from public.projet_extras where projet_id = pr.id and statut = 'soumis';
  perform app.notifier_planification('extras_a_approuver', 'Extras à approuver | ' || coalesce(pr.code_projet, 'projet'),
    format('%s : %s extra(s) en attente, %s $ avant taxes.', (select nom from public.fournisseurs where id = pr.sous_traitant_id), n,
           to_char(v_total / 100.0, 'FM999G999G990D00')), '/extras');
  return n;
end $$;

-- ===== 20261024001800_dossier_job.sql =====
alter table public.projets add column numero_ahri text check (numero_ahri is null or numero_ahri ~ '^[0-9]{5,12}$');
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

-- ===== 20261025000100_visite_pointage.sql =====
alter table public.lead_activites add column source text not null default 'hvac' check (source in ('hvac','pointage'));
alter table public.lead_activites add column pointage_ref text;   -- identifiant de la visite (pré-installation) dans l'app de Mike
alter table public.lead_activites drop constraint lead_activites_type_check;
alter table public.lead_activites add constraint lead_activites_type_check check (type in ('attribution','prise_en_charge','appel',
  'courriel','texto','note','visite_planifiee','visite_annulee','perdu','reouvert','vendu'));
create index lead_activites_pointage on public.lead_activites (pointage_ref) where pointage_ref is not null;
alter table public.leads add column visite_pointage_ref text;
create or replace function app.lead_activite_apres() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  update public.leads l set
    pris_en_charge_le = case when new.type in ('prise_en_charge','appel','courriel','texto','visite_planifiee')
                             then coalesce(l.pris_en_charge_le, new.fait_le) else l.pris_en_charge_le end,
    premier_contact_le = case when new.type in ('appel','courriel','texto') and l.premier_contact_le is null
                              then new.fait_le else l.premier_contact_le end,
    premier_contact_canal = case when new.type in ('appel','courriel','texto') and l.premier_contact_le is null
                                 then new.type else l.premier_contact_canal end,
    visite_prevue_le = case when new.type = 'visite_planifiee' then new.visite_le
                            when new.type = 'visite_annulee' then null else l.visite_prevue_le end,
    visite_pointage_ref = case when new.type = 'visite_planifiee' then coalesce(new.pointage_ref, l.visite_pointage_ref)
                               when new.type = 'visite_annulee' then null else l.visite_pointage_ref end,
    perdu_le = case when new.type = 'perdu' then new.fait_le when new.type = 'reouvert' then null else l.perdu_le end,
    raison_perte = case when new.type = 'perdu' then new.note else l.raison_perte end,
    statut = case
      when new.type = 'vendu' then 'converti'
      when new.type = 'perdu' then 'perdu'
      when new.type = 'reouvert' then case when l.premier_contact_le is not null then 'contacte' else 'pris_en_charge' end
      when l.statut in ('converti','perdu') then l.statut
      when new.type = 'visite_planifiee' then 'inspection_planifiee'
      when new.type = 'visite_annulee' and l.statut = 'inspection_planifiee'
        then case when l.premier_contact_le is not null then 'contacte' else 'pris_en_charge' end
      when new.type in ('appel','courriel','texto') and l.statut in ('nouveau','pris_en_charge') then 'contacte'
      when new.type = 'prise_en_charge' and l.statut = 'nouveau' then 'pris_en_charge'
      else l.statut end
  where l.id = new.lead_id;
  return null;
end $$;
create or replace function app.lead_ref_pointage_garde() returns trigger
language plpgsql as $$
begin
  if tg_op = 'INSERT' then new.visite_pointage_ref := null;
  elsif pg_trigger_depth() = 1 then new.visite_pointage_ref := old.visite_pointage_ref; end if;
  return new;
end $$;
create trigger trg_lead_ref_pointage before insert or update on public.leads for each row execute function app.lead_ref_pointage_garde();
insert into public.parametres (cle, valeur, description) values
  ('visites_pointage_seulement', 'false', 'true : la date de visite vient seulement de Pointage (app de Mike), plus de saisie manuelle dans le lead (ADR-086).')
on conflict (cle) do nothing;
drop policy ajout on public.lead_activites;
create policy ajout on public.lead_activites for insert to authenticated
  with check (exists (select 1 from public.leads l where l.id = lead_id) and employe_id = app.employe_id()
              and type not in ('attribution','visite_annulee') and source = 'hvac' and pointage_ref is null
              and not (type = 'visite_planifiee' and app.parametre_bool('visites_pointage_seulement', false)));
create or replace function public.hvac_visite_pointage(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  l public.leads%rowtype; v_ref text := nullif(trim(p->>'pointage_ref'), '');
  v_le timestamptz := nullif(p->>'visite_le', '')::timestamptz; v_annulee boolean := coalesce((p->>'annulee')::boolean, false);
  v_tel text := nullif(regexp_replace(coalesce(p->>'telephone', ''), '\D', '', 'g'), ''); n int;
begin
  if v_ref is null then raise exception 'Référence de la visite Pointage requise' using errcode = 'P0001'; end if;
  if not v_annulee and v_le is null then raise exception 'Date de la visite requise' using errcode = 'P0001'; end if;
  if nullif(p->>'lead_ref', '') is not null then
    select * into l from public.leads where id = (p->>'lead_ref')::uuid;
  else
    select * into l from public.leads where visite_pointage_ref = v_ref limit 1;
    if l.id is null and v_tel is not null then
      select count(*) into n from public.leads where right(regexp_replace(coalesce(contact_tel, ''), '\D', '', 'g'), 10) = right(v_tel, 10)
         and statut not in ('converti','perdu');
      if n > 1 then raise exception 'Plusieurs leads ouverts pour ce téléphone : lead à préciser' using errcode = 'P0001'; end if;
      select * into l from public.leads where right(regexp_replace(coalesce(contact_tel, ''), '\D', '', 'g'), 10) = right(v_tel, 10)
         and statut not in ('converti','perdu');
    end if;
  end if;
  if l.id is null then raise exception 'Lead introuvable pour cette visite' using errcode = 'P0002'; end if;
  if v_annulee then
    if l.visite_pointage_ref is distinct from v_ref then return jsonb_build_object('lead_id', l.id, 'change', false); end if;
    insert into public.lead_activites (lead_id, type, note, source, pointage_ref, employe_id)
    values (l.id, 'visite_annulee', 'Visite annulée dans Pointage', 'pointage', v_ref, l.assigne_a);
  else
    if l.visite_pointage_ref = v_ref and l.visite_prevue_le = v_le then return jsonb_build_object('lead_id', l.id, 'change', false); end if;
    insert into public.lead_activites (lead_id, type, note, visite_le, source, pointage_ref, employe_id)
    values (l.id, 'visite_planifiee', case when l.visite_pointage_ref = v_ref then 'Visite déplacée dans Pointage' else 'Visite planifiée dans Pointage' end,
            v_le, 'pointage', v_ref, l.assigne_a);
  end if;
  return jsonb_build_object('lead_id', l.id, 'change', true);
end $$;
revoke all on function public.hvac_visite_pointage(jsonb) from public, anon, authenticated;
grant execute on function public.hvac_visite_pointage(jsonb) to service_role;
drop view public.crm_evaluation_v;
drop view public.crm_rapidite_v;
drop view public.leads_v;
create view public.leads_v with (security_invoker = true) as
select l.*,
       e.prenom || ' ' || e.nom as vendeur_nom,
       extract(epoch from (l.pris_en_charge_le - l.recu_le)) / 60  as minutes_prise_en_charge,
       extract(epoch from (l.premier_contact_le - l.recu_le)) / 60 as minutes_premier_contact,
       extract(epoch from (coalesce(l.premier_contact_le, now()) - l.recu_le)) / 60 as minutes_en_attente,
       l.premier_contact_le is null and l.statut not in ('perdu','converti')
         and now() - l.recu_le > make_interval(mins => (select coalesce(seuil_moyen, seuil_bon)::int
                                                          from public.crm_objectifs where indicateur = 'minutes_premier_contact'))
         is true as en_retard,
       l.type_demande is null or l.assigne_a is null or exists (
         select 1 from public.crm_vendeur_types q where q.employe_id = l.assigne_a and q.type_demande = l.type_demande)
         as vendeur_qualifie
  from public.leads l left join public.employes e on e.id = l.assigne_a;
create or replace view public.crm_rapidite_v with (security_invoker = true) as
select assigne_a as employe_id, vendeur_nom,
       count(*)                                                    as leads,
       count(*) filter (where premier_contact_le is not null)      as contactes,
       round((percentile_cont(0.5) within group (order by minutes_prise_en_charge))::numeric, 1) as minutes_prise_en_charge,
       round((percentile_cont(0.5) within group (order by minutes_premier_contact))::numeric, 1) as minutes_premier_contact,
       round(100.0 * count(*) filter (where premier_contact_le is not null) / count(*), 1)       as pct_contactes,
       round(100.0 * count(*) filter (where premier_contact_canal = 'appel')
             / nullif(count(*) filter (where premier_contact_le is not null), 0), 1)            as pct_premier_par_appel,
       round(100.0 * count(*) filter (where visite_prevue_le is not null) / count(*), 1)        as pct_visites,
       count(*) filter (where premier_contact_canal = 'appel')    as par_appel,
       count(*) filter (where premier_contact_canal = 'courriel') as par_courriel,
       count(*) filter (where premier_contact_canal = 'texto')    as par_texto
  from public.leads_v
 where assigne_a is not null
 group by assigne_a, vendeur_nom;
create or replace view public.crm_evaluation_v with (security_invoker = true) as
select r.employe_id, r.vendeur_nom, r.leads, o.indicateur, o.libelle, o.unite, o.sens, o.seuil_bon, o.seuil_moyen, o.ordre,
       v.valeur, app.cote(v.valeur, o.sens, o.seuil_bon, o.seuil_moyen) as cote
  from public.crm_rapidite_v r
  cross join public.crm_objectifs o
  cross join lateral (select case o.indicateur
       when 'minutes_prise_en_charge' then r.minutes_prise_en_charge
       when 'minutes_premier_contact' then r.minutes_premier_contact
       when 'pct_contactes'           then r.pct_contactes
       when 'pct_premier_par_appel'   then r.pct_premier_par_appel
       when 'pct_visites'             then r.pct_visites end as valeur) v;

-- ===== 20261025000200_depot_recu.sql =====
alter table public.projets
  add column depot_recu_le timestamptz,
  add column depot_montant_cents bigint check (depot_montant_cents is null or depot_montant_cents > 0),
  add column depot_ref text unique;   -- identifiant du paiement dans l'app de Mike (un même paiement ne compte qu'une fois)
create or replace function public.hvac_depot_recu(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  pr public.projets%rowtype; v_numero text := nullif(regexp_replace(coalesce(p->>'devis_numero_mike', ''), '^#', ''), '');
  v_ref text := nullif(trim(p->>'paiement_ref'), ''); v_le timestamptz := coalesce(nullif(p->>'paye_le', '')::timestamptz, now());
  v_montant bigint := nullif(p->>'montant_cents', '')::bigint;
begin
  if v_numero is null then raise exception 'Numéro de soumission requis' using errcode = 'P0001'; end if;
  if v_ref is null then raise exception 'Référence du paiement requise' using errcode = 'P0001'; end if;
  if v_montant is not null and v_montant <= 0 then raise exception 'Montant invalide' using errcode = 'P0001'; end if;
  select * into pr from public.projets where depot_ref = v_ref;
  if pr.id is not null then return jsonb_build_object('projet_id', pr.id, 'change', false, 'raison', 'paiement déjà reçu'); end if;
  select * into pr from public.projets where devis_numero_mike = v_numero for update;
  if pr.id is null then raise exception 'Projet introuvable pour la soumission #%', v_numero using errcode = 'P0002'; end if;
  if pr.statut <> 'attente_paiement' then
    update public.projets set depot_recu_le = coalesce(depot_recu_le, v_le), depot_montant_cents = coalesce(depot_montant_cents, v_montant),
           depot_ref = coalesce(depot_ref, v_ref) where id = pr.id;
    if pr.statut = 'annule' then
      perform app.notifier_planification('depot_projet_annule', 'Dépôt reçu sur un projet annulé | ' || coalesce(pr.code_projet, ''),
        format('Soumission #%s : un dépôt est arrivé alors que le projet est annulé. À vérifier (remboursement ?).', v_numero), '/macro');
    end if;
    return jsonb_build_object('projet_id', pr.id, 'change', false, 'raison', 'étape : ' || pr.statut);
  end if;
  update public.projets set statut = 'a_planifier', depot_recu_le = v_le, depot_montant_cents = v_montant, depot_ref = v_ref where id = pr.id;
  perform app.notifier_planification('depot_recu', 'Dépôt reçu : à céduler | ' || coalesce(pr.code_projet, ''),
    format('Soumission #%s : le client a payé son dépôt%s. Le projet est passé à « À céduler ».', v_numero,
           case when v_montant is null then '' else ' (' || to_char(v_montant / 100.0, 'FM999G999G990D00') || ' $)' end), '/macro');
  if pr.sous_traitant_id is not null then
    perform app.notifier_fournisseur(pr.sous_traitant_id, 'depot_recu', 'Job confirmée | ' || coalesce(pr.code_projet, ''),
      'Le client a payé son dépôt. Ses coordonnées et ton dossier LogisVert sont maintenant ouverts dans « Mes jobs ».', '/jobs');
  end if;
  return jsonb_build_object('projet_id', pr.id, 'change', true);
end $$;
revoke all on function public.hvac_depot_recu(jsonb) from public, anon, authenticated;
grant execute on function public.hvac_depot_recu(jsonb) to service_role;
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
       p.numero_ahri, case when p.sous_traitant_id is null then null else cardinality(app.dossier_job(p.id)) end as dossier_manques,
       p.depot_recu_le, p.depot_montant_cents
  from public.projets p
  join public.clients c on c.id = p.client_id
  left join public.sites s on s.id = p.site_id
  left join public.leads l on l.id = p.lead_id
  left join public.employes e on e.id = p.vendeur_id
  left join public.fournisseurs f on f.id = p.sous_traitant_id
 where p.division = 'Ventilation';

-- ===== 20261025000300_ahri_belleflamme.sql =====
create or replace function app.dossier_job(p_projet uuid) returns text[]
language plpgsql stable security definer set search_path = public as $$
declare m text[] := '{}'; e record; n_ext int; n_int int;
begin
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
create or replace function public.hvac_job_ahri(p_projet uuid, p_numero text) returns void
language plpgsql security definer set search_path = public as $$
declare v text := nullif(regexp_replace(coalesce(p_numero, ''), '\s', '', 'g'), '');
begin
  if not (app.est_admin() or app.est_planification()) then
    raise exception 'Le numéro AHRI est inscrit par Belleflamme' using errcode = '42501';
  end if;
  perform app.dossier_ouvert(p_projet);
  if v is null or v !~ '^[0-9]{5,12}$' then raise exception 'Numéro AHRI : 5 à 12 chiffres' using errcode = 'P0001'; end if;
  update public.projets set numero_ahri = v where id = p_projet;
  update public.equipements_installes set ahri = v where projet_id = p_projet and actif;   -- même certificat pour le système
end $$;
