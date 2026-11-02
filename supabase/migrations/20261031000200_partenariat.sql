-- Partenariat du sous-traitant (ADR-096, demande de Simon) : sur son accueil, depuis quand il est partenaire de
-- Belleflamme, depuis quand son compte existe, et la version ACTIVE de sa liste de prix (V1, V2...), mise à jour
-- à chaque nouvelle version du registre (ADR-065).

alter table public.fournisseurs add column partenaire_depuis date;
update public.fournisseurs set partenaire_depuis = created_at::date where partenaire_depuis is null;
alter table public.fournisseurs alter column partenaire_depuis set default current_date;

-- Compte créé : à la première connexion (lien du compte Auth avec la fiche, ADR-026). Un nouveau responsable
-- (ADR-095) repart à sa propre date.
alter table public.employes add column compte_cree_le timestamptz;
update public.employes set compte_cree_le = created_at where auth_user_id is not null and compte_cree_le is null;

create or replace function public.hvac_session() returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_email text := lower(auth.jwt() ->> 'email'); e public.employes%rowtype;
begin
  if auth.uid() is null then return null; end if;
  update public.employes set auth_user_id = auth.uid(), compte_cree_le = now()
   where auth_user_id is null and lower(email) = v_email and actif;
  select * into e from public.employes where auth_user_id = auth.uid() and actif;
  if not found then return null; end if;
  return jsonb_build_object('id', e.id, 'monday_item_id', e.monday_item_id, 'email', e.email,
    'prenom', e.prenom, 'nom', e.nom, 'role', e.role, 'succursale_code', e.succursale_code,
    'peut_approuver_rabais', e.peut_approuver_rabais, 'fournisseur_id', e.fournisseur_id);
end $$;

-- Le sous-traitant pour lui-même ; la planification pour n'importe lequel
create or replace function public.hvac_partenariat(p_fournisseur uuid default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_f uuid := coalesce(app.mon_fournisseur(), p_fournisseur); f public.fournisseurs%rowtype; v record;
begin
  if v_f is null or (app.mon_fournisseur() is null and not (app.est_planification() or app.est_admin())) then
    raise exception 'Sous-traitant introuvable' using errcode = 'P0002';
  end if;
  select * into f from public.fournisseurs where id = v_f;
  if f.id is null then raise exception 'Sous-traitant introuvable' using errcode = 'P0002'; end if;
  select numero, cree_le into v from public.listes_prix_versions where fournisseur_id = v_f order by numero desc limit 1;
  return jsonb_build_object('nom', f.nom, 'partenaire_depuis', f.partenaire_depuis,
    'compte_cree_le', (select compte_cree_le from public.employes where fournisseur_id = v_f and role = 'Sous-traitant'),
    'version', v.numero, 'version_le', v.cree_le);
end $$;
revoke all on function public.hvac_partenariat(uuid) from public, anon;
grant execute on function public.hvac_partenariat(uuid) to authenticated;
