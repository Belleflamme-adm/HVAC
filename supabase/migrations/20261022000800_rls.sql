-- Phase 1 | Sécurité : RLS sur toutes les tables, aucune politique DELETE (on archive par statut).
-- Pas de FORCE RLS : les fonctions security definer (propriétaire des tables) doivent
-- pouvoir lire sans récursion de politiques.
-- Principes :
--   * anon (clé publique sans session) : aucun accès aux tables
--   * Admin tout, Direction, Comptabilité : toutes les succursales
--   * Gérant, Vendeur, Coordonnateur : leurs succursales (ADR-006)
--   * Technicien : seulement ce qui lui est assigné (minimisation, Loi 25)
--   * les fonctions serverless utilisent le JWT de l'utilisateur, donc la RLS s'applique ;
--     la clé service_role (qui contourne la RLS) est réservée aux tâches système

-- ---------------------------------------------------------------------------
-- Helpers d'accès
-- ---------------------------------------------------------------------------

create or replace function app.acces_succursale(p_code text) returns boolean
language sql stable as $$
  select app.voit_tout()
      or (coalesce(app.role() in ('Gérant de succursale','Vendeur','Coordonnateur'), false)
          and p_code = any(app.mes_succursales()))
$$;

create or replace function app.est_facturation() returns boolean
language sql stable as $$
  select coalesce(app.role() in ('Admin tout','Direction','Comptabilité','Coordonnateur','Gérant de succursale'), false)
$$;

create or replace function app.technicien_sur_projet(p_projet uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.bons_travail
                  where projet_id = p_projet and assigne_employe_id = app.employe_id() and statut <> 'annule')
$$;

create or replace function app.technicien_voit_client(p_client uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.bons_travail bt
                   left join public.projets p on p.id = bt.projet_id
                   left join public.appels_service a on a.id = bt.appel_service_id
                  where bt.assigne_employe_id = app.employe_id() and bt.statut <> 'annule'
                    and (p.client_id = p_client or a.client_id = p_client))
      or exists (select 1 from public.appels_service
                  where technicien_id = app.employe_id() and client_id = p_client)
      or exists (select 1 from public.inspections
                  where inspecteur_id = app.employe_id() and client_id = p_client)
$$;

create or replace function app.voit_client(p_client uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select app.acces_succursale((select succursale_code from public.clients where id = p_client))
      or app.technicien_voit_client(p_client)
$$;

create or replace function app.voit_devis(p_devis uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select app.acces_succursale((select succursale_code from public.devis where id = p_devis))
$$;

create or replace function app.voit_projet(p_projet uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select app.acces_succursale((select succursale_code from public.projets where id = p_projet))
      or app.technicien_sur_projet(p_projet)
$$;

create or replace function app.voit_bt(p_bt uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.bons_travail
                  where id = p_bt and (assigne_employe_id = app.employe_id() or app.acces_succursale(succursale_code)))
$$;

create or replace function app.voit_facture(p_facture uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select app.acces_succursale((select succursale_code from public.factures where id = p_facture))
$$;

-- ---------------------------------------------------------------------------
-- Droits de base
-- ---------------------------------------------------------------------------

revoke all on all tables in schema public from anon;
revoke all on all sequences in schema public from anon;
grant usage on schema app to authenticated;
grant execute on all functions in schema app to authenticated;
revoke execute on function app.prochain_numero(text, text, text, date) from authenticated;

do $$
declare t text;
begin
  for t in select tablename from pg_tables where schemaname = 'public' loop
    execute format('alter table public.%I enable row level security', t);
  end loop;
end $$;

-- ---------------------------------------------------------------------------
-- Référentiels : lecture pour tous les employés connectés, écriture admin
-- ---------------------------------------------------------------------------

do $$
declare t text;
begin
  foreach t in array array['succursales','divisions','parametres','taux_taxes','formats_numerotation',
                           'marques','produits','kits','kit_items','fournisseurs','employes','employe_succursales'] loop
    execute format('create policy lecture on public.%I for select to authenticated using (app.employe_id() is not null)', t);
    execute format('create policy ajout_admin on public.%I for insert to authenticated with check (app.est_admin())', t);
    execute format('create policy maj_admin on public.%I for update to authenticated using (app.est_admin()) with check (app.est_admin())', t);
  end loop;
end $$;

-- Compteurs : aucun accès direct, seulement via app.prochain_numero (security definer).
-- Journal : lecture admin seulement, écriture par triggers et app.journaliser.
create policy lecture_admin on public.journal_audit for select to authenticated using (app.est_admin());

-- Certifications
create policy lecture on public.certifications for select to authenticated
  using (app.est_admin() or app.role() = 'Gérant de succursale' or employe_id = app.employe_id());
create policy ecriture on public.certifications for insert to authenticated
  with check (app.est_admin() or app.role() = 'Gérant de succursale');
create policy maj on public.certifications for update to authenticated
  using (app.est_admin() or app.role() = 'Gérant de succursale');

-- ---------------------------------------------------------------------------
-- Commercial : par succursale
-- ---------------------------------------------------------------------------

create policy lecture on public.clients for select to authenticated
  using (app.acces_succursale(succursale_code) or app.technicien_voit_client(id));
create policy ajout on public.clients for insert to authenticated
  with check (app.acces_succursale(succursale_code));
create policy maj on public.clients for update to authenticated
  using (app.acces_succursale(succursale_code)) with check (app.acces_succursale(succursale_code));

create policy lecture on public.sites for select to authenticated using (app.voit_client(client_id));
create policy ajout on public.sites for insert to authenticated
  with check (app.acces_succursale((select succursale_code from public.clients c where c.id = client_id)));
create policy maj on public.sites for update to authenticated
  using (app.acces_succursale((select succursale_code from public.clients c where c.id = client_id)));

do $$
declare t text;
begin
  foreach t in array array['leads','devis','contrats_entretien','financements','subventions'] loop
    execute format('create policy lecture on public.%I for select to authenticated using (app.acces_succursale(succursale_code))', t);
    execute format('create policy ajout on public.%I for insert to authenticated with check (app.acces_succursale(succursale_code))', t);
    execute format('create policy maj on public.%I for update to authenticated using (app.acces_succursale(succursale_code)) with check (app.acces_succursale(succursale_code))', t);
  end loop;
end $$;

create policy lecture on public.inspections for select to authenticated
  using (app.acces_succursale(succursale_code) or inspecteur_id = app.employe_id());
create policy ajout on public.inspections for insert to authenticated
  with check (app.acces_succursale(succursale_code));
create policy maj on public.inspections for update to authenticated
  using (app.acces_succursale(succursale_code) or inspecteur_id = app.employe_id());

create policy lecture on public.devis_lignes for select to authenticated using (app.voit_devis(devis_id));
create policy ajout on public.devis_lignes for insert to authenticated with check (app.voit_devis(devis_id));
create policy maj on public.devis_lignes for update to authenticated using (app.voit_devis(devis_id));
-- Exception assumée à « pas de DELETE » : retirer une ligne d'un devis en brouillon
-- (le trigger refuse si le devis n'est plus en brouillon).
create policy retrait on public.devis_lignes for delete to authenticated using (app.voit_devis(devis_id));

create policy lecture on public.approbations_rabais for select to authenticated
  using (app.voit_devis(devis_id) or app.peut_approuver_rabais());
create policy demande on public.approbations_rabais for insert to authenticated
  with check (app.voit_devis(devis_id) and statut = 'en_attente');
create policy decision on public.approbations_rabais for update to authenticated
  using (app.peut_approuver_rabais()) with check (app.peut_approuver_rabais());

create policy lecture on public.delegations_rabais for select to authenticated
  using (employe_id = app.employe_id() or app.peut_approuver_rabais() or app.est_admin());
create policy ajout on public.delegations_rabais for insert to authenticated with check (app.peut_approuver_rabais());
create policy maj on public.delegations_rabais for update to authenticated using (app.peut_approuver_rabais());

-- ---------------------------------------------------------------------------
-- Opérations : succursale + techniciens assignés
-- ---------------------------------------------------------------------------

create policy lecture on public.projets for select to authenticated using (app.voit_projet(id));
create policy ajout on public.projets for insert to authenticated with check (app.acces_succursale(succursale_code));
create policy maj on public.projets for update to authenticated
  using (app.acces_succursale(succursale_code)) with check (app.acces_succursale(succursale_code));

create policy lecture on public.equipements_installes for select to authenticated
  using (app.voit_client(client_id));
create policy ajout on public.equipements_installes for insert to authenticated
  with check (app.voit_client(client_id) and (projet_id is null or app.voit_projet(projet_id)));
create policy maj on public.equipements_installes for update to authenticated
  using (app.voit_client(client_id) and (projet_id is null or app.voit_projet(projet_id)));

create policy lecture on public.appels_service for select to authenticated
  using (app.acces_succursale(succursale_code) or technicien_id = app.employe_id());
create policy ajout on public.appels_service for insert to authenticated with check (app.acces_succursale(succursale_code));
create policy maj on public.appels_service for update to authenticated
  using (app.acces_succursale(succursale_code) or technicien_id = app.employe_id());

create policy lecture on public.bons_travail for select to authenticated using (app.voit_bt(id));
create policy ajout on public.bons_travail for insert to authenticated with check (app.acces_succursale(succursale_code));
create policy maj on public.bons_travail for update to authenticated
  using (app.acces_succursale(succursale_code) or assigne_employe_id = app.employe_id());

create policy lecture on public.bt_lignes for select to authenticated using (app.voit_bt(bon_travail_id));
create policy ajout on public.bt_lignes for insert to authenticated with check (app.voit_bt(bon_travail_id));
create policy maj on public.bt_lignes for update to authenticated using (app.voit_bt(bon_travail_id));

-- ---------------------------------------------------------------------------
-- Facturation : lecture par succursale, écriture rôles de facturation
-- ---------------------------------------------------------------------------

create policy lecture on public.factures for select to authenticated using (app.acces_succursale(succursale_code));
create policy ajout on public.factures for insert to authenticated
  with check (app.est_facturation() and app.acces_succursale(succursale_code));
create policy maj on public.factures for update to authenticated
  using (app.est_facturation() and app.acces_succursale(succursale_code));

create policy lecture on public.facture_lignes for select to authenticated using (app.voit_facture(facture_id));
create policy ajout on public.facture_lignes for insert to authenticated
  with check (app.est_facturation() and app.voit_facture(facture_id));
create policy maj on public.facture_lignes for update to authenticated
  using (app.est_facturation() and app.voit_facture(facture_id));
create policy retrait on public.facture_lignes for delete to authenticated
  using (app.est_facturation() and app.voit_facture(facture_id));

create policy lecture on public.paiements for select to authenticated using (app.voit_facture(facture_id));
create policy ajout on public.paiements for insert to authenticated
  with check (app.est_facturation() and app.voit_facture(facture_id));

-- ---------------------------------------------------------------------------
-- Documents (Storage) : succursale, ou ce que l'employé a lui-même téléversé
-- ---------------------------------------------------------------------------

create policy lecture on public.documents for select to authenticated
  using (app.acces_succursale(succursale_code) or created_by = app.employe_id());
create policy ajout on public.documents for insert to authenticated
  with check (app.employe_id() is not null and succursale_code = any(app.mes_succursales())
              or app.voit_tout());
create policy maj on public.documents for update to authenticated
  using (app.acces_succursale(succursale_code));
