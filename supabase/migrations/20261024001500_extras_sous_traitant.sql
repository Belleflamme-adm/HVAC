-- Feuille d'extra du sous-traitant (ADR-081) : oublis du vendeur, imprévus de chantier, demandes du client.
-- Le sous-traitant ajoute ses extras (de SA liste de prix, ou hors liste avec justification), les envoie pour
-- approbation ; Belleflamme (Simon, Mike, planification) approuve ou refuse ligne par ligne. Ensuite seulement,
-- il soumet sa facture finale : installation + extras approuvés, montant figé. Le paiement reste chez Mike.

-- 1. Lignes d'extra
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
-- Lecture : Belleflamme selon le projet. Le sous-traitant passe par hvac_mes_projets. Écriture : fonctions seulement.
create policy lecture on public.projet_extras for select to authenticated using (app.est_interne() and app.voit_projet(projet_id));
create trigger trg_audit_projet_extras after insert or update on public.projet_extras for each row execute function app.audit();

-- 2. Facture finale du sous-traitant (montant figé ; le paiement se fait dans l'app de Mike)
alter table public.projets
  add column facture_st_soumise_le timestamptz,
  add column facture_st_total_cents bigint check (facture_st_total_cents is null or facture_st_total_cents >= 0);

-- Avis à la planification (Simon, Mike, coordonnateurs)
create or replace function app.notifier_planification(p_type text, p_titre text, p_message text, p_lien text)
returns void language sql security definer set search_path = public as $$
  insert into public.notifications (destinataire_employe_id, type, titre, message, lien)
  select id, p_type, p_titre, p_message, p_lien from public.employes where actif and role in ('Admin tout','Direction','Coordonnateur')
$$;

-- Le projet du sous-traitant, ouvert aux extras : dépôt reçu, pas encore facturé, facture finale pas soumise
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

-- 3. Le sous-traitant ajoute un extra (brouillon). p : { type_travail_id?, description?, quantite, cout_cents? (hors liste), justification?, cause, note? }
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

-- Retirer un brouillon (la ligne reste, statut « retiré », pour la trace)
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

-- Envoyer la feuille d'extra pour approbation (tous les brouillons de la job)
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

-- 4. Belleflamme approuve ou refuse (raison obligatoire au refus). Oubli du vendeur approuvé : avis au vendeur.
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

-- 5. Facture finale : plus rien en brouillon ni en attente ; job en cours ou terminée ; montant figé
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

-- 6. File d'approbation (Belleflamme, RLS des extras)
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

-- 7. Vue Macro : extras en attente et facture finale
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

-- 8. Mes jobs : on ajoute les extras, le total final et la facture finale (type de retour changé : on recrée)
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
