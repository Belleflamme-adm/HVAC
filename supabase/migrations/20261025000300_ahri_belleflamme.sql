-- Numéro AHRI inscrit par Belleflamme, pas par le sous-traitant (ADR-088, demande de Simon) : le sous-traitant prend
-- seulement les photos (appareil installé et plaque signalétique). Le numéro AHRI (certificat de la combinaison
-- extérieure + intérieure) est inscrit par Belleflamme pour la demande LogisVert ; il ne bloque plus la facture finale
-- du sous-traitant ni l'étape « Terminé ».

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
