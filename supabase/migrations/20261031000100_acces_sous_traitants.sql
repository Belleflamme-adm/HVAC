-- Accès des sous-traitants (ADR-095, décision de Simon) : UN compte par sous-traitant, au courriel du responsable,
-- connexion par courriel et code à 6 chiffres (Supabase Auth, OTP par courriel). Sur la fiche, la planification :
--   « Envoyer l'accès » : le serveur envoie le code au responsable (crée le compte Auth au besoin) ;
--   « Couper l'accès » : le compte est désactivé sur-le-champ (app.employe_id(), app.role() et la session exigent actif) ;
--   « Rétablir l'accès ».
-- Désactiver le sous-traitant coupe aussi son accès. Changer le courriel du responsable déplace le compte vers ce courriel
-- et défait le lien avec l'ancienne personne : elle ne peut plus entrer.

alter table public.employes
  add column acces_envoye_le timestamptz,
  add column acces_coupe_le  timestamptz;

-- Un seul compte par sous-traitant
create unique index employes_un_compte_st on public.employes (fournisseur_id) where role = 'Sous-traitant';

create or replace function app.st_compte(p_fournisseur uuid) returns public.employes
language plpgsql stable security definer set search_path = public as $$
declare e public.employes%rowtype;
begin
  if not app.est_planification() then raise exception 'Réservé à la planification' using errcode = '42501'; end if;
  select * into e from public.employes where fournisseur_id = p_fournisseur and role = 'Sous-traitant';
  if e.id is null then raise exception 'Aucun compte pour ce sous-traitant' using errcode = 'P0002'; end if;
  return e;
end $$;

-- État de l'accès, pour la fiche
create or replace function public.hvac_st_acces(p_fournisseur uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare e public.employes;
begin
  e := app.st_compte(p_fournisseur);
  return jsonb_build_object('email', e.email, 'actif', e.actif, 'connecte', e.auth_user_id is not null,
    'acces_envoye_le', e.acces_envoye_le, 'acces_coupe_le', e.acces_coupe_le);
end $$;

-- Avant l'envoi du code par le serveur : vérifie, note l'envoi et rend le courriel
create or replace function public.hvac_st_acces_envoyer(p_fournisseur uuid) returns text
language plpgsql security definer set search_path = public as $$
declare e public.employes;
begin
  e := app.st_compte(p_fournisseur);
  if not exists (select 1 from public.fournisseurs where id = p_fournisseur and actif) then
    raise exception 'Sous-traitant inactif : réactive-le d''abord' using errcode = 'P0001';
  end if;
  if not e.actif then raise exception 'Accès coupé : rétablis-le d''abord' using errcode = 'P0001'; end if;
  if e.email like '%.invalid' then raise exception 'Courriel du responsable fictif : inscris son vrai courriel' using errcode = 'P0001'; end if;
  update public.employes set acces_envoye_le = now() where id = e.id;
  return e.email;
end $$;

create or replace function public.hvac_st_acces_couper(p_fournisseur uuid) returns void
language plpgsql security definer set search_path = public as $$
declare e public.employes;
begin
  e := app.st_compte(p_fournisseur);
  update public.employes set actif = false, acces_coupe_le = now() where id = e.id;
end $$;

create or replace function public.hvac_st_acces_retablir(p_fournisseur uuid) returns void
language plpgsql security definer set search_path = public as $$
declare e public.employes;
begin
  e := app.st_compte(p_fournisseur);
  if not exists (select 1 from public.fournisseurs where id = p_fournisseur and actif) then
    raise exception 'Sous-traitant inactif : réactive-le d''abord' using errcode = 'P0001';
  end if;
  update public.employes set actif = true, acces_coupe_le = null where id = e.id;
end $$;

revoke all on function public.hvac_st_acces(uuid), public.hvac_st_acces_envoyer(uuid), public.hvac_st_acces_couper(uuid),
  public.hvac_st_acces_retablir(uuid) from public, anon;
grant execute on function public.hvac_st_acces(uuid), public.hvac_st_acces_envoyer(uuid), public.hvac_st_acces_couper(uuid),
  public.hvac_st_acces_retablir(uuid) to authenticated;

-- Fiche du sous-traitant : désactivé -> accès coupé ; nouveau courriel du responsable -> le compte suit, l'ancien lien tombe
create or replace function app.st_fiche_acces() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if old.actif and not new.actif then
    update public.employes set actif = false, acces_coupe_le = now()
     where fournisseur_id = new.id and role = 'Sous-traitant' and actif;
  end if;
  -- Seulement si le compte était celui du responsable (même courriel) : le compte suit la personne responsable
  if new.responsable_courriel is distinct from old.responsable_courriel and nullif(trim(new.responsable_courriel), '') is not null then
    update public.employes set email = lower(trim(new.responsable_courriel)), auth_user_id = null, acces_envoye_le = null
     where fournisseur_id = new.id and role = 'Sous-traitant' and lower(email) = lower(trim(old.responsable_courriel));
  end if;
  return new;
end $$;
create trigger trg_st_fiche_acces after update on public.fournisseurs for each row execute function app.st_fiche_acces();
