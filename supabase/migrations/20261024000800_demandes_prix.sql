-- Demandes de prix aux sous-traitants (ADR-061).
-- 1. Simon (ou Mike, ou la planification) coche les travaux à chiffrer pour un sous-traitant : demande + lignes
--    (copie figée du code, du titre, de la description et de l'unité au moment de l'envoi).
-- 2. Un lien unique (jeton de 64 caractères, seulement son empreinte SHA-256 est gardée) est envoyé au sous-traitant.
-- 3. Le sous-traitant, SANS compte, remplit ses coûts, signe (nom + signature dessinée), la date est celle du serveur ;
--    il atteste que ses prix sont valides un an complet à partir de cette date. Le lien ne sert qu'une fois.
-- 4. Simon révise et approuve : les prix deviennent des tarifs datés (valides jusqu'à la date d'échéance).
-- Accès public : uniquement par les fonctions hvac_demande_prix_lire / _soumettre (jeton), aucune table ouverte à anon.

-- Édition des lignes de la liste par Simon et Mike (la RLS « maj_admin » existe déjà) : on journalise
create trigger trg_audit after update on public.types_travaux
  for each row execute function app.audit();

alter table public.tarifs_sous_traitants
  add column valide_jusqu date,
  add column demande_prix_id uuid;

create table public.demandes_prix (
  id              uuid primary key default gen_random_uuid(),
  fournisseur_id  uuid not null references public.fournisseurs(id),
  jeton_hash      text not null unique,
  statut          text not null default 'envoyee' check (statut in ('envoyee','recue','approuvee','annulee')),
  message         text,
  expire_le       timestamptz not null default now() + interval '30 days',
  cree_par        uuid references public.employes(id) default app.employe_id(),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  ouverte_le      timestamptz,
  signataire_nom  text,
  signature_png   text check (signature_png is null or (signature_png like 'data:image/png;base64,%' and length(signature_png) < 300000)),
  signe_le        timestamptz,
  valide_jusqu    date,
  ip_signature    text,
  approuvee_par   uuid references public.employes(id),
  approuvee_le    timestamptz,
  check ((statut in ('recue','approuvee')) = (signe_le is not null))
);
call app.preparer_table('public.demandes_prix', false);
alter table public.tarifs_sous_traitants add constraint tarifs_demande_fk foreign key (demande_prix_id) references public.demandes_prix(id);

create table public.demandes_prix_lignes (
  id              uuid primary key default gen_random_uuid(),
  demande_id      uuid not null references public.demandes_prix(id),
  type_travail_id uuid not null references public.types_travaux(id),
  code            text not null,
  nom             text not null,
  description     text,
  unite           text not null,
  categorie       text,
  ordre           integer not null default 0,
  cout_cents      bigint check (cout_cents is null or cout_cents > 0),
  non_offert      boolean not null default false,
  note            text,
  unique (demande_id, type_travail_id),
  check (not (non_offert and cout_cents is not null))
);

-- Création (connecté) : retourne le jeton EN CLAIR une seule fois
create or replace function public.hvac_creer_demande_prix(p_fournisseur uuid, p_types uuid[], p_message text default null)
returns table (id uuid, jeton text, expire_le timestamptz)
language plpgsql security definer set search_path = public as $$
declare v_jeton text := replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', ''); v_id uuid; v_exp timestamptz;
begin
  if not (app.est_admin() or app.est_planification()) then
    raise exception 'Seuls Simon, Mike et la planification envoient une demande de prix' using errcode = '42501';
  end if;
  if coalesce(array_length(p_types, 1), 0) = 0 then
    raise exception 'Coche au moins un travail' using errcode = 'P0001';
  end if;
  if not exists (select 1 from public.fournisseurs f where f.id = p_fournisseur and f.type in ('sous-traitant','les deux')) then
    raise exception 'Sous-traitant introuvable' using errcode = 'P0002';
  end if;
  insert into public.demandes_prix (fournisseur_id, jeton_hash, message)
  values (p_fournisseur, encode(sha256(convert_to(v_jeton, 'UTF8')), 'hex'), nullif(trim(p_message), ''))
  returning demandes_prix.id, demandes_prix.expire_le into v_id, v_exp;
  insert into public.demandes_prix_lignes (demande_id, type_travail_id, code, nom, description, unite, categorie, ordre)
  select v_id, t.id, t.code, t.nom, t.description, t.unite, t.categorie, t.ordre
    from public.types_travaux t where t.id = any(p_types) and t.actif;
  return query select v_id, v_jeton, v_exp;
end $$;

create or replace function app.demande_par_jeton(p_jeton text) returns public.demandes_prix
language sql stable security definer set search_path = public as $$
  select * from public.demandes_prix where jeton_hash = encode(sha256(convert_to(coalesce(p_jeton, ''), 'UTF8')), 'hex')
$$;

-- Lecture publique par le sous-traitant (jeton)
create or replace function public.hvac_demande_prix_lire(p_jeton text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare d public.demandes_prix;
begin
  d := app.demande_par_jeton(p_jeton);
  if d.id is null or d.statut = 'annulee' then
    raise exception 'Lien invalide ou annulé. Communique avec Belleflamme.' using errcode = 'P0002';
  end if;
  if d.statut = 'envoyee' and d.expire_le < now() then
    raise exception 'Ce lien est expiré. Demande un nouveau lien à Belleflamme.' using errcode = 'P0001';
  end if;
  if d.ouverte_le is null then
    perform set_config('app.demande_prix_fonction', 'oui', true);
    update public.demandes_prix set ouverte_le = now() where id = d.id;
    perform set_config('app.demande_prix_fonction', '', true);
  end if;
  return jsonb_build_object(
    'statut', d.statut, 'message', d.message, 'expire_le', d.expire_le,
    'fournisseur', (select nom from public.fournisseurs where id = d.fournisseur_id),
    'signataire_nom', d.signataire_nom, 'signe_le', d.signe_le, 'valide_jusqu', d.valide_jusqu,
    'categories', (select coalesce(jsonb_agg(jsonb_build_object('code', c.code, 'nom', c.nom) order by c.ordre), '[]') from public.categories_travaux c),
    'lignes', (select coalesce(jsonb_agg(jsonb_build_object('id', l.id, 'code', l.code, 'nom', l.nom, 'description', l.description,
                 'unite', l.unite, 'categorie', l.categorie, 'cout_cents', l.cout_cents, 'non_offert', l.non_offert, 'note', l.note) order by l.ordre), '[]')
               from public.demandes_prix_lignes l where l.demande_id = d.id));
end $$;

-- Soumission publique : une seule fois, toutes les lignes répondues (prix ou « non offert »), nom et signature
-- p_lignes : [{ id, cout_cents | null, non_offert, note }]
create or replace function public.hvac_demande_prix_soumettre(p_jeton text, p_lignes jsonb, p_nom text, p_signature text, p_atteste boolean)
returns jsonb language plpgsql security definer set search_path = public as $$
declare d public.demandes_prix; v_jour date := (now() at time zone 'America/Toronto')::date; v_ip text; l jsonb;
begin
  d := app.demande_par_jeton(p_jeton);
  if d.id is null or d.statut = 'annulee' then raise exception 'Lien invalide ou annulé' using errcode = 'P0002'; end if;
  if d.statut <> 'envoyee' then raise exception 'Cette liste de prix a déjà été envoyée le %', to_char(d.signe_le at time zone 'America/Toronto', 'YYYY-MM-DD') using errcode = 'P0001'; end if;
  if d.expire_le < now() then raise exception 'Ce lien est expiré' using errcode = 'P0001'; end if;
  if coalesce(length(trim(p_nom)), 0) < 3 then raise exception 'Nom du signataire requis' using errcode = 'P0001'; end if;
  if p_signature is null or p_signature not like 'data:image/png;base64,%' then raise exception 'Signature requise' using errcode = 'P0001'; end if;
  if not coalesce(p_atteste, false) then raise exception 'Il faut confirmer que les prix sont valides un an' using errcode = 'P0001'; end if;

  perform set_config('app.demande_prix_fonction', 'oui', true);
  for l in select * from jsonb_array_elements(coalesce(p_lignes, '[]')) loop
    update public.demandes_prix_lignes set
      cout_cents = case when coalesce((l->>'non_offert')::boolean, false) then null else nullif(l->>'cout_cents', '')::bigint end,
      non_offert = coalesce((l->>'non_offert')::boolean, false),
      note = left(nullif(trim(l->>'note'), ''), 300)
    where id = (l->>'id')::uuid and demande_id = d.id;
  end loop;
  if exists (select 1 from public.demandes_prix_lignes where demande_id = d.id and cout_cents is null and not non_offert) then
    raise exception 'Chaque ligne doit avoir un prix ou être marquée « je n''offre pas ce service »' using errcode = 'P0001';
  end if;

  begin v_ip := split_part(current_setting('request.headers', true)::json->>'x-forwarded-for', ',', 1);
  exception when others then v_ip := null; end;
  update public.demandes_prix set statut = 'recue', signataire_nom = trim(p_nom), signature_png = p_signature,
         signe_le = now(), valide_jusqu = (v_jour + interval '1 year')::date, ip_signature = nullif(v_ip, '')
   where id = d.id;
  -- Alerte dans l'app pour Simon et Mike
  insert into public.notifications (destinataire_employe_id, type, titre, message, lien)
  select e.id, 'prix_recus', 'Liste de prix reçue', (select nom from public.fournisseurs where id = d.fournisseur_id) || ' a envoyé ses prix.',
         '/demande-prix?id=' || d.id
    from public.employes e where e.actif and e.role = 'Admin tout';
  perform set_config('app.demande_prix_fonction', '', true);
  return jsonb_build_object('ok', true, 'signe_le', now(), 'valide_jusqu', (v_jour + interval '1 year')::date);
end $$;

-- Approbation : les prix deviennent des tarifs datés, valides jusqu'à l'échéance d'un an
create or replace function public.hvac_approuver_demande_prix(p_demande uuid) returns integer
language plpgsql security definer set search_path = public as $$
declare d public.demandes_prix; n integer;
begin
  if not app.est_admin() then raise exception 'Seuls Simon et Mike approuvent une liste de prix' using errcode = '42501'; end if;
  select * into d from public.demandes_prix where id = p_demande for update;
  if d.statut <> 'recue' then raise exception 'Seule une liste reçue s''approuve (statut : %)', d.statut using errcode = 'P0001'; end if;
  insert into public.tarifs_sous_traitants (fournisseur_id, type_travail_id, cout_cents, en_vigueur_du, valide_jusqu, demande_prix_id, notes)
  select d.fournisseur_id, l.type_travail_id, l.cout_cents, (d.signe_le at time zone 'America/Toronto')::date, d.valide_jusqu, d.id,
         'Liste signée par ' || d.signataire_nom
    from public.demandes_prix_lignes l where l.demande_id = d.id and l.cout_cents is not null
  on conflict (fournisseur_id, type_travail_id, en_vigueur_du) do nothing;
  get diagnostics n = row_count;
  perform set_config('app.demande_prix_fonction', 'oui', true);
  update public.demandes_prix set statut = 'approuvee', approuvee_par = app.employe_id(), approuvee_le = now() where id = d.id;
  perform set_config('app.demande_prix_fonction', '', true);
  return n;
end $$;

-- Garde : seules les fonctions ci-dessus (drapeau de transaction) remplissent, signent et approuvent ;
-- un utilisateur ne peut qu'annuler. Les lignes ne se modifient que par le lien du sous-traitant.
create or replace function app.demande_prix_garde() returns trigger
language plpgsql as $$
begin
  if coalesce(current_setting('app.demande_prix_fonction', true), '') <> 'oui' then
    if (new.jeton_hash, new.fournisseur_id, new.signataire_nom, new.signature_png, new.signe_le, new.valide_jusqu, new.ip_signature)
       is distinct from (old.jeton_hash, old.fournisseur_id, old.signataire_nom, old.signature_png, old.signe_le, old.valide_jusqu, old.ip_signature) then
      raise exception 'Une demande de prix ne se modifie pas' using errcode = '42501';
    end if;
    if new.statut is distinct from old.statut and not (new.statut = 'annulee' and old.statut in ('envoyee','recue')) then
      raise exception 'Seule l''annulation se fait ici ; l''approbation passe par hvac_approuver_demande_prix' using errcode = '42501';
    end if;
  end if;
  return new;
end $$;
create trigger trg_demande_prix_garde before update on public.demandes_prix for each row execute function app.demande_prix_garde();
create trigger trg_demande_prix_delete before delete on public.demandes_prix for each row execute function app.interdit();
create trigger trg_audit after insert or update on public.demandes_prix for each row execute function app.audit();

create or replace function app.demande_ligne_garde() returns trigger
language plpgsql as $$
begin
  if coalesce(current_setting('app.demande_prix_fonction', true), '') <> 'oui' then raise exception 'Les lignes d''une demande se remplissent par le lien du sous-traitant' using errcode = '42501'; end if;
  return new;
end $$;
create trigger trg_demande_ligne_garde before update or delete on public.demandes_prix_lignes for each row execute function app.demande_ligne_garde();

alter table public.demandes_prix enable row level security;
alter table public.demandes_prix_lignes enable row level security;
revoke all on public.demandes_prix, public.demandes_prix_lignes from anon;
create policy lecture on public.demandes_prix for select to authenticated using (app.est_admin() or app.est_planification());
create policy annulation on public.demandes_prix for update to authenticated
  using (app.est_admin() or app.est_planification()) with check (app.est_admin() or app.est_planification());
create policy lecture on public.demandes_prix_lignes for select to authenticated
  using (exists (select 1 from public.demandes_prix d where d.id = demande_id));

revoke all on function public.hvac_creer_demande_prix(uuid, uuid[], text) from public, anon;
grant execute on function public.hvac_creer_demande_prix(uuid, uuid[], text) to authenticated;
grant execute on function public.hvac_demande_prix_lire(text) to anon, authenticated;
grant execute on function public.hvac_demande_prix_soumettre(text, jsonb, text, text, boolean) to anon, authenticated;
revoke all on function public.hvac_approuver_demande_prix(uuid) from public, anon;
grant execute on function public.hvac_approuver_demande_prix(uuid) to authenticated;
