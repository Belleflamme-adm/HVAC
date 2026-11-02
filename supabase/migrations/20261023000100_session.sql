-- Phase 2 | RPC de session appelées par session-login / session-me (via PostgREST).

-- Retourne l'employé lié au compte connecté. Au premier login, lie le compte Supabase Auth
-- à la fiche employé qui a le même courriel (créée d'avance par un admin).
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
    'peut_approuver_rabais', e.peut_approuver_rabais);
end $$;

-- Impersonation (« bfImpersonate » chez Mike) : réservée à « Admin tout », toujours journalisée.
-- Les données restent lues avec le JWT de l'admin : seule l'interface prend l'identité de la cible.
create or replace function public.hvac_impersonation(p_employe uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare e public.employes%rowtype;
begin
  if coalesce(app.role(), '') <> 'Admin tout' then
    raise exception 'Impersonation réservée à « Admin tout »' using errcode = '42501';
  end if;
  select * into e from public.employes where id = p_employe and actif;
  if not found then raise exception 'Employé introuvable' using errcode = 'P0002'; end if;
  perform app.journaliser('impersonation', 'employes', e.id::text, jsonb_build_object('cible', e.email));
  return jsonb_build_object('id', e.id, 'monday_item_id', e.monday_item_id, 'email', e.email,
    'prenom', e.prenom, 'nom', e.nom, 'role', e.role, 'succursale_code', e.succursale_code,
    'peut_approuver_rabais', e.peut_approuver_rabais);
end $$;

revoke all on function public.hvac_session() from public, anon;
revoke all on function public.hvac_impersonation(uuid) from public, anon;
grant execute on function public.hvac_session() to authenticated;
grant execute on function public.hvac_impersonation(uuid) to authenticated;
