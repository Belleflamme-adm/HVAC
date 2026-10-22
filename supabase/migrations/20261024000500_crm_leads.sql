-- CRM des leads (ADR-056) : Google / Facebook -> Monday -> board principal de l'app.
-- - Le board principal (tous les leads) est la vérité ; chaque vendeur a sa vue (ses leads).
-- - Attribution automatique à tour de rôle entre les vendeurs du board (1, 2, 3, 1, 2, 3...).
-- - Chaque geste du vendeur est tracé (prise en charge, appel, courriel, texto, note, visite) ;
--   la rapidité d'exécution est mesurée à partir de ces traces horodatées par la base.
-- - La visite est planifiée dans Pointage (app de Mike) ; ici on en garde la date.

-- ---------------------------------------------------------------------------
-- Lead : champs de suivi
-- ---------------------------------------------------------------------------
alter table public.leads drop constraint leads_source_check;
alter table public.leads add constraint leads_source_check
  check (source in ('google','facebook','instagram','site_web','telephone','magasin','reference','salon','autre'));
alter table public.leads drop constraint leads_statut_check;
alter table public.leads add constraint leads_statut_check
  check (statut in ('nouveau','pris_en_charge','contacte','qualifie','inspection_planifiee','converti','perdu'));

alter table public.leads
  add column recu_le              timestamptz not null default now(),   -- arrivée (date Monday si importé)
  add column campagne             text,                                  -- campagne Google / Facebook
  add column ville                text,
  add column attribue_le          timestamptz,
  add column pris_en_charge_le    timestamptz,
  add column premier_contact_le   timestamptz,
  add column premier_contact_canal text check (premier_contact_canal in ('appel','courriel','texto')),
  add column visite_prevue_le     timestamptz,
  add column perdu_le             timestamptz;
create index on public.leads (assigne_a, statut);
create index on public.leads (recu_le desc);

-- ---------------------------------------------------------------------------
-- Vendeurs du board (le tour de rôle se fait entre les vendeurs actifs, par ordre)
-- ---------------------------------------------------------------------------
create table public.crm_vendeurs (
  employe_id  uuid primary key references public.employes(id),
  ordre       integer not null default 0,
  actif       boolean not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
call app.preparer_table('public.crm_vendeurs', false);

-- Pointeur du tour de rôle (une seule ligne, verrouillée à chaque attribution)
create table public.crm_tourniquet (
  id              boolean primary key default true check (id),
  dernier_employe uuid references public.employes(id),
  updated_at      timestamptz not null default now()
);
insert into public.crm_tourniquet (id) values (true);

create or replace function app.prochain_vendeur() returns uuid
language plpgsql security definer set search_path = public as $$
declare v_dernier uuid; v_ordre int; v_suivant uuid;
begin
  select dernier_employe into v_dernier from public.crm_tourniquet where id for update;
  select ordre into v_ordre from public.crm_vendeurs where employe_id = v_dernier;
  -- Le suivant après le dernier servi (ordre, puis id), sinon on recommence au premier
  select v.employe_id into v_suivant
    from public.crm_vendeurs v join public.employes e on e.id = v.employe_id and e.actif
   where v.actif and v_dernier is not null and (v.ordre, v.employe_id) > (coalesce(v_ordre, -1), v_dernier)
   order by v.ordre, v.employe_id limit 1;
  if v_suivant is null then
    select v.employe_id into v_suivant
      from public.crm_vendeurs v join public.employes e on e.id = v.employe_id and e.actif
     where v.actif order by v.ordre, v.employe_id limit 1;
  end if;
  if v_suivant is not null then
    update public.crm_tourniquet set dernier_employe = v_suivant, updated_at = now() where id;
  end if;
  return v_suivant;
end $$;

-- ---------------------------------------------------------------------------
-- Activités (journal du vendeur) : ajout seulement, jamais modifiées ni supprimées
-- ---------------------------------------------------------------------------
create table public.lead_activites (
  id          uuid primary key default gen_random_uuid(),
  lead_id     uuid not null references public.leads(id),
  type        text not null check (type in ('attribution','prise_en_charge','appel','courriel','texto','note',
                                            'visite_planifiee','perdu','reouvert')),
  resultat    text check (resultat in ('joint','message_laisse','pas_de_reponse','envoye')),
  note        text,
  visite_le   timestamptz,
  employe_id  uuid references public.employes(id) default app.employe_id(),
  fait_le     timestamptz not null default now(),
  created_at  timestamptz not null default now()
);
create index on public.lead_activites (lead_id, fait_le);

-- Attribution à l'arrivée : si personne n'est assigné, tour de rôle
create or replace function app.lead_avant() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    new.statut := 'nouveau';
    new.pris_en_charge_le := null; new.premier_contact_le := null; new.premier_contact_canal := null;
    if new.assigne_a is null then new.assigne_a := app.prochain_vendeur(); end if;
    if new.assigne_a is not null then new.attribue_le := now(); end if;
    return new;
  end if;
  -- Les horodatages de suivi viennent des activités (triggers imbriqués), jamais d'une saisie directe
  if pg_trigger_depth() = 1 then
    new.recu_le := old.recu_le; new.attribue_le := old.attribue_le;
    new.pris_en_charge_le := old.pris_en_charge_le; new.premier_contact_le := old.premier_contact_le;
    new.premier_contact_canal := old.premier_contact_canal; new.visite_prevue_le := old.visite_prevue_le;
    new.perdu_le := old.perdu_le; new.statut := old.statut;
    if new.assigne_a is distinct from old.assigne_a then
      -- Réattribution : seulement le board principal (admin, direction, gérant, coordonnateur)
      if not app.voit_board_crm() then
        raise exception 'Seul le responsable du board réattribue un lead' using errcode = '42501';
      end if;
      new.attribue_le := now(); new.pris_en_charge_le := null;
    end if;
  end if;
  return new;
end $$;
create trigger trg_lead_avant before insert or update on public.leads
  for each row execute function app.lead_avant();

create or replace function app.lead_apres_insert() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.assigne_a is not null then
    insert into public.lead_activites (lead_id, type, employe_id, note)
    values (new.id, 'attribution', new.assigne_a, 'Attribué automatiquement (tour de rôle)');
  end if;
  return null;
end $$;
create trigger trg_lead_apres_insert after insert on public.leads
  for each row execute function app.lead_apres_insert();

-- Une activité fait avancer le lead et horodate la rapidité
create or replace function app.lead_activite_avant() returns trigger
language plpgsql security definer set search_path = public as $$
declare l public.leads%rowtype;
begin
  if tg_op <> 'INSERT' then
    raise exception 'Le journal du lead ne se modifie pas' using errcode = '42501';
  end if;
  select * into l from public.leads where id = new.lead_id;
  new.fait_le := now();                       -- l'heure vient de la base, pas du téléphone
  if new.type in ('appel','courriel','texto') and new.resultat is null then
    new.resultat := case when new.type = 'appel' then 'joint' else 'envoye' end;
  end if;
  if new.type = 'visite_planifiee' and new.visite_le is null then
    raise exception 'Date de visite requise (planifiée dans Pointage)' using errcode = 'P0001';
  end if;
  if new.type = 'perdu' and coalesce(trim(new.note), '') = '' then
    raise exception 'Raison de la perte requise' using errcode = 'P0001';
  end if;
  if new.type = 'prise_en_charge' and l.assigne_a is distinct from app.employe_id() and not app.voit_board_crm() then
    raise exception 'Ce lead est attribué à un autre vendeur' using errcode = '42501';
  end if;
  return new;
end $$;
create trigger trg_lead_activite_avant before insert or update or delete on public.lead_activites
  for each row execute function app.lead_activite_avant();

create or replace function app.lead_activite_apres() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  update public.leads l set
    pris_en_charge_le = case when new.type in ('prise_en_charge','appel','courriel','texto','visite_planifiee')
                             then coalesce(l.pris_en_charge_le, new.fait_le) else l.pris_en_charge_le end,
    premier_contact_le = case when new.type in ('appel','courriel','texto') and l.premier_contact_le is null
                              then new.fait_le else l.premier_contact_le end,
    premier_contact_canal = case when new.type in ('appel','courriel','texto') and l.premier_contact_le is null
                                 then new.type else l.premier_contact_canal end,
    visite_prevue_le = case when new.type = 'visite_planifiee' then new.visite_le else l.visite_prevue_le end,
    perdu_le = case when new.type = 'perdu' then new.fait_le when new.type = 'reouvert' then null else l.perdu_le end,
    raison_perte = case when new.type = 'perdu' then new.note else l.raison_perte end,
    statut = case
      when new.type = 'perdu' then 'perdu'
      when new.type = 'reouvert' then case when l.premier_contact_le is not null then 'contacte' else 'pris_en_charge' end
      when l.statut in ('converti','perdu') then l.statut
      when new.type = 'visite_planifiee' then 'inspection_planifiee'
      when new.type in ('appel','courriel','texto') and l.statut in ('nouveau','pris_en_charge') then 'contacte'
      when new.type = 'prise_en_charge' and l.statut = 'nouveau' then 'pris_en_charge'
      else l.statut end
  where l.id = new.lead_id;
  return null;
end $$;
create trigger trg_lead_activite_apres after insert on public.lead_activites
  for each row execute function app.lead_activite_apres();

-- ---------------------------------------------------------------------------
-- Rapidité d'exécution et tableau de quantification (ADR-056)
-- Simon et Mike inscrivent les seuils attendus ; l'app compare les chiffres réels de chaque
-- vendeur et le classe « bon », « moyen » ou « à améliorer ». Seuils vides = « non évalué ».
-- ---------------------------------------------------------------------------
insert into public.parametres (cle, valeur, description) values
  ('url_pointage', '"https://belleflammetime.netlify.app"', 'Pointage (app de Mike) : la visite y est planifiée. Lien seulement, aucune connexion.')
on conflict (cle) do nothing;

create table public.crm_objectifs (
  indicateur   text primary key,
  libelle      text not null,
  unite        text not null check (unite in ('minutes','pourcent')),
  sens         text not null check (sens in ('bas','haut')),   -- bas : plus petit = mieux (délais)
  seuil_bon    numeric,                                         -- atteint ou mieux -> « bon »
  seuil_moyen  numeric,                                         -- atteint ou mieux -> « moyen », sinon « à améliorer »
  ordre        integer not null default 0,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  check (seuil_bon is null or seuil_moyen is null
         or (sens = 'bas' and seuil_bon <= seuil_moyen) or (sens = 'haut' and seuil_bon >= seuil_moyen))
);
call app.preparer_table('public.crm_objectifs', false);
insert into public.crm_objectifs (indicateur, libelle, unite, sens, ordre) values
  ('minutes_prise_en_charge', 'Délai de prise en charge (médiane)',         'minutes',  'bas',  1),
  ('minutes_premier_contact', 'Délai du premier contact (médiane)',          'minutes',  'bas',  2),
  ('pct_contactes',           'Leads contactés',                             'pourcent', 'haut', 3),
  ('pct_premier_par_appel',   'Premier contact fait par appel téléphonique', 'pourcent', 'haut', 4),
  ('pct_visites',             'Leads avec visite planifiée',                 'pourcent', 'haut', 5);

create or replace function app.cote(p_valeur numeric, p_sens text, p_bon numeric, p_moyen numeric) returns text
language sql immutable as $$
  select case
    when p_valeur is null or (p_bon is null and p_moyen is null) then 'non_evalue'
    when p_sens = 'bas'  and p_bon   is not null and p_valeur <= p_bon   then 'bon'
    when p_sens = 'haut' and p_bon   is not null and p_valeur >= p_bon   then 'bon'
    when p_sens = 'bas'  and p_moyen is not null and p_valeur <= p_moyen then 'moyen'
    when p_sens = 'haut' and p_moyen is not null and p_valeur >= p_moyen then 'moyen'
    when p_moyen is null then 'moyen'          -- seulement le seuil « bon » saisi
    else 'a_ameliorer' end
$$;

create or replace view public.leads_v with (security_invoker = true) as
select l.*,
       e.prenom || ' ' || e.nom as vendeur_nom,
       extract(epoch from (l.pris_en_charge_le - l.recu_le)) / 60  as minutes_prise_en_charge,
       extract(epoch from (l.premier_contact_le - l.recu_le)) / 60 as minutes_premier_contact,
       extract(epoch from (coalesce(l.premier_contact_le, now()) - l.recu_le)) / 60 as minutes_en_attente,
       -- En retard : pas encore contacté et le seuil « moyen » du premier contact est dépassé
       l.premier_contact_le is null and l.statut not in ('perdu','converti')
         and now() - l.recu_le > make_interval(mins => (select coalesce(seuil_moyen, seuil_bon)::int
                                                          from public.crm_objectifs where indicateur = 'minutes_premier_contact'))
         is true as en_retard
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

-- ---------------------------------------------------------------------------
-- Accès : board principal (tous les leads) ou vue du vendeur (ses leads)
-- ---------------------------------------------------------------------------
create or replace function app.voit_board_crm() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(app.role() in ('Admin tout','Direction','Gérant de succursale','Coordonnateur'), false)
$$;

drop policy lecture on public.leads;
drop policy ajout on public.leads;
drop policy maj on public.leads;
create policy lecture on public.leads for select to authenticated
  using (app.voit_board_crm() or assigne_a = app.employe_id());
create policy ajout on public.leads for insert to authenticated
  with check (app.est_commercial());
create policy maj on public.leads for update to authenticated
  using (app.voit_board_crm() or assigne_a = app.employe_id())
  with check (app.voit_board_crm() or assigne_a = app.employe_id());

alter table public.lead_activites enable row level security;
create policy lecture on public.lead_activites for select to authenticated
  using (exists (select 1 from public.leads l where l.id = lead_id));        -- hérite de la RLS des leads
create policy ajout on public.lead_activites for insert to authenticated
  with check (exists (select 1 from public.leads l where l.id = lead_id) and employe_id = app.employe_id()
              and type <> 'attribution');

alter table public.crm_vendeurs enable row level security;
create policy lecture on public.crm_vendeurs for select to authenticated using (app.est_commercial());
create policy gestion on public.crm_vendeurs for all to authenticated
  using (app.voit_board_crm()) with check (app.voit_board_crm());
alter table public.crm_tourniquet enable row level security;   -- aucune politique : fonctions seulement

alter table public.crm_objectifs enable row level security;
create policy lecture on public.crm_objectifs for select to authenticated using (app.est_commercial());
create policy maj on public.crm_objectifs for update to authenticated
  using (app.voit_board_crm()) with check (app.voit_board_crm());

create trigger trg_audit after insert or update or delete on public.crm_vendeurs
  for each row execute function app.audit();
create trigger trg_audit after update on public.crm_objectifs
  for each row execute function app.audit();
