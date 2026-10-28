-- Facture finale conforme LogisVert (ADR-092, exigence de Simon) : la facture finale du client (faite dans l'app de Mike)
-- DOIT porter les 4 mentions, sinon Hydro-Québec refuse la demande :
--   1. le numéro AHRI ou ENERGY STAR ; 2. la licence RBQ de Belleflamme ; 3. la date d'installation ; 4. la mention « Payé ».
-- Notre app ne fait pas la facture (ADR-055) : elle fournit les données, vérifie qu'elles existent, et exige qu'une personne
-- de Belleflamme confirme avoir vu les 4 mentions sur la facture de Mike avant le passage à « Facturé ».
-- Le guide LogisVert part au client à « Facturé » (facture conforme et payée), et non plus à « Terminé ».

insert into public.parametres (cle, valeur, description) values
  ('licence_rbq_belleflamme', '"5631-7035-01"', 'Licence RBQ de Belleflamme (9238-6051 Québec inc.), obligatoire sur la facture finale pour LogisVert.')
on conflict (cle) do nothing;

alter table public.projets
  add column facture_payee_le      timestamptz,                -- facture finale payée au complet (app de Mike)
  add column facture_numero_mike   text,
  add column facture_paiement_ref  text unique,
  add column facture_verifiee_le   timestamptz,                -- Belleflamme a vu les 4 mentions sur la facture de Mike
  add column facture_verifiee_par  uuid references public.employes(id);

-- Ce qui manque pour une facture finale conforme (liste vide = conforme)
create or replace function app.facture_logisvert_manques(p_projet uuid) returns text[]
language plpgsql stable security definer set search_path = public as $$
declare p public.projets%rowtype; m text[] := '{}'; v_rbq text := (select valeur #>> '{}' from public.parametres where cle = 'licence_rbq_belleflamme');
begin
  select * into p from public.projets where id = p_projet;
  if p.numero_ahri is null and p.numero_energy_star is null then m := array_append(m, 'numéro AHRI ou ENERGY STAR (dossier de la job)'); end if;
  if v_rbq is null or v_rbq !~ '^\d{4}-\d{4}-\d{2}$' then m := array_append(m, 'licence RBQ de Belleflamme (paramètre)'); end if;
  if p.installation_terminee_le is null then m := array_append(m, 'date d''installation (projet passé à Terminé)'); end if;
  if p.facture_payee_le is null then m := array_append(m, 'facture payée au complet (mention « Payé »)'); end if;
  if p.facture_verifiee_le is null then m := array_append(m, 'vérification de la facture de Mike : les 4 mentions y sont'); end if;
  return m;
end $$;

-- Passage à « Facturé » (ou au-delà) : facture conforme exigée, en plus des règles existantes (dossier, étapes)
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
  if n >= array_position(ordre, 'facture') and a < array_position(ordre, 'facture') then
    v_manques := app.facture_logisvert_manques(new.id);
    if cardinality(v_manques) > 0 then
      raise exception 'Facture finale non conforme LogisVert : %', array_to_string(v_manques, ' ; ') using errcode = 'P0001';
    end if;
  end if;
  return new;
end $$;

-- Facture payée : par l'app de Mike (webhook, clé serveur) ou, d'ici la greffe, par Belleflamme
create or replace function public.hvac_facture_payee(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare pr public.projets%rowtype; v_numero text := nullif(regexp_replace(coalesce(p->>'devis_numero_mike', ''), '^#', ''), '');
  v_ref text := nullif(trim(p->>'paiement_ref'), '');
begin
  if v_numero is null or v_ref is null then raise exception 'Numéro de soumission et référence du paiement requis' using errcode = 'P0001'; end if;
  select * into pr from public.projets where facture_paiement_ref = v_ref;
  if pr.id is not null then return jsonb_build_object('projet_id', pr.id, 'change', false); end if;
  select * into pr from public.projets where devis_numero_mike = v_numero;
  if pr.id is null then raise exception 'Projet introuvable pour la soumission #%', v_numero using errcode = 'P0002'; end if;
  update public.projets set facture_payee_le = coalesce(nullif(p->>'paye_le', '')::timestamptz, now()), facture_paiement_ref = v_ref,
         facture_numero_mike = coalesce(nullif(trim(p->>'facture_numero_mike'), ''), facture_numero_mike) where id = pr.id;
  return jsonb_build_object('projet_id', pr.id, 'change', true);
end $$;
revoke all on function public.hvac_facture_payee(jsonb) from public, anon, authenticated;
grant execute on function public.hvac_facture_payee(jsonb) to service_role;

create or replace function public.hvac_facture_payee_manuel(p_projet uuid, p_numero_facture text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not (app.est_admin() or app.est_planification()) then raise exception 'Réservé à Belleflamme' using errcode = '42501'; end if;
  if nullif(trim(p_numero_facture), '') is null then raise exception 'Numéro de la facture de Mike requis' using errcode = 'P0001'; end if;
  update public.projets set facture_payee_le = now(), facture_numero_mike = trim(p_numero_facture) where id = p_projet;
  if not found then raise exception 'Projet introuvable' using errcode = 'P0002'; end if;
end $$;

-- « J'ai vu les 4 mentions sur la facture de Mike » : seulement si les données existent (sinon la facture ne peut pas les porter)
create or replace function public.hvac_facture_verifiee(p_projet uuid) returns void
language plpgsql security definer set search_path = public as $$
declare v_manques text[];
begin
  if not (app.est_admin() or app.est_planification()) then raise exception 'Réservé à Belleflamme' using errcode = '42501'; end if;
  select array_agg(x) into v_manques from unnest(app.facture_logisvert_manques(p_projet)) x where x not like 'vérification%';
  if cardinality(v_manques) > 0 then
    raise exception 'Impossible de confirmer : il manque %', array_to_string(v_manques, ' ; ') using errcode = 'P0001';
  end if;
  update public.projets set facture_verifiee_le = now(), facture_verifiee_par = app.employe_id() where id = p_projet;
end $$;
revoke all on function public.hvac_facture_payee_manuel(uuid, text), public.hvac_facture_verifiee(uuid) from public, anon;
grant execute on function public.hvac_facture_payee_manuel(uuid, text), public.hvac_facture_verifiee(uuid) to authenticated;

-- (La règle « Guide LogisVert au client » se déclenche à « Facturé » : voir ses conditions dans la migration du moteur.)

-- Macro : état de la facture finale (ajouté à la fin de la vue)
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
       p.depot_recu_le, p.depot_montant_cents, p.subvention_statut, p.subvention_maj_le, p.installation_terminee_le, p.numero_energy_star,
       p.facture_payee_le, p.facture_numero_mike, p.facture_verifiee_le, cardinality(app.facture_logisvert_manques(p.id)) as facture_manques
  from public.projets p
  join public.clients c on c.id = p.client_id
  left join public.sites s on s.id = p.site_id
  left join public.leads l on l.id = p.lead_id
  left join public.employes e on e.id = p.vendeur_id
  left join public.fournisseurs f on f.id = p.sous_traitant_id
 where p.division = 'Ventilation';
