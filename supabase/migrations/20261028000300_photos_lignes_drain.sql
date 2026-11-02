-- Photos des lignes et du drain obligatoires (ADR-093, décision de Simon) : en plus de la plaque et de l'appareil
-- installé (par appareil), chaque job doit avoir au moins une photo des lignes de réfrigérant (parcours, isolant,
-- recouvrement) et une du drain de condensat. Photos de la job, pas d'un appareil. Mêmes règles qu'avant :
-- sans elles, pas de facture finale du sous-traitant et pas d'étape « Terminé ».

alter table public.projet_photos drop constraint projet_photos_categorie_check;
alter table public.projet_photos add constraint projet_photos_categorie_check check (categorie in ('plaque','installe','lignes','drain','autre'));
alter table public.projet_photos drop constraint projet_photos_check;
alter table public.projet_photos add constraint projet_photos_check check (categorie in ('lignes','drain','autre') or equipement_id is not null);

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
  if not exists (select 1 from public.projet_photos where projet_id = p_projet and categorie = 'lignes' and statut in ('televersee','purgee')) then
    m := array_append(m, 'photo des lignes de réfrigérant');
  end if;
  if not exists (select 1 from public.projet_photos where projet_id = p_projet and categorie = 'drain' and statut in ('televersee','purgee')) then
    m := array_append(m, 'photo du drain de condensat');
  end if;
  return m;
end $$;

create or replace function public.hvac_job_photo_preparer(p_projet uuid, p_equipement uuid, p_categorie text, p_type text, p_taille integer) returns jsonb
language plpgsql security definer set search_path = public as $$
declare pr public.projets%rowtype; v_chemin text; v_id uuid;
begin
  pr := app.dossier_ouvert(p_projet);
  if p_categorie not in ('plaque','installe','lignes','drain','autre') then raise exception 'Catégorie de photo inconnue' using errcode = 'P0001'; end if;
  if p_equipement is null and p_categorie in ('plaque','installe') then raise exception 'Choisis l''appareil de la photo' using errcode = 'P0001'; end if;
  if p_categorie in ('lignes','drain') then p_equipement := null; end if;   -- photo de la job, pas d'un appareil
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
