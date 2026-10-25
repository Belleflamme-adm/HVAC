-- Dépôt reçu dans l'app de Mike (ADR-087, demande de Simon) : quand l'app de Mike reçoit le paiement du dépôt, elle nous
-- l'envoie (webhook signé paiement-webhook). Le projet passe tout seul de « Signé, attente du dépôt » à « À céduler ».
-- Avis à la planification (à céduler) et au sous-traitant attitré (coordonnées du client et dossier maintenant ouverts).
-- INACTIF tant que PAIEMENT_SYNC_ENABLED=false ; d'ici là, la flèche du Macro reste le moyen manuel.

alter table public.projets
  add column depot_recu_le timestamptz,
  add column depot_montant_cents bigint check (depot_montant_cents is null or depot_montant_cents > 0),
  add column depot_ref text unique;   -- identifiant du paiement dans l'app de Mike (un même paiement ne compte qu'une fois)

-- p : { devis_numero_mike, paiement_ref, montant_cents?, paye_le? }
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
    -- Dépôt noté quand même (trace), mais l'étape ne bouge pas : projet déjà plus loin, ou annulé
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

-- Macro : dépôt reçu (ajouté à la fin de la vue)
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
