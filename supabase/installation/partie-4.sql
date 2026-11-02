-- Installation HVAC Belleflamme | partie 4 sur 6 | à coller dans Supabase > SQL Editor > Run
-- Généré depuis supabase/migrations (commentaires retirés). Les parties s'exécutent DANS L'ORDRE, une seule fois.

-- ===== 20261024000400_taxes_ontario_autochtone.sql =====
alter table public.taux_taxes drop constraint taux_taxes_code_check;
alter table public.taux_taxes add constraint taux_taxes_code_check check (code in ('TPS','TVQ','TVH_ON'));
insert into public.taux_taxes (code, taux_pcm, en_vigueur_du) values ('TVH_ON', 13000, '2010-07-01')
on conflict do nothing;
alter table public.devis
  add column regime_taxes text not null default 'QC' check (regime_taxes in ('QC','ON')),
  add column autochtone boolean not null default false,
  add column autochtone_no_registre text,
  add column tvh_cents bigint not null default 0;
alter table public.factures
  add column regime_taxes text not null default 'QC' check (regime_taxes in ('QC','ON')),
  add column autochtone boolean not null default false,
  add column autochtone_no_registre text,
  add column tvh_cents bigint not null default 0;
create or replace function app.taxes_regime(
  p_montant bigint, p_date date, p_regime text, p_exempt_tps boolean, p_exempt_tvq boolean, p_autochtone boolean,
  out tps bigint, out tvq bigint, out tvh bigint
) language plpgsql stable as $$
begin
  tps := 0; tvq := 0; tvh := 0;
  if p_autochtone then return; end if;
  if p_regime = 'ON' then
    if not (p_exempt_tps and p_exempt_tvq) then tvh := app.arrondi_taxe(p_montant, app.taux_pcm('TVH_ON', p_date)); end if;
    return;
  end if;
  select t.tps, t.tvq into tps, tvq from app.taxes(p_montant, p_date, p_exempt_tps, p_exempt_tvq) t;
end $$;
create or replace function app.recalculer_devis(p_devis uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  d public.devis%rowtype; c public.clients%rowtype;
  v_base bigint; v_brut bigint; v_net bigint; v_taxable bigint; v_tps bigint; v_tvq bigint; v_tvh bigint;
begin
  select * into d from public.devis where id = p_devis;
  select * into c from public.clients where id = d.client_id;
  if d.statut = 'brouillon' then
    select coalesce(sum(montant_cents), 0) into v_base from public.devis_lignes
     where devis_id = p_devis and type_ligne <> 'rabais';
    update public.devis_lignes
       set prix_unitaire_cents = -round(v_base * rabais_valeur / 10000.0)::bigint
     where devis_id = p_devis and type_ligne = 'rabais' and rabais_mode = 'pourcentage'
       and prix_unitaire_cents <> -round(v_base * rabais_valeur / 10000.0)::bigint;
  end if;
  select coalesce(sum(round(quantite * prix_unitaire_cents)::bigint) filter (where type_ligne <> 'rabais'), 0),
         coalesce(sum(montant_cents), 0),
         coalesce(sum(montant_cents) filter (where taxable), 0)
    into v_brut, v_net, v_taxable
    from public.devis_lignes where devis_id = p_devis;
  if v_net < 0 then
    raise exception 'Le rabais global dépasse le sous-total du devis' using errcode = 'P0001';
  end if;
  select t.tps, t.tvq, t.tvh into v_tps, v_tvq, v_tvh
    from app.taxes_regime(greatest(v_taxable, 0), d.date_devis, d.regime_taxes,
                          c.exemption_tps, c.exemption_tvq, d.autochtone) t;
  update public.devis set
    sous_total_cents = v_net,
    rabais_cents     = v_brut - v_net,
    tps_cents        = v_tps,
    tvq_cents        = v_tvq,
    tvh_cents        = v_tvh,
    total_cents      = v_net + v_tps + v_tvq + v_tvh,
    depot_cents      = round((v_net + v_tps + v_tvq + v_tvh) * depot_bp / 10000.0)::bigint
  where id = p_devis;
end $$;
create or replace function app.recalculer_facture(p_facture uuid) returns void
language plpgsql security definer set search_path = public as $$
declare f public.factures%rowtype; c public.clients%rowtype;
        v_net bigint; v_taxable bigint; v_tps bigint; v_tvq bigint; v_tvh bigint;
begin
  select * into f from public.factures where id = p_facture;
  select * into c from public.clients where id = f.client_id;
  select coalesce(sum(montant_cents), 0), coalesce(sum(montant_cents) filter (where taxable), 0)
    into v_net, v_taxable from public.facture_lignes where facture_id = p_facture;
  select t.tps, t.tvq, t.tvh into v_tps, v_tvq, v_tvh
    from app.taxes_regime(v_taxable, coalesce(f.emise_le, now())::date, f.regime_taxes,
                          c.exemption_tps, c.exemption_tvq, f.autochtone) t;
  update public.factures set sous_total_cents = v_net, tps_cents = v_tps, tvq_cents = v_tvq, tvh_cents = v_tvh,
         total_cents = v_net + v_tps + v_tvq + v_tvh
   where id = p_facture;
end $$;
create or replace function app.devis_regime_avant() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    if new.regime_taxes = 'QC' and exists (select 1 from public.sites s where s.id = new.site_id and s.province = 'ON') then
      new.regime_taxes := 'ON';
    end if;
    if not new.autochtone and exists (select 1 from public.clients c where c.id = new.client_id and c.exemption_taxes = 'autochtone') then
      new.autochtone := true;
      new.autochtone_no_registre := coalesce(new.autochtone_no_registre,
        (select exemption_numero from public.clients where id = new.client_id));
    end if;
    new.tvh_cents := 0;
    return new;
  end if;
  if pg_trigger_depth() = 1 then new.tvh_cents := old.tvh_cents; end if;
  if (new.regime_taxes, new.autochtone, new.autochtone_no_registre)
     is distinct from (old.regime_taxes, old.autochtone, old.autochtone_no_registre)
     and old.statut <> 'brouillon' then
    raise exception 'Devis non modifiable (statut %) : les taxes sont figées', old.statut using errcode = '42501';
  end if;
  if new.statut = 'envoye' and old.statut = 'brouillon' then
    if exists (select 1 from public.sites s where s.id = new.site_id and s.province <> new.regime_taxes
                                              and s.province in ('QC','ON')) then
      raise exception 'Devis % : le chantier est en % mais les taxes sont celles de %. Corriger la case « Vente Ontario ».',
        new.numero, (select province from public.sites where id = new.site_id), new.regime_taxes using errcode = 'P0001';
    end if;
  end if;
  return new;
end $$;
create trigger trg_devis_regime_avant before insert or update on public.devis
  for each row execute function app.devis_regime_avant();
create or replace function app.devis_regime_apres() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform app.recalculer_devis(new.id);
  return null;
end $$;
create trigger trg_devis_regime_apres after update of regime_taxes, autochtone on public.devis
  for each row when ((new.regime_taxes, new.autochtone) is distinct from (old.regime_taxes, old.autochtone))
  execute function app.devis_regime_apres();
create or replace function app.facture_regime_avant() returns trigger
language plpgsql security definer set search_path = public as $$
declare d public.devis%rowtype;
begin
  if tg_op = 'INSERT' then
    select * into d from public.devis
     where id = coalesce(new.devis_id, (select devis_id from public.projets where id = new.projet_id));
    if found then
      new.regime_taxes := d.regime_taxes; new.autochtone := d.autochtone;
      new.autochtone_no_registre := d.autochtone_no_registre;
    end if;
    new.tvh_cents := 0;
    return new;
  end if;
  if pg_trigger_depth() = 1 then new.tvh_cents := old.tvh_cents; end if;
  if (new.regime_taxes, new.autochtone, new.autochtone_no_registre, new.tvh_cents)
     is distinct from (old.regime_taxes, old.autochtone, old.autochtone_no_registre, old.tvh_cents)
     and old.statut <> 'brouillon' then
    raise exception 'Facture émise : non modifiable. Faire une note de crédit.' using errcode = '42501';
  end if;
  return new;
end $$;
create trigger trg_facture_regime_avant before insert or update on public.factures
  for each row execute function app.facture_regime_avant();
create or replace function app.facture_regime_apres() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform app.recalculer_facture(new.id);
  return null;
end $$;
create trigger trg_facture_regime_apres after update of regime_taxes, autochtone on public.factures
  for each row when ((new.regime_taxes, new.autochtone) is distinct from (old.regime_taxes, old.autochtone))
  execute function app.facture_regime_apres();

-- ===== 20261024000500_crm_leads.sql =====
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
create table public.crm_vendeurs (
  employe_id  uuid primary key references public.employes(id),
  ordre       integer not null default 0,
  actif       boolean not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
call app.preparer_table('public.crm_vendeurs', false);
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
  if pg_trigger_depth() = 1 then
    new.recu_le := old.recu_le; new.attribue_le := old.attribue_le;
    new.pris_en_charge_le := old.pris_en_charge_le; new.premier_contact_le := old.premier_contact_le;
    new.premier_contact_canal := old.premier_contact_canal; new.visite_prevue_le := old.visite_prevue_le;
    new.perdu_le := old.perdu_le; new.statut := old.statut;
    if new.assigne_a is distinct from old.assigne_a then
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
       l.premier_contact_le is null and l.statut not in ('perdu','converti')
         and now() - l.recu_le > make_interval(mins => (select coalesce(seuil_moyen, seuil_bon)::int
                                                          from public.crm_objectifs where indicateur = 'minutes_premier_contact'))
         is true as en_retard
  from public.leads l left join public.employes e on e.id = l.assigne_a;
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

-- ===== 20261024000600_crm_types_demande.sql =====
alter table public.leads add column type_demande text
  check (type_demande in ('mural_simple','mural_multi','central','bienergie'));
create table public.crm_vendeur_types (
  employe_id   uuid not null references public.employes(id),
  type_demande text not null check (type_demande in ('mural_simple','mural_multi','central','bienergie')),
  created_at   timestamptz not null default now(),
  primary key (employe_id, type_demande)
);
insert into public.crm_vendeur_types (employe_id, type_demande)
select v.employe_id, t from public.crm_vendeurs v
 cross join unnest(array['mural_simple','mural_multi','central','bienergie']) t
on conflict do nothing;
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
drop view public.crm_evaluation_v;
drop view public.crm_rapidite_v;
drop view public.leads_v;
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
create policy retrait on public.crm_vendeur_types for delete to authenticated using (app.voit_board_crm());
create trigger trg_audit after insert or delete on public.crm_vendeur_types
  for each row execute function app.audit();
alter table public.crm_tourniquet_types enable row level security;   -- fonctions seulement

-- ===== 20261024000700_liste_prix_installation.sql =====
alter table public.types_travaux
  add column categorie text,
  add column unite text not null default 'forfait' check (unite in ('forfait','tete','pied','sortie','heure','unite','livre')),
  add column ordre integer not null default 0;
create table public.categories_travaux (
  code   text primary key,
  nom    text not null,
  ordre  integer not null
);
alter table public.categories_travaux enable row level security;
create policy lecture on public.categories_travaux for select to authenticated using (app.employe_id() is not null);
insert into public.categories_travaux (code, nom, ordre) values
  ('murale', 'Thermopompe murale | installation neuve', 1),
  ('tetes', 'Têtes intérieures spéciales (supplément par tête)', 2),
  ('central', 'Système central | installation neuve', 3),
  ('remplacement', 'Remplacements', 4),
  ('bienergie', 'Biénergie', 5),
  ('huile', 'Conversion de l''huile', 6),
  ('ventilation', 'Ventilation | échangeur d''air', 7),
  ('extras', 'Extras et options d''installation', 8),
  ('conduits', 'Conduits', 9),
  ('electricite', 'Électricité (maître électricien, licence CMEQ)', 10),
  ('gaz', 'Gaz naturel et propane (licence gaz requise)', 11),
  ('retrait', 'Retrait et disposition', 12),
  ('service', 'Service et entretien', 13);
alter table public.types_travaux add constraint types_travaux_categorie_fk foreign key (categorie) references public.categories_travaux(code);
insert into public.types_travaux (code, nom, description, categorie, unite, ordre) values
  ('INST-MURAL-1T-12', 'Murale 1 tête, jusqu''à 12 000 BTU', 'Condenseur et 1 tête, 25 pi de ligne, support, drain par gravité, vide d''air, mise en marche', 'murale', 'forfait', 100),
  ('INST-MURAL-1T-18', 'Murale 1 tête, 15 000 à 18 000 BTU', 'Comme 12 000 BTU', 'murale', 'forfait', 101),
  ('INST-MURAL-1T-24', 'Murale 1 tête, 24 000 BTU et plus', 'Comme 12 000 BTU, appareil plus lourd', 'murale', 'forfait', 102),
  ('INST-MULTI-2T', 'Multizone 2 têtes', 'Condenseur et 2 têtes, 25 pi de ligne par tête, supports, drains, mise en marche', 'murale', 'forfait', 103),
  ('INST-MULTI-3T', 'Multizone 3 têtes', 'Condenseur et 3 têtes, 25 pi de ligne par tête', 'murale', 'forfait', 104),
  ('INST-MULTI-4T', 'Multizone 4 têtes', 'Condenseur et 4 têtes, 25 pi de ligne par tête', 'murale', 'forfait', 105),
  ('INST-MULTI-5T', 'Multizone 5 têtes', 'Condenseur et 5 têtes, 25 pi de ligne par tête', 'murale', 'forfait', 106),
  ('INST-TETE-MULTI', 'Installation additionnelle par tête multizone', 'Tête ajoutée à un condenseur multizone, 25 pi de ligne', 'murale', 'tete', 107),
  ('INST-TETE-CASSETTE', 'Tête cassette au plafond', 'Supplément par rapport à une tête murale', 'tetes', 'tete', 208),
  ('INST-TETE-CONSOLE', 'Tête console au plancher', 'Supplément par rapport à une tête murale', 'tetes', 'tete', 209),
  ('INST-TETE-GAINABLE', 'Tête gainable (conduits courts dissimulés)', 'Supplément, conduits courts et grilles inclus', 'tetes', 'tete', 210),
  ('INST-CENTRAL-NEUF', 'Système central neuf avec réseau de conduits (maison sans conduits)', 'Fournaise ou unité de traitement d''air, thermopompe, plenums, réseau principal ; sorties en sus (CONDUIT-SORTIE)', 'central', 'forfait', 311),
  ('INST-CENTRAL-TP-UTA', 'Thermopompe centrale et unité de traitement d''air (conduits existants)', 'Raccord au réseau existant, serpentin, condenseur, mise en marche', 'central', 'forfait', 312),
  ('INST-ADDON', 'Add-on thermopompe centrale sur fournaise existante', 'Serpentin sur la fournaise, condenseur, 25 pi de ligne, mise en marche', 'central', 'forfait', 313),
  ('INST-CLIM-CENTRAL', 'Climatiseur central (sans chauffage)', 'Serpentin et condenseur, 25 pi de ligne', 'central', 'forfait', 314),
  ('INST-FOURNAISE-ELEC', 'Fournaise électrique neuve (conduits existants)', 'Raccord au réseau de conduits existant', 'central', 'forfait', 315),
  ('REMP-MURAL-1T', 'Remplacement d''une murale 1 tête', 'Retrait de l''ancienne, récupération du réfrigérant, nouvelle installation ; lignes réutilisées si conformes', 'remplacement', 'forfait', 416),
  ('REMP-MULTI-COND', 'Remplacement d''un condenseur multizone', 'Têtes existantes conservées', 'remplacement', 'forfait', 417),
  ('REMP-TETE', 'Remplacement d''une tête intérieure', null, 'remplacement', 'tete', 418),
  ('REMP-TP-CENTRALE-COND', 'Remplacement du condenseur d''une thermopompe centrale', 'Serpentin existant conservé', 'remplacement', 'forfait', 419),
  ('REMP-TP-CENTRALE', 'Remplacement complet d''une thermopompe centrale', 'Condenseur et serpentin', 'remplacement', 'forfait', 420),
  ('REMP-FOURNAISE-ELEC', 'Remplacement d''une fournaise électrique (électrique vers électrique)', null, 'remplacement', 'forfait', 421),
  ('REMP-FOURNAISE-ELEC-TP', 'Remplacement d''une fournaise électrique et ajout d''une thermopompe centrale', null, 'remplacement', 'forfait', 422),
  ('REMP-FOURNAISE-GAZ', 'Remplacement d''une fournaise au gaz (gaz vers gaz)', 'Raccord gaz et évent en sus si modifiés', 'remplacement', 'forfait', 423),
  ('REMP-UTA', 'Remplacement d''une unité de traitement d''air', null, 'remplacement', 'forfait', 424),
  ('BIEN-GAZ-REMP-ADDON', 'Remplacement d''une fournaise au gaz et add-on thermopompe (biénergie)', 'Nouvelle fournaise au gaz, serpentin, condenseur, contrôle biénergie', 'bienergie', 'forfait', 525),
  ('BIEN-GAZ-ADDON', 'Add-on thermopompe sur fournaise au gaz existante (biénergie)', 'Serpentin, condenseur, contrôle biénergie', 'bienergie', 'forfait', 526),
  ('BIEN-HUILE-ADDON', 'Add-on thermopompe sur fournaise à l''huile existante (biénergie)', 'Serpentin, condenseur, contrôle biénergie', 'bienergie', 'forfait', 527),
  ('BIEN-PROPANE-ADDON', 'Add-on thermopompe sur fournaise au propane (biénergie)', 'Serpentin, condenseur, contrôle biénergie', 'bienergie', 'forfait', 528),
  ('BIEN-CONTROLE', 'Contrôle biénergie seul', 'Sonde extérieure, relais et programmation', 'bienergie', 'unite', 529),
  ('CONV-HUILE-ELEC', 'Fournaise à l''huile remplacée par une fournaise électrique', 'Retrait du brûleur et de la fournaise ; réservoir en sus', 'huile', 'forfait', 630),
  ('CONV-HUILE-ELEC-TP', 'Fournaise à l''huile remplacée par une fournaise électrique et une thermopompe centrale', 'Réservoir en sus', 'huile', 'forfait', 631),
  ('RETRAIT-RESERVOIR-INT', 'Retrait et disposition d''un réservoir d''huile intérieur', 'Vidange, découpe, transport', 'huile', 'forfait', 632),
  ('RETRAIT-RESERVOIR-EXT', 'Retrait d''un réservoir d''huile extérieur hors sol', 'Réservoir enfoui : soumission spéciale', 'huile', 'forfait', 633),
  ('INST-ECHANGEUR-NEUF', 'Échangeur d''air (VRC ou VRE) neuf avec conduits', 'Appareil, conduits, sorties murales, équilibrage', 'ventilation', 'forfait', 734),
  ('REMP-ECHANGEUR', 'Remplacement d''un échangeur d''air (conduits existants)', 'Retrait de l''ancien, équilibrage', 'ventilation', 'forfait', 735),
  ('SERV-EQUILIBRAGE', 'Équilibrage d''un échangeur d''air', null, 'ventilation', 'forfait', 736),
  ('EXTRA-LIGNE-PI', 'Ligne frigorifique supplémentaire (au-delà de 25 pi)', null, 'extras', 'pied', 837),
  ('EXTRA-COUVRE-LIGNE-PI', 'Couvre-ligne (line hide)', null, 'extras', 'pied', 838),
  ('EXTRA-DRAIN-PI', 'Drain de condensat supplémentaire', null, 'extras', 'pied', 839),
  ('EXTRA-POMPE-COND', 'Pompe à condensat', null, 'extras', 'unite', 840),
  ('EXTRA-SUPPORT-MURAL', 'Support mural du condenseur', null, 'extras', 'unite', 841),
  ('EXTRA-SUPPORT-SOL', 'Base au sol ou pattes anti-neige', null, 'extras', 'unite', 842),
  ('EXTRA-SUPPORT-TOIT', 'Installation du condenseur sur un toit', null, 'extras', 'forfait', 843),
  ('EXTRA-PERCAGE-BETON', 'Percement béton ou fondation', null, 'extras', 'unite', 844),
  ('EXTRA-PERCAGE-BRIQUE', 'Percement brique ou pierre', null, 'extras', 'unite', 845),
  ('EXTRA-HAUTEUR', 'Travail en hauteur (2e étage et plus, échafaudage ou nacelle)', null, 'extras', 'forfait', 846),
  ('EXTRA-ACCES-DIFFICILE', 'Accès difficile (vide sanitaire, entretoit, plafond fini)', null, 'extras', 'forfait', 847),
  ('EXTRA-THERMOSTAT', 'Pose d''un thermostat programmable ou intelligent', null, 'extras', 'unite', 848),
  ('CONDUIT-SORTIE', 'Sortie d''alimentation (trappe) ajoutée', null, 'conduits', 'sortie', 949),
  ('CONDUIT-RETOUR', 'Retour d''air ajouté', null, 'conduits', 'sortie', 950),
  ('CONDUIT-PLENUM', 'Fabrication ou modification d''un plenum', null, 'conduits', 'forfait', 951),
  ('CONDUIT-PI', 'Conduit rigide supplémentaire', null, 'conduits', 'pied', 952),
  ('ELEC-CIRCUIT-240', 'Circuit 240 V dédié (jusqu''à 25 pi du panneau)', 'Travaux par un maître électricien', 'electricite', 'unite', 1053),
  ('ELEC-SECTIONNEUR', 'Sectionneur extérieur', null, 'electricite', 'unite', 1054),
  ('ELEC-CIRCUIT-PI', 'Câblage supplémentaire (au-delà de 25 pi)', null, 'electricite', 'pied', 1055),
  ('ELEC-PANNEAU', 'Mise à niveau du panneau électrique', 'Soumission spéciale au besoin', 'electricite', 'forfait', 1056),
  ('GAZ-RACCORD', 'Raccordement gaz naturel ou propane', null, 'gaz', 'forfait', 1157),
  ('GAZ-EVENT-PVC', 'Évent et prise d''air PVC (fournaise haute efficacité)', null, 'gaz', 'forfait', 1158),
  ('GAZ-CHEMISAGE', 'Chemisage de cheminée', null, 'gaz', 'forfait', 1159),
  ('RETRAIT-MURAL', 'Retrait d''une thermopompe murale et récupération du réfrigérant', null, 'retrait', 'unite', 1260),
  ('RETRAIT-CENTRAL', 'Retrait d''un condenseur central et récupération du réfrigérant', null, 'retrait', 'unite', 1261),
  ('RETRAIT-FOURNAISE', 'Retrait et disposition d''une fournaise', null, 'retrait', 'unite', 1262),
  ('SERV-DEPLACEMENT', 'Appel de service (déplacement et première heure)', null, 'service', 'forfait', 1363),
  ('SERV-HEURE', 'Heure additionnelle', null, 'service', 'heure', 1364),
  ('SERV-ENTRETIEN-MURAL', 'Entretien annuel d''une murale', null, 'service', 'tete', 1365),
  ('SERV-ENTRETIEN-CENTRAL', 'Entretien annuel d''un système central', null, 'service', 'forfait', 1366),
  ('SERV-REFRIGERANT', 'Ajout de réfrigérant', 'Technicien certifié (halocarbures)', 'service', 'livre', 1367)
on conflict (code) do update set nom = excluded.nom, description = excluded.description,
  categorie = excluded.categorie, unite = excluded.unite, ordre = excluded.ordre, updated_at = now();

-- ===== 20261024000800_demandes_prix.sql =====
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
  insert into public.notifications (destinataire_employe_id, type, titre, message, lien)
  select e.id, 'prix_recus', 'Liste de prix reçue', (select nom from public.fournisseurs where id = d.fournisseur_id) || ' a envoyé ses prix.',
         '/demande-prix?id=' || d.id
    from public.employes e where e.actif and e.role = 'Admin tout';
  perform set_config('app.demande_prix_fonction', '', true);
  return jsonb_build_object('ok', true, 'signe_le', now(), 'valide_jusqu', (v_jour + interval '1 year')::date);
end $$;
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

-- ===== 20261024000900_prix_portail.sql =====
create table public.travaux_sous_traitants (
  fournisseur_id  uuid not null references public.fournisseurs(id),
  type_travail_id uuid not null references public.types_travaux(id),
  created_at      timestamptz not null default now(),
  primary key (fournisseur_id, type_travail_id)
);
alter table public.travaux_sous_traitants enable row level security;
create policy lecture on public.travaux_sous_traitants for select to authenticated
  using (app.est_commercial() or app.voit_tout() or fournisseur_id = app.mon_fournisseur());
create policy ajout on public.travaux_sous_traitants for insert to authenticated with check (app.est_admin() or app.est_planification());
create policy retrait on public.travaux_sous_traitants for delete to authenticated using (app.est_admin() or app.est_planification());
create trigger trg_audit after insert or delete on public.travaux_sous_traitants for each row execute function app.audit();
insert into public.travaux_sous_traitants (fournisseur_id, type_travail_id)
select distinct fournisseur_id, type_travail_id from public.tarifs_sous_traitants on conflict do nothing;
create or replace function app.tarif_immuable() returns trigger
language plpgsql as $$
begin
  if tg_op = 'UPDATE' and coalesce(current_setting('app.tarif_meme_jour', true), '') = 'oui'
     and old.en_vigueur_du = new.en_vigueur_du and old.fournisseur_id = new.fournisseur_id and old.type_travail_id = new.type_travail_id then
    return new;
  end if;
  raise exception '% interdit sur tarifs_sous_traitants (un prix ne se modifie pas : on en ajoute un nouveau, daté)', tg_op using errcode = '42501';
end $$;
drop trigger trg_tarif_immuable on public.tarifs_sous_traitants;
create trigger trg_tarif_immuable before update or delete on public.tarifs_sous_traitants
  for each row execute function app.tarif_immuable();
create trigger trg_audit_maj after update on public.tarifs_sous_traitants for each row execute function app.audit();
create or replace function app.engagements(p_fournisseur uuid, p_types uuid[] default null)
returns table (devis_id uuid, numero text, code_projet text, statut text, ville text, vendeur_id uuid, vendeur_nom text,
               type_travail_id uuid, code text, travail text, quantite numeric, cout_cents bigint, honorer_jusqu date)
language sql stable security definer set search_path = public as $$
  select d.id, d.numero::text, d.code_projet, case when d.statut = 'accepte' then 'accepte' else 'envoye' end,
         s.ville, d.vendeur_id, e.prenom || ' ' || e.nom, l.type_travail_id, t.code, t.nom, l.quantite, l.cout_cents,
         case when d.statut = 'accepte' then null else d.valide_jusqu end
    from public.devis_lignes l
    join public.devis d on d.id = l.devis_id
    join public.types_travaux t on t.id = l.type_travail_id
    left join public.sites s on s.id = d.site_id
    left join public.employes e on e.id = d.vendeur_id
   where l.type_ligne = 'installation' and l.source_cout = 'grille' and l.sous_traitant_id = p_fournisseur
     and (p_types is null or l.type_travail_id = any(p_types))
     and ((d.statut = 'envoye' and d.valide_jusqu >= current_date)
          or (d.statut = 'accepte' and not exists (select 1 from public.projets p where p.devis_id = d.id and p.statut in ('termine','facture','ferme','annule'))))
   order by coalesce(d.valide_jusqu, current_date + 3650), d.numero
$$;
create or replace function public.hvac_mes_engagements(p_fournisseur uuid default null, p_types uuid[] default null)
returns table (devis_id uuid, numero text, statut text, ville text, vendeur_nom text, type_travail_id uuid, code text,
               travail text, quantite numeric, cout_cents bigint, honorer_jusqu date)
language plpgsql stable security definer set search_path = public as $$
declare v_f uuid := coalesce(app.mon_fournisseur(), case when app.est_admin() or app.est_planification() then p_fournisseur end);
begin
  if v_f is null then raise exception 'Sous-traitant requis' using errcode = '42501'; end if;
  return query select e.devis_id, e.numero, e.statut, e.ville, e.vendeur_nom, e.type_travail_id, e.code, e.travail,
                      e.quantite, e.cout_cents, e.honorer_jusqu
                 from app.engagements(v_f, p_types) e;
end $$;
revoke all on function public.hvac_mes_engagements(uuid, uuid[]) from public, anon;
grant execute on function public.hvac_mes_engagements(uuid, uuid[]) to authenticated;
create or replace function public.hvac_maj_mes_prix(p_prix jsonb, p_fournisseur uuid default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_f uuid := coalesce(app.mon_fournisseur(), case when app.est_admin() or app.est_planification() then p_fournisseur end);
  v_jour date := (now() at time zone 'America/Toronto')::date;
  x jsonb; v_type uuid; v_cout bigint; v_ancien bigint; n integer := 0; v_types uuid[] := '{}';
begin
  if v_f is null then raise exception 'Sous-traitant requis' using errcode = '42501'; end if;
  perform set_config('app.tarif_meme_jour', 'oui', true);
  for x in select * from jsonb_array_elements(coalesce(p_prix, '[]')) loop
    v_type := (x->>'type_travail_id')::uuid;
    v_cout := (x->>'cout_cents')::bigint;
    if v_cout is null or v_cout <= 0 then raise exception 'Prix invalide' using errcode = 'P0001'; end if;
    if not exists (select 1 from public.travaux_sous_traitants where fournisseur_id = v_f and type_travail_id = v_type) then
      raise exception 'Ce travail n''est pas confié à ce sous-traitant' using errcode = '42501';
    end if;
    v_ancien := public.hvac_cout_installation(v_f, v_type, v_jour);
    if v_ancien is not distinct from v_cout then continue; end if;
    insert into public.tarifs_sous_traitants (fournisseur_id, type_travail_id, cout_cents, en_vigueur_du, notes)
    values (v_f, v_type, v_cout, v_jour, case when app.mon_fournisseur() is not null then 'Modifié par le sous-traitant' else 'Modifié par Belleflamme' end)
    on conflict (fournisseur_id, type_travail_id, en_vigueur_du) do update set cout_cents = excluded.cout_cents, notes = excluded.notes;
    n := n + 1; v_types := v_types || v_type;
    insert into public.notifications (destinataire_employe_id, type, titre, message, lien)
    select distinct e.vendeur_id, 'prix_sous_traitant',
           'Nouveau prix d''installation',
           format('%s : %s passe de %s $ à %s $. Ton devis #%s garde l''ancien prix%s ; au renouvellement, le nouveau prix s''appliquera.',
                  (select nom from public.fournisseurs where id = v_f), e.travail,
                  to_char(e.cout_cents / 100.0, 'FM999G990D00'), to_char(v_cout / 100.0, 'FM999G990D00'), e.numero,
                  case when e.honorer_jusqu is not null then ' jusqu''au ' || to_char(e.honorer_jusqu, 'YYYY-MM-DD') else '' end),
           '/devis?id=' || e.devis_id
      from app.engagements(v_f, array[v_type]) e where e.vendeur_id is not null;
  end loop;
  perform set_config('app.tarif_meme_jour', '', true);
  if n > 0 then
    insert into public.notifications (destinataire_employe_id, type, titre, message, lien)
    select emp.id, 'prix_sous_traitant', 'Liste de prix modifiée',
           (select nom from public.fournisseurs where id = v_f) || ' a modifié ' || n || ' prix.', '/mes-prix?fournisseur=' || v_f
      from public.employes emp where emp.actif and emp.role = 'Admin tout';
  end if;
  return jsonb_build_object('changes', n, 'engagements', (select coalesce(jsonb_agg(to_jsonb(e)), '[]') from app.engagements(v_f, v_types) e));
end $$;
revoke all on function public.hvac_maj_mes_prix(jsonb, uuid) from public, anon;
grant execute on function public.hvac_maj_mes_prix(jsonb, uuid) to authenticated;
create or replace function app.renouvellement_ecarts() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_origine uuid; v_vendeur uuid; v_numero text; o record;
begin
  if new.type_ligne <> 'installation' or new.source_cout <> 'grille' then return null; end if;
  select devis_origine_id, vendeur_id, numero::text into v_origine, v_vendeur, v_numero from public.devis where id = new.devis_id;
  if v_origine is null then return null; end if;
  select l.cout_cents, l.prix_unitaire_cents into o from public.devis_lignes l
   where l.devis_id = v_origine and l.type_ligne = 'installation'
     and l.type_travail_id = new.type_travail_id and l.sous_traitant_id = new.sous_traitant_id
   limit 1;
  if o.cout_cents is not null and o.cout_cents <> new.cout_cents then
    insert into public.notifications (destinataire_employe_id, type, titre, message, lien)
    values (v_vendeur, 'prix_renouvellement', 'Nouvelle liste de prix au renouvellement',
            format('Devis #%s : %s, prix client %s $ au lieu de %s $ (nouvelle liste de prix du sous-traitant). Vérifie avant de renvoyer au client.',
                   v_numero, new.description, to_char(new.prix_unitaire_cents / 100.0, 'FM999G990D00'), to_char(o.prix_unitaire_cents / 100.0, 'FM999G990D00')),
            '/devis?id=' || new.devis_id);
  end if;
  return null;
end $$;
create trigger trg_renouvellement_ecarts after insert on public.devis_lignes
  for each row execute function app.renouvellement_ecarts();
create or replace view public.devis_ecarts_prix_v with (security_invoker = true) as
select n.devis_id, n.id as ligne_id, n.description, n.type_travail_id, n.sous_traitant_id,
       o.cout_cents as ancien_cout_cents, n.cout_cents as nouveau_cout_cents,
       o.prix_unitaire_cents as ancien_prix_cents, n.prix_unitaire_cents as nouveau_prix_cents
  from public.devis_lignes n
  join public.devis d on d.id = n.devis_id and d.devis_origine_id is not null
  join public.devis_lignes o on o.devis_id = d.devis_origine_id and o.type_travail_id = n.type_travail_id
                            and o.sous_traitant_id = n.sous_traitant_id and o.type_ligne = 'installation'
 where n.type_ligne = 'installation' and n.cout_cents <> o.cout_cents;
grant select on public.devis_ecarts_prix_v to authenticated;
revoke all on public.devis_ecarts_prix_v from anon;

-- ===== 20261024001000_fiche_sous_traitant.sql =====
alter table public.fournisseurs
  add column responsable_nom       text check (length(responsable_nom) <= 120),
  add column responsable_telephone text check (length(responsable_telephone) <= 40),
  add column responsable_courriel  text check (responsable_courriel ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
  add column proprietaire_nom      text check (length(proprietaire_nom) <= 120);
alter table public.fournisseurs
  add constraint fournisseurs_licence_rbq_format check (licence_rbq is null or licence_rbq ~ '^\d{4}-\d{4}-\d{2}$') not valid;
create trigger trg_audit after insert or update on public.fournisseurs for each row execute function app.audit();

-- ===== 20261024001100_registre_listes_prix.sql =====
create table public.listes_prix_versions (
  id                 uuid primary key default gen_random_uuid(),
  fournisseur_id     uuid not null references public.fournisseurs(id),
  numero             integer not null check (numero > 0),
  cree_le            timestamptz not null default now(),
  auteur_employe_id  uuid references public.employes(id),
  auteur_nom         text not null,
  par_sous_traitant  boolean not null default false,
  motif              text not null,
  lignes             jsonb not null,      -- [{ code, nom, categorie, unite, cout_cents, en_vigueur_du }]
  changements        jsonb not null,      -- [{ type: ajout | retrait | prix, code, nom, avant, apres }]
  nb_lignes          integer not null,
  nb_changements     integer not null,
  empreinte          text not null,       -- SHA-256 des lignes : prouve que le PDF n'a pas été retouché
  unique (fournisseur_id, numero)
);
create index listes_prix_versions_recent on public.listes_prix_versions (fournisseur_id, cree_le desc);
alter table public.listes_prix_versions enable row level security;
create policy lecture on public.listes_prix_versions for select to authenticated
  using (app.est_admin() or app.est_planification() or app.voit_tout() or fournisseur_id = app.mon_fournisseur());
revoke all on public.listes_prix_versions from anon;
grant select on public.listes_prix_versions to authenticated;
create or replace function app.version_immuable() returns trigger language plpgsql as $$
begin
  raise exception '% interdit sur listes_prix_versions (une version archivée ne se modifie pas)', tg_op using errcode = '42501';
end $$;
create trigger trg_version_immuable before update or delete on public.listes_prix_versions
  for each row execute function app.version_immuable();
insert into public.parametres (cle, valeur, description)
values ('seuil_versions_liste_30j', '3', 'Alerte quand un sous-traitant modifie sa liste de prix ce nombre de fois ou plus en 30 jours (ADR-065)')
on conflict (cle) do nothing;
create or replace function app.versionner_liste(p_fournisseur uuid, p_motif text) returns integer
language plpgsql security definer set search_path = public as $$
declare
  v_jour date := (now() at time zone 'America/Toronto')::date;
  v_lignes jsonb; v_prec jsonb; v_chg jsonb; v_num integer; v_emp uuid := app.employe_id();
  v_auteur text; v_st boolean := app.mon_fournisseur() is not null; v_seuil integer; v_n30 integer;
begin
  perform pg_advisory_xact_lock(hashtext('liste_prix:' || p_fournisseur));
  select coalesce(jsonb_agg(jsonb_build_object(
           'code', t.code, 'nom', t.nom, 'categorie', coalesce(c.nom, t.categorie), 'unite', t.unite,
           'cout_cents', public.hvac_cout_installation(p_fournisseur, t.id, v_jour),
           'en_vigueur_du', (select max(x.en_vigueur_du) from public.tarifs_sous_traitants x
                              where x.fournisseur_id = p_fournisseur and x.type_travail_id = t.id and x.en_vigueur_du <= v_jour))
         order by c.ordre nulls last, t.ordre, t.code), '[]')
    into v_lignes
    from public.travaux_sous_traitants ts
    join public.types_travaux t on t.id = ts.type_travail_id
    left join public.categories_travaux c on c.code = t.categorie
   where ts.fournisseur_id = p_fournisseur;
  select lignes, numero into v_prec, v_num from public.listes_prix_versions
   where fournisseur_id = p_fournisseur order by numero desc limit 1;
  if v_prec is null then
    if jsonb_array_length(v_lignes) = 0 then return null; end if;
    v_chg := '[]';
  else
    select coalesce(jsonb_agg(x order by x->>'code'), '[]') into v_chg from (
      select jsonb_build_object('type', 'ajout', 'code', n->>'code', 'nom', n->>'nom', 'avant', null, 'apres', n->'cout_cents') as x
        from jsonb_array_elements(v_lignes) n
       where not exists (select 1 from jsonb_array_elements(v_prec) o where o->>'code' = n->>'code')
      union all
      select jsonb_build_object('type', 'retrait', 'code', o->>'code', 'nom', o->>'nom', 'avant', o->'cout_cents', 'apres', null)
        from jsonb_array_elements(v_prec) o
       where not exists (select 1 from jsonb_array_elements(v_lignes) n where n->>'code' = o->>'code')
      union all
      select jsonb_build_object('type', 'prix', 'code', n->>'code', 'nom', n->>'nom', 'avant', o->'cout_cents', 'apres', n->'cout_cents')
        from jsonb_array_elements(v_lignes) n join jsonb_array_elements(v_prec) o on o->>'code' = n->>'code'
       where (o->'cout_cents') is distinct from (n->'cout_cents')
    ) s;
    if jsonb_array_length(v_chg) = 0 then return null; end if;
  end if;
  select coalesce(nullif(trim(e.prenom || ' ' || e.nom), ''), e.email) into v_auteur from public.employes e where e.id = v_emp;
  v_num := coalesce(v_num, 0) + 1;
  insert into public.listes_prix_versions (fournisseur_id, numero, auteur_employe_id, auteur_nom, par_sous_traitant, motif,
                                           lignes, changements, nb_lignes, nb_changements, empreinte)
  values (p_fournisseur, v_num, v_emp, coalesce(v_auteur, 'Système'), v_st, p_motif,
          v_lignes, v_chg, jsonb_array_length(v_lignes), jsonb_array_length(v_chg),
          encode(sha256(convert_to(v_lignes::text, 'UTF8')), 'hex'));
  if v_st then
    v_seuil := coalesce((select (valeur #>> '{}')::integer from public.parametres where cle = 'seuil_versions_liste_30j'), 3);
    select count(*) into v_n30 from public.listes_prix_versions
     where fournisseur_id = p_fournisseur and par_sous_traitant and cree_le > now() - interval '30 days';
    if v_n30 >= v_seuil then
      insert into public.notifications (destinataire_employe_id, type, titre, message, lien)
      select emp.id, 'liste_prix_frequente', 'Liste de prix modifiée souvent',
             format('%s a modifié sa liste de prix %s fois en 30 jours (version %s).',
                    (select nom from public.fournisseurs where id = p_fournisseur), v_n30, v_num),
             '/installation-grille?fournisseur=' || p_fournisseur
        from public.employes emp where emp.actif and emp.role = 'Admin tout';
    end if;
  end if;
  return v_num;
end $$;
revoke all on function app.versionner_liste(uuid, text) from public;
create or replace function public.hvac_maj_mes_prix(p_prix jsonb, p_fournisseur uuid default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_f uuid := coalesce(app.mon_fournisseur(), case when app.est_admin() or app.est_planification() then p_fournisseur end);
  v_st boolean := app.mon_fournisseur() is not null;
  v_jour date := (now() at time zone 'America/Toronto')::date;
  x jsonb; v_type uuid; v_cout bigint; v_ancien bigint; n integer := 0; v_types uuid[] := '{}'; v_version integer;
begin
  if v_f is null then raise exception 'Sous-traitant requis' using errcode = '42501'; end if;
  perform set_config('app.tarif_meme_jour', 'oui', true);
  for x in select * from jsonb_array_elements(coalesce(p_prix, '[]')) loop
    v_type := (x->>'type_travail_id')::uuid;
    v_cout := (x->>'cout_cents')::bigint;
    if v_cout is null or v_cout <= 0 then raise exception 'Prix invalide' using errcode = 'P0001'; end if;
    if not exists (select 1 from public.types_travaux where id = v_type) then raise exception 'Travail inconnu' using errcode = 'P0001'; end if;
    if not exists (select 1 from public.travaux_sous_traitants where fournisseur_id = v_f and type_travail_id = v_type) then
      if v_st then raise exception 'Ce travail n''est pas confié à ce sous-traitant' using errcode = '42501'; end if;
      insert into public.travaux_sous_traitants (fournisseur_id, type_travail_id) values (v_f, v_type);
    end if;
    v_ancien := public.hvac_cout_installation(v_f, v_type, v_jour);
    if v_ancien is not distinct from v_cout then continue; end if;
    insert into public.tarifs_sous_traitants (fournisseur_id, type_travail_id, cout_cents, en_vigueur_du, notes)
    values (v_f, v_type, v_cout, v_jour, case when v_st then 'Modifié par le sous-traitant' else 'Modifié par Belleflamme' end)
    on conflict (fournisseur_id, type_travail_id, en_vigueur_du) do update set cout_cents = excluded.cout_cents, notes = excluded.notes;
    n := n + 1; v_types := v_types || v_type;
    insert into public.notifications (destinataire_employe_id, type, titre, message, lien)
    select distinct e.vendeur_id, 'prix_sous_traitant',
           'Nouveau prix d''installation',
           format('%s : %s passe de %s $ à %s $. Ton devis #%s garde l''ancien prix%s ; au renouvellement, le nouveau prix s''appliquera.',
                  (select nom from public.fournisseurs where id = v_f), e.travail,
                  to_char(e.cout_cents / 100.0, 'FM999G990D00'), to_char(v_cout / 100.0, 'FM999G990D00'), e.numero,
                  case when e.honorer_jusqu is not null then ' jusqu''au ' || to_char(e.honorer_jusqu, 'YYYY-MM-DD') else '' end),
           '/devis?id=' || e.devis_id
      from app.engagements(v_f, array[v_type]) e where e.vendeur_id is not null;
  end loop;
  perform set_config('app.tarif_meme_jour', '', true);
  if n > 0 then
    insert into public.notifications (destinataire_employe_id, type, titre, message, lien)
    select emp.id, 'prix_sous_traitant', 'Liste de prix modifiée',
           (select nom from public.fournisseurs where id = v_f) || ' a modifié ' || n || ' prix.', '/mes-prix?fournisseur=' || v_f
      from public.employes emp where emp.actif and emp.role = 'Admin tout';
  end if;
  v_version := app.versionner_liste(v_f, case when v_st then 'Prix modifiés par le sous-traitant' else 'Prix modifiés par Belleflamme' end);
  return jsonb_build_object('changes', n, 'version', v_version,
                            'engagements', (select coalesce(jsonb_agg(to_jsonb(e)), '[]') from app.engagements(v_f, v_types) e));
end $$;
create or replace function public.hvac_confier_travaux(p_fournisseur uuid, p_ajouter uuid[] default '{}', p_retirer uuid[] default '{}')
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_a integer; v_r integer;
begin
  if not (app.est_admin() or app.est_planification()) then raise exception 'Réservé à la planification' using errcode = '42501'; end if;
  insert into public.travaux_sous_traitants (fournisseur_id, type_travail_id)
  select p_fournisseur, unnest(coalesce(p_ajouter, '{}')) on conflict do nothing;
  get diagnostics v_a = row_count;
  delete from public.travaux_sous_traitants where fournisseur_id = p_fournisseur and type_travail_id = any(coalesce(p_retirer, '{}'));
  get diagnostics v_r = row_count;
  return jsonb_build_object('ajoutes', v_a, 'retires', v_r,
                            'version', app.versionner_liste(p_fournisseur, 'Travaux confiés modifiés par Belleflamme'));
end $$;
revoke all on function public.hvac_confier_travaux(uuid, uuid[], uuid[]) from public, anon;
grant execute on function public.hvac_confier_travaux(uuid, uuid[], uuid[]) to authenticated;
create or replace function public.hvac_versionner_liste(p_fournisseur uuid, p_motif text default 'Liste modifiée')
returns integer language plpgsql security definer set search_path = public as $$
begin
  if not (app.est_admin() or app.est_planification() or app.mon_fournisseur() = p_fournisseur) then
    raise exception 'Accès refusé' using errcode = '42501';
  end if;
  return app.versionner_liste(p_fournisseur, left(coalesce(p_motif, 'Liste modifiée'), 120));
end $$;
revoke all on function public.hvac_versionner_liste(uuid, text) from public, anon;
grant execute on function public.hvac_versionner_liste(uuid, text) to authenticated;
do $$
declare f uuid;
begin
  for f in select distinct fournisseur_id from public.travaux_sous_traitants loop
    perform app.versionner_liste(f, 'Première version (reprise de la liste existante)');
  end loop;
end $$;

-- ===== 20261024001200_communications.sql =====
create or replace function app.est_interne() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.employes e where e.id = app.employe_id() and e.actif and e.fournisseur_id is null)
$$;
create table public.communications (
  id                     uuid primary key default gen_random_uuid(),
  client_id              uuid references public.clients(id),
  lead_id                uuid references public.leads(id),
  canal                  text not null check (canal in ('appel','texto','courriel')),
  direction              text not null check (direction in ('sortant','entrant')),
  statut                 text not null default 'termine'
                         check (statut in ('termine','manque','messagerie','envoye','recu','echec')),
  employe_id             uuid references public.employes(id),
  coordonnee_client      text,                -- numéro ou courriel du client utilisé
  debut                  timestamptz not null,
  duree_s                integer check (duree_s >= 0),
  sujet                  text,                -- courriel
  contenu                text,                -- texto ou corps du courriel
  enregistrement_ref     text,                -- référence de l'enregistrement chez Mike (jamais une URL publique)
  enregistrement_duree_s integer check (enregistrement_duree_s >= 0),
  enregistrement_efface_le timestamptz,       -- effacé selon la règle de conservation
  transcription          text,
  resume                 text,
  externe_id             text unique,         -- identifiant chez Mike (ex. identifiant d'appel de la téléphonie)
  created_at             timestamptz not null default now(),
  updated_at             timestamptz not null default now(),
  check (client_id is not null or lead_id is not null)
);
call app.preparer_table('public.communications');
create index communications_client on public.communications (client_id, debut desc);
create index communications_lead on public.communications (lead_id, debut desc);
alter table public.communications enable row level security;
create policy lecture on public.communications for select to authenticated using (app.est_interne());
revoke all on public.communications from anon;
grant select on public.communications to authenticated;
create trigger trg_audit after insert or update on public.communications for each row execute function app.audit();
create or replace view public.communications_v as
select c.id, coalesce(c.client_id, l.client_id) as client_id, c.lead_id, c.canal, c.direction, c.statut,
       c.employe_id, trim(e.prenom || ' ' || e.nom) as employe_nom, c.coordonnee_client, c.debut, c.duree_s,
       c.sujet, c.contenu, (c.enregistrement_ref is not null and c.enregistrement_efface_le is null) as a_enregistrement,
       c.enregistrement_duree_s, c.enregistrement_efface_le, c.transcription, c.resume, c.source
  from public.communications c
  left join public.leads l on l.id = c.lead_id
  left join public.employes e on e.id = c.employe_id
 where app.est_interne();
grant select on public.communications_v to authenticated;
revoke all on public.communications_v from anon;
create or replace function public.hvac_ecouter_enregistrement(p_communication uuid)
returns text language plpgsql security definer set search_path = public as $$
declare v_ref text; v_client uuid; v_lead uuid;
begin
  if not app.est_interne() then raise exception 'Accès refusé' using errcode = '42501'; end if;
  select enregistrement_ref, client_id, lead_id into v_ref, v_client, v_lead from public.communications
   where id = p_communication and canal = 'appel' and enregistrement_efface_le is null;
  if v_ref is null then raise exception 'Enregistrement introuvable ou effacé' using errcode = 'P0002'; end if;
  insert into public.journal_audit (auth_uid, employe_id, action, table_nom, ligne_id, contexte)
  values (auth.uid(), app.employe_id(), 'lecture', 'communications', p_communication::text,
          jsonb_build_object('objet', 'enregistrement', 'client_id', v_client, 'lead_id', v_lead));
  return v_ref;
end $$;
revoke all on function public.hvac_ecouter_enregistrement(uuid) from public, anon;
grant execute on function public.hvac_ecouter_enregistrement(uuid) to authenticated;
insert into public.parametres (cle, valeur, description)
values ('conservation_enregistrements_jours', 'null',
        'Durée de conservation des enregistrements d''appels, en jours. Même règle que l''app de Mike : à confirmer avec lui (ADR-067). Vide = rien n''est effacé.')
on conflict (cle) do nothing;
create or replace function app.purger_enregistrements() returns integer
language plpgsql security definer set search_path = public as $$
declare v_jours integer; n integer;
begin
  select nullif(valeur #>> '{}', 'null')::integer into v_jours from public.parametres where cle = 'conservation_enregistrements_jours';
  if v_jours is null then return 0; end if;
  update public.communications set enregistrement_ref = null, enregistrement_efface_le = now()
   where enregistrement_ref is not null and debut < now() - make_interval(days => v_jours);
  get diagnostics n = row_count;
  return n;
end $$;
revoke all on function app.purger_enregistrements() from public;
alter table public.sites add column latitude numeric(9,6) check (latitude between -90 and 90),
                         add column longitude numeric(9,6) check (longitude between -180 and 180);

-- ===== 20261024001300_macro.sql =====
alter table public.lead_activites drop constraint lead_activites_type_check;
alter table public.lead_activites add constraint lead_activites_type_check check (type in ('attribution','prise_en_charge','appel',
  'courriel','texto','note','visite_planifiee','perdu','reouvert','vendu'));
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
      when new.type = 'vendu' then 'converti'
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
alter table public.projets
  add column lead_id uuid references public.leads(id),
  add column devis_numero_mike text unique,           -- numéro du devis signé dans l'app de Mike (#120815)
  add column montant_avant_taxes_cents bigint check (montant_avant_taxes_cents >= 0),
  add column type_systeme text check (type_systeme in ('mural_simple','mural_multi','central','bienergie')),
  add column signe_le timestamptz;
create index projets_lead on public.projets (lead_id);
create or replace function app.projet_transition() returns trigger
language plpgsql as $$
declare
  ordre text[] := array['attente_paiement','a_planifier','planifie','en_cours','termine','facture','ferme'];
  a int := array_position(ordre, old.statut); n int := array_position(ordre, new.statut);
begin
  if new.statut = old.statut then return new; end if;
  if new.statut = 'annule' then
    if old.statut in ('facture','ferme') then raise exception 'Un projet facturé ne s''annule pas' using errcode = 'P0001'; end if;
    return new;
  end if;
  if old.statut = 'annule' then raise exception 'Un projet annulé ne revient pas' using errcode = 'P0001'; end if;
  if n < a - 1 then raise exception 'Un projet recule d''une étape à la fois' using errcode = 'P0001'; end if;
  return new;
end $$;
create trigger trg_projet_transition before update of statut on public.projets
  for each row execute function app.projet_transition();
create trigger trg_audit_projets after insert or update on public.projets for each row execute function app.audit();
create or replace function public.hvac_projet_signe(p jsonb) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  l public.leads%rowtype; v_client uuid := nullif(p->>'client_id', '')::uuid; v_projet uuid; v_succ text;
  v_numero text := nullif(trim(p->>'devis_numero_mike'), '');
begin
  if not (app.est_admin() or app.est_planification()) then raise exception 'Réservé à Belleflamme' using errcode = '42501'; end if;
  if v_numero is null then raise exception 'Numéro du devis signé requis' using errcode = 'P0001'; end if;
  select id into v_projet from public.projets where devis_numero_mike = v_numero;
  if v_projet is not null then return v_projet; end if;   -- déjà reçu : rien en double
  if p->>'lead_id' is not null then select * into l from public.leads where id = (p->>'lead_id')::uuid; end if;
  v_succ := coalesce(p->>'succursale_code', l.succursale_code);
  if v_succ is null then raise exception 'Succursale requise' using errcode = 'P0001'; end if;
  v_client := coalesce(v_client, l.client_id);
  if v_client is null then
    if l.id is null then raise exception 'Client ou lead requis' using errcode = 'P0001'; end if;
    insert into public.clients (nom, telephone, courriel, succursale_code, vendeur_id)
    values (coalesce(nullif(trim(l.contact_nom), ''), 'Client sans nom'), l.contact_tel, l.contact_courriel, v_succ, l.assigne_a)
    returning id into v_client;
    update public.leads set client_id = v_client where id = l.id;
  end if;
  insert into public.projets (division, succursale_code, client_id, vendeur_id, statut, lead_id, devis_numero_mike,
                              montant_avant_taxes_cents, type_systeme, signe_le)
  values ('Ventilation', v_succ, v_client, coalesce(nullif(p->>'vendeur_id', '')::uuid, l.assigne_a), 'attente_paiement', l.id, v_numero,
          nullif(p->>'montant_avant_taxes_cents', '')::bigint, coalesce(p->>'type_systeme', l.type_demande),
          coalesce(nullif(p->>'signe_le', '')::timestamptz, now()))
  returning id into v_projet;
  if l.id is not null and l.statut <> 'converti' then
    insert into public.lead_activites (lead_id, type, note) values (l.id, 'vendu', 'Soumission #' || v_numero || ' signée par le client');
  end if;
  return v_projet;
end $$;
revoke all on function public.hvac_projet_signe(jsonb) from public, anon;
grant execute on function public.hvac_projet_signe(jsonb) to authenticated;
create or replace view public.projets_macro_v with (security_invoker = true) as
select p.id, p.code_projet, p.statut, p.succursale_code, p.client_id, trim(coalesce(c.prenom || ' ', '') || c.nom) as client_nom,
       coalesce(s.ville, l.ville) as ville, p.vendeur_id, trim(e.prenom || ' ' || e.nom) as vendeur_nom, p.lead_id, p.devis_numero_mike,
       p.montant_avant_taxes_cents, p.type_systeme, p.signe_le, p.installation_prevue_le, p.created_at, p.updated_at
  from public.projets p
  join public.clients c on c.id = p.client_id
  left join public.sites s on s.id = p.site_id
  left join public.leads l on l.id = p.lead_id
  left join public.employes e on e.id = p.vendeur_id
 where p.division = 'Ventilation';
grant select on public.projets_macro_v to authenticated;
revoke all on public.projets_macro_v from anon;

-- ===== 20261024001400_jobs_sous_traitant.sql =====
alter table public.projets add column sous_traitant_id uuid references public.fournisseurs(id);
create index projets_sous_traitant on public.projets (sous_traitant_id) where sous_traitant_id is not null;
create table public.projet_lignes (
  id              uuid primary key default gen_random_uuid(),
  projet_id       uuid not null references public.projets(id),
  division        text not null default 'Ventilation' references public.divisions(nom),
  position        integer not null default 0,
  type_ligne      text not null check (type_ligne in ('machine','installation')),
  description     text not null check (length(trim(description)) > 0),
  quantite        numeric(10,2) not null default 1 check (quantite > 0),
  type_travail_id uuid references public.types_travaux(id),
  cout_cents      bigint check (cout_cents is null or cout_cents > 0),
  check ((type_ligne = 'installation') = (type_travail_id is not null and cout_cents is not null)),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
call app.preparer_table('public.projet_lignes');
create index projet_lignes_projet on public.projet_lignes (projet_id, position);
alter table public.projet_lignes enable row level security;
create policy lecture on public.projet_lignes for select to authenticated using (app.est_interne() and app.voit_projet(projet_id));
create trigger trg_audit_projet_lignes after insert or update on public.projet_lignes for each row execute function app.audit();
create or replace function public.hvac_projet_signe(p jsonb) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  l public.leads%rowtype; v_client uuid := nullif(p->>'client_id', '')::uuid; v_projet uuid; v_succ text;
  v_numero text := nullif(trim(p->>'devis_numero_mike'), '');
  v_st uuid := nullif(p->>'sous_traitant_id', '')::uuid; v_signe timestamptz := coalesce(nullif(p->>'signe_le', '')::timestamptz, now());
  x jsonb; v_pos integer := 0; v_type uuid; v_cout bigint; v_nom text;
begin
  if not (app.est_admin() or app.est_planification()) then raise exception 'Réservé à Belleflamme' using errcode = '42501'; end if;
  if v_numero is null then raise exception 'Numéro du devis signé requis' using errcode = 'P0001'; end if;
  select id into v_projet from public.projets where devis_numero_mike = v_numero;
  if v_projet is not null then return v_projet; end if;   -- déjà reçu : rien en double
  if v_st is not null and not exists (select 1 from public.fournisseurs where id = v_st and actif and type in ('sous-traitant','les deux')) then
    raise exception 'Sous-traitant inconnu ou inactif' using errcode = 'P0001';
  end if;
  if jsonb_typeof(coalesce(p->'lignes', '[]')) <> 'array' then raise exception 'Lignes invalides' using errcode = 'P0001'; end if;
  if v_st is null and exists (select 1 from jsonb_array_elements(coalesce(p->'lignes', '[]')) e where e->>'type_ligne' = 'installation') then
    raise exception 'Installation sans sous-traitant' using errcode = 'P0001';
  end if;
  if p->>'lead_id' is not null then select * into l from public.leads where id = (p->>'lead_id')::uuid; end if;
  v_succ := coalesce(p->>'succursale_code', l.succursale_code);
  if v_succ is null then raise exception 'Succursale requise' using errcode = 'P0001'; end if;
  v_client := coalesce(v_client, l.client_id);
  if v_client is null then
    if l.id is null then raise exception 'Client ou lead requis' using errcode = 'P0001'; end if;
    insert into public.clients (nom, telephone, courriel, succursale_code, vendeur_id)
    values (coalesce(nullif(trim(l.contact_nom), ''), 'Client sans nom'), l.contact_tel, l.contact_courriel, v_succ, l.assigne_a)
    returning id into v_client;
    update public.leads set client_id = v_client where id = l.id;
  end if;
  insert into public.projets (division, succursale_code, client_id, vendeur_id, statut, lead_id, devis_numero_mike,
                              montant_avant_taxes_cents, type_systeme, signe_le, sous_traitant_id)
  values ('Ventilation', v_succ, v_client, coalesce(nullif(p->>'vendeur_id', '')::uuid, l.assigne_a), 'attente_paiement', l.id, v_numero,
          nullif(p->>'montant_avant_taxes_cents', '')::bigint, coalesce(p->>'type_systeme', l.type_demande), v_signe, v_st)
  returning id into v_projet;
  for x in select * from jsonb_array_elements(coalesce(p->'lignes', '[]')) loop
    v_pos := v_pos + 1;
    if x->>'type_ligne' = 'machine' then
      insert into public.projet_lignes (projet_id, position, type_ligne, description, quantite)
      values (v_projet, v_pos, 'machine', trim(x->>'description'), coalesce(nullif(x->>'quantite', '')::numeric, 1));
    elsif x->>'type_ligne' = 'installation' then
      v_type := (x->>'type_travail_id')::uuid;
      if not exists (select 1 from public.travaux_sous_traitants where fournisseur_id = v_st and type_travail_id = v_type) then
        raise exception 'Ce travail n''est pas confié à ce sous-traitant' using errcode = 'P0001';
      end if;
      v_cout := public.hvac_cout_installation(v_st, v_type, (v_signe at time zone 'America/Toronto')::date);
      if v_cout is null then raise exception 'Aucun prix pour ce travail dans la liste du sous-traitant' using errcode = 'P0001'; end if;
      select nom into v_nom from public.types_travaux where id = v_type;
      insert into public.projet_lignes (projet_id, position, type_ligne, description, quantite, type_travail_id, cout_cents)
      values (v_projet, v_pos, 'installation', v_nom, coalesce(nullif(x->>'quantite', '')::numeric, 1), v_type, v_cout);
    else
      raise exception 'Type de ligne inconnu' using errcode = 'P0001';
    end if;
  end loop;
  if l.id is not null and l.statut <> 'converti' then
    insert into public.lead_activites (lead_id, type, note) values (l.id, 'vendu', 'Soumission #' || v_numero || ' signée par le client');
  end if;
  return v_projet;
end $$;
create or replace view public.projets_macro_v with (security_invoker = true) as
select p.id, p.code_projet, p.statut, p.succursale_code, p.client_id, trim(coalesce(c.prenom || ' ', '') || c.nom) as client_nom,
       coalesce(s.ville, l.ville) as ville, p.vendeur_id, trim(e.prenom || ' ' || e.nom) as vendeur_nom, p.lead_id, p.devis_numero_mike,
       p.montant_avant_taxes_cents, p.type_systeme, p.signe_le, p.installation_prevue_le, p.created_at, p.updated_at,
       p.sous_traitant_id, f.nom as sous_traitant_nom,
       (select sum(round(pl.quantite * pl.cout_cents))::bigint from public.projet_lignes pl
         where pl.projet_id = p.id and pl.type_ligne = 'installation') as cout_installation_cents
  from public.projets p
  join public.clients c on c.id = p.client_id
  left join public.sites s on s.id = p.site_id
  left join public.leads l on l.id = p.lead_id
  left join public.employes e on e.id = p.vendeur_id
  left join public.fournisseurs f on f.id = p.sous_traitant_id
 where p.division = 'Ventilation';
grant select on public.projets_macro_v to authenticated;
revoke all on public.projets_macro_v from anon;
create or replace function public.hvac_mes_projets(p_fournisseur uuid default null)
returns table (id uuid, code_projet text, statut text, ville text, type_systeme text, signe_le timestamptz,
               installation_prevue_le timestamptz, client_nom text, client_telephone text, adresse text,
               lignes jsonb, total_cents bigint)
language plpgsql stable security definer set search_path = public as $$
declare v_f uuid := coalesce(app.mon_fournisseur(), case when app.est_admin() or app.est_planification() then p_fournisseur end);
begin
  if v_f is null then raise exception 'Sous-traitant requis' using errcode = '42501'; end if;
  return query
  select p.id, p.code_projet, p.statut, coalesce(s.ville, ld.ville), p.type_systeme, p.signe_le, p.installation_prevue_le,
         case when p.statut <> 'attente_paiement' then trim(coalesce(c.prenom || ' ', '') || c.nom) end,
         case when p.statut <> 'attente_paiement' then c.telephone end,
         case when p.statut <> 'attente_paiement' then s.adresse end,
         coalesce((select jsonb_agg(jsonb_build_object('type_ligne', pl.type_ligne, 'description', pl.description, 'quantite', pl.quantite,
                     'prix_cents', case when pl.type_ligne = 'installation' then pl.cout_cents else 0 end,
                     'total_cents', case when pl.type_ligne = 'installation' then round(pl.quantite * pl.cout_cents)::bigint else 0 end)
                     order by pl.position)
                     from public.projet_lignes pl where pl.projet_id = p.id), '[]'::jsonb),
         coalesce((select sum(round(pl.quantite * pl.cout_cents))::bigint from public.projet_lignes pl
                    where pl.projet_id = p.id and pl.type_ligne = 'installation'), 0)
    from public.projets p
    join public.clients c on c.id = p.client_id
    left join public.sites s on s.id = p.site_id
    left join public.leads ld on ld.id = p.lead_id
   where p.sous_traitant_id = v_f and p.statut not in ('annule','ferme')
   order by p.signe_le desc nulls last;
end $$;
revoke all on function public.hvac_mes_projets(uuid) from public, anon;
grant execute on function public.hvac_mes_projets(uuid) to authenticated;
