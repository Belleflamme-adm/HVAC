-- CRM (ADR-058) : type de demande du lead et qualifications des vendeurs.
-- Simon choisit, pour chaque vendeur, les types qu'il peut prendre ; un lead d'un type donné va
-- à tour de rôle aux seuls vendeurs qualifiés (un tour de rôle par type). Personne de qualifié :
-- le lead reste non attribué dans le board principal (on ne « brûle » pas le client).
-- Type inconnu à l'arrivée : tour de rôle entre tous les vendeurs actifs du board (à confirmer par Simon).

alter table public.leads add column type_demande text
  check (type_demande in ('mural_simple','mural_multi','central','bienergie'));

create table public.crm_vendeur_types (
  employe_id   uuid not null references public.employes(id),
  type_demande text not null check (type_demande in ('mural_simple','mural_multi','central','bienergie')),
  created_at   timestamptz not null default now(),
  primary key (employe_id, type_demande)
);

-- Les vendeurs déjà au board restent qualifiés pour tout (aucun changement de comportement)
insert into public.crm_vendeur_types (employe_id, type_demande)
select v.employe_id, t from public.crm_vendeurs v
 cross join unnest(array['mural_simple','mural_multi','central','bienergie']) t
on conflict do nothing;

-- Un pointeur de tour de rôle par type (« tous » pour un type inconnu)
create table public.crm_tourniquet_types (
  cle             text primary key,
  dernier_employe uuid references public.employes(id),
  updated_at      timestamptz not null default now()
);
insert into public.crm_tourniquet_types (cle) values ('tous'),('mural_simple'),('mural_multi'),('central'),('bienergie');

create or replace function app.prochain_vendeur(p_type text) returns uuid
language plpgsql security definer set search_path = public as $$
declare v_cle text := coalesce(p_type, 'tous'); v_dernier uuid; v_ordre int; v_suivant uuid;
begin
  select dernier_employe into v_dernier from public.crm_tourniquet_types where cle = v_cle for update;
  select ordre into v_ordre from public.crm_vendeurs where employe_id = v_dernier;
  with candidats as (
    select v.employe_id, v.ordre
      from public.crm_vendeurs v join public.employes e on e.id = v.employe_id and e.actif
     where v.actif
       and (p_type is null or exists (select 1 from public.crm_vendeur_types q
                                       where q.employe_id = v.employe_id and q.type_demande = p_type)))
  select coalesce(
    (select employe_id from candidats where v_dernier is not null and (ordre, employe_id) > (coalesce(v_ordre, -1), v_dernier)
      order by ordre, employe_id limit 1),
    (select employe_id from candidats order by ordre, employe_id limit 1))
  into v_suivant;
  if v_suivant is not null then
    update public.crm_tourniquet_types set dernier_employe = v_suivant, updated_at = now() where cle = v_cle;
  end if;
  return v_suivant;
end $$;

-- Attribution à l'arrivée : selon le type de demande
create or replace function app.lead_avant() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    new.statut := 'nouveau';
    new.pris_en_charge_le := null; new.premier_contact_le := null; new.premier_contact_canal := null;
    if new.assigne_a is null then new.assigne_a := app.prochain_vendeur(new.type_demande); end if;
    if new.assigne_a is not null then new.attribue_le := now(); end if;
    return new;
  end if;
  if pg_trigger_depth() = 1 then
    new.recu_le := old.recu_le; new.attribue_le := old.attribue_le;
    new.pris_en_charge_le := old.pris_en_charge_le; new.premier_contact_le := old.premier_contact_le;
    new.premier_contact_canal := old.premier_contact_canal; new.visite_prevue_le := old.visite_prevue_le;
    new.perdu_le := old.perdu_le; new.statut := old.statut;
    if new.assigne_a is distinct from old.assigne_a or new.type_demande is distinct from old.type_demande then
      if not app.voit_board_crm() then
        raise exception 'Seul le responsable du board réattribue un lead ou change son type' using errcode = '42501';
      end if;
    end if;
    if new.assigne_a is distinct from old.assigne_a then
      new.attribue_le := case when new.assigne_a is null then null else now() end; new.pris_en_charge_le := null;
    end if;
  end if;
  return new;
end $$;

create or replace function app.lead_apres_insert() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.assigne_a is not null then
    insert into public.lead_activites (lead_id, type, employe_id, note)
    values (new.id, 'attribution', new.assigne_a, 'Attribué automatiquement (tour de rôle'
      || case when new.type_demande is not null then ', vendeurs qualifiés : ' || new.type_demande else '' end || ')');
  end if;
  return null;
end $$;

-- leads_v gagne type_demande (l.*) et vendeur_qualifie : les vues sont recréées à l'identique
-- (aucune donnée : ce sont des vues), crm_rapidite_v et crm_evaluation_v en dépendent.
drop view public.crm_evaluation_v;
drop view public.crm_rapidite_v;
drop view public.leads_v;
-- Qualification du vendeur assigné, pour avertir le board d'une attribution hors compétence
create view public.leads_v with (security_invoker = true) as
select l.*,
       e.prenom || ' ' || e.nom as vendeur_nom,
       extract(epoch from (l.pris_en_charge_le - l.recu_le)) / 60  as minutes_prise_en_charge,
       extract(epoch from (l.premier_contact_le - l.recu_le)) / 60 as minutes_premier_contact,
       extract(epoch from (coalesce(l.premier_contact_le, now()) - l.recu_le)) / 60 as minutes_en_attente,
       l.premier_contact_le is null and l.statut not in ('perdu','converti')
         and now() - l.recu_le > make_interval(mins => (select coalesce(seuil_moyen, seuil_bon)::int
                                                          from public.crm_objectifs where indicateur = 'minutes_premier_contact'))
         is true as en_retard,
       l.type_demande is null or l.assigne_a is null or exists (
         select 1 from public.crm_vendeur_types q where q.employe_id = l.assigne_a and q.type_demande = l.type_demande)
         as vendeur_qualifie
  from public.leads l left join public.employes e on e.id = l.assigne_a;

-- Chiffres réels par vendeur
create or replace view public.crm_rapidite_v with (security_invoker = true) as
select assigne_a as employe_id, vendeur_nom,
       count(*)                                                    as leads,
       count(*) filter (where premier_contact_le is not null)      as contactes,
       round((percentile_cont(0.5) within group (order by minutes_prise_en_charge))::numeric, 1) as minutes_prise_en_charge,
       round((percentile_cont(0.5) within group (order by minutes_premier_contact))::numeric, 1) as minutes_premier_contact,
       round(100.0 * count(*) filter (where premier_contact_le is not null) / count(*), 1)       as pct_contactes,
       round(100.0 * count(*) filter (where premier_contact_canal = 'appel')
             / nullif(count(*) filter (where premier_contact_le is not null), 0), 1)            as pct_premier_par_appel,
       round(100.0 * count(*) filter (where visite_prevue_le is not null) / count(*), 1)        as pct_visites,
       count(*) filter (where premier_contact_canal = 'appel')    as par_appel,
       count(*) filter (where premier_contact_canal = 'courriel') as par_courriel,
       count(*) filter (where premier_contact_canal = 'texto')    as par_texto
  from public.leads_v
 where assigne_a is not null
 group by assigne_a, vendeur_nom;

-- Comparaison au tableau de quantification : une ligne par vendeur et par indicateur
create or replace view public.crm_evaluation_v with (security_invoker = true) as
select r.employe_id, r.vendeur_nom, r.leads, o.indicateur, o.libelle, o.unite, o.sens, o.seuil_bon, o.seuil_moyen, o.ordre,
       v.valeur, app.cote(v.valeur, o.sens, o.seuil_bon, o.seuil_moyen) as cote
  from public.crm_rapidite_v r
  cross join public.crm_objectifs o
  cross join lateral (select case o.indicateur
       when 'minutes_prise_en_charge' then r.minutes_prise_en_charge
       when 'minutes_premier_contact' then r.minutes_premier_contact
       when 'pct_contactes'           then r.pct_contactes
       when 'pct_premier_par_appel'   then r.pct_premier_par_appel
       when 'pct_visites'             then r.pct_visites end as valeur) v;

alter table public.crm_vendeur_types enable row level security;
create policy lecture on public.crm_vendeur_types for select to authenticated using (app.est_commercial());
create policy ajout on public.crm_vendeur_types for insert to authenticated with check (app.voit_board_crm());
-- Retirer une qualification = retirer une ligne : réservé au board principal (journalisé)
create policy retrait on public.crm_vendeur_types for delete to authenticated using (app.voit_board_crm());
create trigger trg_audit after insert or delete on public.crm_vendeur_types
  for each row execute function app.audit();
alter table public.crm_tourniquet_types enable row level security;   -- fonctions seulement
