-- Mes jobs (ADR-080) : dès que la soumission est signée (Macro, « Signé, attente du dépôt »), le projet tombe aussi
-- chez le sous-traitant attitré. Il voit les machines (quantités, prix à 0 $) et SES prix d'installation seulement :
-- ni le prix chargé au client, ni le total de la facture, ni notre marge. Rien de ça n'est stocké ici de toute façon.
-- Loi 25 : nom, téléphone et adresse du client seulement après le dépôt (étape « À céduler » et suivantes).

-- 1. Sous-traitant attitré au projet
alter table public.projets add column sous_traitant_id uuid references public.fournisseurs(id);
create index projets_sous_traitant on public.projets (sous_traitant_id) where sous_traitant_id is not null;

-- 2. Lignes du projet : machines (sans prix) et installation (coût du sous-traitant, instantané de sa liste à la signature)
create table public.projet_lignes (
  id              uuid primary key default gen_random_uuid(),
  projet_id       uuid not null references public.projets(id),
  division        text not null default 'Ventilation' references public.divisions(nom),
  position        integer not null default 0,
  type_ligne      text not null check (type_ligne in ('machine','installation')),
  description     text not null check (length(trim(description)) > 0),
  quantite        numeric(10,2) not null default 1 check (quantite > 0),
  type_travail_id uuid references public.types_travaux(id),
  cout_cents      bigint check (cout_cents is null or cout_cents > 0),
  check ((type_ligne = 'installation') = (type_travail_id is not null and cout_cents is not null)),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
call app.preparer_table('public.projet_lignes');
create index projet_lignes_projet on public.projet_lignes (projet_id, position);
alter table public.projet_lignes enable row level security;
-- Lecture : Belleflamme selon le projet. Écriture : par hvac_projet_signe seulement (security definer).
create policy lecture on public.projet_lignes for select to authenticated using (app.est_interne() and app.voit_projet(projet_id));
create trigger trg_audit_projet_lignes after insert or update on public.projet_lignes for each row execute function app.audit();

-- 3. Réception d'un projet signé : on ajoute sous_traitant_id et lignes.
--    lignes : [{ type_ligne: 'machine', description, quantite } | { type_ligne: 'installation', type_travail_id, quantite }]
--    Le coût d'installation vient de la liste de prix du sous-traitant à la date de signature, jamais du navigateur.
create or replace function public.hvac_projet_signe(p jsonb) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  l public.leads%rowtype; v_client uuid := nullif(p->>'client_id', '')::uuid; v_projet uuid; v_succ text;
  v_numero text := nullif(trim(p->>'devis_numero_mike'), '');
  v_st uuid := nullif(p->>'sous_traitant_id', '')::uuid; v_signe timestamptz := coalesce(nullif(p->>'signe_le', '')::timestamptz, now());
  x jsonb; v_pos integer := 0; v_type uuid; v_cout bigint; v_nom text;
begin
  if not (app.est_admin() or app.est_planification()) then raise exception 'Réservé à Belleflamme' using errcode = '42501'; end if;
  if v_numero is null then raise exception 'Numéro du devis signé requis' using errcode = 'P0001'; end if;
  select id into v_projet from public.projets where devis_numero_mike = v_numero;
  if v_projet is not null then return v_projet; end if;   -- déjà reçu : rien en double
  if v_st is not null and not exists (select 1 from public.fournisseurs where id = v_st and actif and type in ('sous-traitant','les deux')) then
    raise exception 'Sous-traitant inconnu ou inactif' using errcode = 'P0001';
  end if;
  if jsonb_typeof(coalesce(p->'lignes', '[]')) <> 'array' then raise exception 'Lignes invalides' using errcode = 'P0001'; end if;
  if v_st is null and exists (select 1 from jsonb_array_elements(coalesce(p->'lignes', '[]')) e where e->>'type_ligne' = 'installation') then
    raise exception 'Installation sans sous-traitant' using errcode = 'P0001';
  end if;
  if p->>'lead_id' is not null then select * into l from public.leads where id = (p->>'lead_id')::uuid; end if;
  v_succ := coalesce(p->>'succursale_code', l.succursale_code);
  if v_succ is null then raise exception 'Succursale requise' using errcode = 'P0001'; end if;
  v_client := coalesce(v_client, l.client_id);
  if v_client is null then
    if l.id is null then raise exception 'Client ou lead requis' using errcode = 'P0001'; end if;
    insert into public.clients (nom, telephone, courriel, succursale_code, vendeur_id)
    values (coalesce(nullif(trim(l.contact_nom), ''), 'Client sans nom'), l.contact_tel, l.contact_courriel, v_succ, l.assigne_a)
    returning id into v_client;
    update public.leads set client_id = v_client where id = l.id;
  end if;
  insert into public.projets (division, succursale_code, client_id, vendeur_id, statut, lead_id, devis_numero_mike,
                              montant_avant_taxes_cents, type_systeme, signe_le, sous_traitant_id)
  values ('Ventilation', v_succ, v_client, coalesce(nullif(p->>'vendeur_id', '')::uuid, l.assigne_a), 'attente_paiement', l.id, v_numero,
          nullif(p->>'montant_avant_taxes_cents', '')::bigint, coalesce(p->>'type_systeme', l.type_demande), v_signe, v_st)
  returning id into v_projet;
  for x in select * from jsonb_array_elements(coalesce(p->'lignes', '[]')) loop
    v_pos := v_pos + 1;
    if x->>'type_ligne' = 'machine' then
      insert into public.projet_lignes (projet_id, position, type_ligne, description, quantite)
      values (v_projet, v_pos, 'machine', trim(x->>'description'), coalesce(nullif(x->>'quantite', '')::numeric, 1));
    elsif x->>'type_ligne' = 'installation' then
      v_type := (x->>'type_travail_id')::uuid;
      if not exists (select 1 from public.travaux_sous_traitants where fournisseur_id = v_st and type_travail_id = v_type) then
        raise exception 'Ce travail n''est pas confié à ce sous-traitant' using errcode = 'P0001';
      end if;
      v_cout := public.hvac_cout_installation(v_st, v_type, (v_signe at time zone 'America/Toronto')::date);
      if v_cout is null then raise exception 'Aucun prix pour ce travail dans la liste du sous-traitant' using errcode = 'P0001'; end if;
      select nom into v_nom from public.types_travaux where id = v_type;
      insert into public.projet_lignes (projet_id, position, type_ligne, description, quantite, type_travail_id, cout_cents)
      values (v_projet, v_pos, 'installation', v_nom, coalesce(nullif(x->>'quantite', '')::numeric, 1), v_type, v_cout);
    else
      raise exception 'Type de ligne inconnu' using errcode = 'P0001';
    end if;
  end loop;
  if l.id is not null and l.statut <> 'converti' then
    insert into public.lead_activites (lead_id, type, note) values (l.id, 'vendu', 'Soumission #' || v_numero || ' signée par le client');
  end if;
  return v_projet;
end $$;

-- 4. Vue Macro : sous-traitant et son coût d'installation (Belleflamme seulement, RLS des projets)
create or replace view public.projets_macro_v with (security_invoker = true) as
select p.id, p.code_projet, p.statut, p.succursale_code, p.client_id, trim(coalesce(c.prenom || ' ', '') || c.nom) as client_nom,
       coalesce(s.ville, l.ville) as ville, p.vendeur_id, trim(e.prenom || ' ' || e.nom) as vendeur_nom, p.lead_id, p.devis_numero_mike,
       p.montant_avant_taxes_cents, p.type_systeme, p.signe_le, p.installation_prevue_le, p.created_at, p.updated_at,
       p.sous_traitant_id, f.nom as sous_traitant_nom,
       (select sum(round(pl.quantite * pl.cout_cents))::bigint from public.projet_lignes pl
         where pl.projet_id = p.id and pl.type_ligne = 'installation') as cout_installation_cents
  from public.projets p
  join public.clients c on c.id = p.client_id
  left join public.sites s on s.id = p.site_id
  left join public.leads l on l.id = p.lead_id
  left join public.employes e on e.id = p.vendeur_id
  left join public.fournisseurs f on f.id = p.sous_traitant_id
 where p.division = 'Ventilation';
grant select on public.projets_macro_v to authenticated;
revoke all on public.projets_macro_v from anon;

-- 5. Mes jobs : le sous-traitant voit ses projets, machines à 0 $, ses prix seulement.
--    Belleflamme (admin, planification) peut voir ce que voit un sous-traitant en passant p_fournisseur.
create or replace function public.hvac_mes_projets(p_fournisseur uuid default null)
returns table (id uuid, code_projet text, statut text, ville text, type_systeme text, signe_le timestamptz,
               installation_prevue_le timestamptz, client_nom text, client_telephone text, adresse text,
               lignes jsonb, total_cents bigint)
language plpgsql stable security definer set search_path = public as $$
declare v_f uuid := coalesce(app.mon_fournisseur(), case when app.est_admin() or app.est_planification() then p_fournisseur end);
begin
  if v_f is null then raise exception 'Sous-traitant requis' using errcode = '42501'; end if;
  return query
  select p.id, p.code_projet, p.statut, coalesce(s.ville, ld.ville), p.type_systeme, p.signe_le, p.installation_prevue_le,
         case when p.statut <> 'attente_paiement' then trim(coalesce(c.prenom || ' ', '') || c.nom) end,
         case when p.statut <> 'attente_paiement' then c.telephone end,
         case when p.statut <> 'attente_paiement' then s.adresse end,
         coalesce((select jsonb_agg(jsonb_build_object('type_ligne', pl.type_ligne, 'description', pl.description, 'quantite', pl.quantite,
                     'prix_cents', case when pl.type_ligne = 'installation' then pl.cout_cents else 0 end,
                     'total_cents', case when pl.type_ligne = 'installation' then round(pl.quantite * pl.cout_cents)::bigint else 0 end)
                     order by pl.position)
                     from public.projet_lignes pl where pl.projet_id = p.id), '[]'::jsonb),
         coalesce((select sum(round(pl.quantite * pl.cout_cents))::bigint from public.projet_lignes pl
                    where pl.projet_id = p.id and pl.type_ligne = 'installation'), 0)
    from public.projets p
    join public.clients c on c.id = p.client_id
    left join public.sites s on s.id = p.site_id
    left join public.leads ld on ld.id = p.lead_id
   where p.sous_traitant_id = v_f and p.statut not in ('annule','ferme')
   order by p.signe_le desc nulls last;
end $$;
revoke all on function public.hvac_mes_projets(uuid) from public, anon;
grant execute on function public.hvac_mes_projets(uuid) to authenticated;
