-- Visite planifiée dans Pointage (ADR-086, demande de Simon) : le vendeur planifie la visite UNE fois, dans le calendrier
-- Pointage de l'app de Mike (formulaire de pré-installation Ventilation). La même date arrive toute seule dans le lead :
-- aucune double saisie. Un changement de date ou une annulation dans Pointage suit aussi.
-- Entrée : webhook signé de l'app de Mike (pointage-webhook), via la clé serveur. INACTIF tant que POINTAGE_SYNC_ENABLED=false.

-- 1. Journal : provenance de l'activité et référence de la visite chez Mike ; nouvelle activité « visite annulée »
alter table public.lead_activites add column source text not null default 'hvac' check (source in ('hvac','pointage'));
alter table public.lead_activites add column pointage_ref text;   -- identifiant de la visite (pré-installation) dans l'app de Mike
alter table public.lead_activites drop constraint lead_activites_type_check;
alter table public.lead_activites add constraint lead_activites_type_check check (type in ('attribution','prise_en_charge','appel',
  'courriel','texto','note','visite_planifiee','visite_annulee','perdu','reouvert','vendu'));
create index lead_activites_pointage on public.lead_activites (pointage_ref) where pointage_ref is not null;
alter table public.leads add column visite_pointage_ref text;

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
    visite_prevue_le = case when new.type = 'visite_planifiee' then new.visite_le
                            when new.type = 'visite_annulee' then null else l.visite_prevue_le end,
    visite_pointage_ref = case when new.type = 'visite_planifiee' then coalesce(new.pointage_ref, l.visite_pointage_ref)
                               when new.type = 'visite_annulee' then null else l.visite_pointage_ref end,
    perdu_le = case when new.type = 'perdu' then new.fait_le when new.type = 'reouvert' then null else l.perdu_le end,
    raison_perte = case when new.type = 'perdu' then new.note else l.raison_perte end,
    statut = case
      when new.type = 'vendu' then 'converti'
      when new.type = 'perdu' then 'perdu'
      when new.type = 'reouvert' then case when l.premier_contact_le is not null then 'contacte' else 'pris_en_charge' end
      when l.statut in ('converti','perdu') then l.statut
      when new.type = 'visite_planifiee' then 'inspection_planifiee'
      when new.type = 'visite_annulee' and l.statut = 'inspection_planifiee'
        then case when l.premier_contact_le is not null then 'contacte' else 'pris_en_charge' end
      when new.type in ('appel','courriel','texto') and l.statut in ('nouveau','pris_en_charge') then 'contacte'
      when new.type = 'prise_en_charge' and l.statut = 'nouveau' then 'pris_en_charge'
      else l.statut end
  where l.id = new.lead_id;
  return null;
end $$;

-- La référence Pointage d'un lead ne se change que par le journal (jamais par le navigateur)
create or replace function app.lead_ref_pointage_garde() returns trigger
language plpgsql as $$
begin
  if tg_op = 'INSERT' then new.visite_pointage_ref := null;
  elsif pg_trigger_depth() = 1 then new.visite_pointage_ref := old.visite_pointage_ref; end if;
  return new;
end $$;
create trigger trg_lead_ref_pointage before insert or update on public.leads for each row execute function app.lead_ref_pointage_garde();

-- Une fois Pointage branché (paramètre à true), le vendeur ne saisit plus la date de visite : seul Pointage l'envoie.
-- D'ici là, la saisie manuelle reste le moyen temporaire. Le navigateur n'inscrit jamais une activité « Pointage ».
insert into public.parametres (cle, valeur, description) values
  ('visites_pointage_seulement', 'false', 'true : la date de visite vient seulement de Pointage (app de Mike), plus de saisie manuelle dans le lead (ADR-086).')
on conflict (cle) do nothing;
drop policy ajout on public.lead_activites;
create policy ajout on public.lead_activites for insert to authenticated
  with check (exists (select 1 from public.leads l where l.id = lead_id) and employe_id = app.employe_id()
              and type not in ('attribution','visite_annulee') and source = 'hvac' and pointage_ref is null
              and not (type = 'visite_planifiee' and app.parametre_bool('visites_pointage_seulement', false)));

-- 2. Réception d'une visite de Pointage. p : { lead_ref?, telephone?, pointage_ref, visite_le?, annulee? }
--    lead_ref = identifiant de notre lead, transmis à Pointage par le bouton « Planifier dans Pointage ».
--    Sans lead_ref : par le téléphone du client, seulement s'il désigne UN lead ouvert. Rejouer le même envoi ne double rien.
create or replace function public.hvac_visite_pointage(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  l public.leads%rowtype; v_ref text := nullif(trim(p->>'pointage_ref'), '');
  v_le timestamptz := nullif(p->>'visite_le', '')::timestamptz; v_annulee boolean := coalesce((p->>'annulee')::boolean, false);
  v_tel text := nullif(regexp_replace(coalesce(p->>'telephone', ''), '\D', '', 'g'), ''); n int;
begin
  if v_ref is null then raise exception 'Référence de la visite Pointage requise' using errcode = 'P0001'; end if;
  if not v_annulee and v_le is null then raise exception 'Date de la visite requise' using errcode = 'P0001'; end if;
  if nullif(p->>'lead_ref', '') is not null then
    select * into l from public.leads where id = (p->>'lead_ref')::uuid;
  else
    select * into l from public.leads where visite_pointage_ref = v_ref limit 1;
    if l.id is null and v_tel is not null then
      select count(*) into n from public.leads where right(regexp_replace(coalesce(contact_tel, ''), '\D', '', 'g'), 10) = right(v_tel, 10)
         and statut not in ('converti','perdu');
      if n > 1 then raise exception 'Plusieurs leads ouverts pour ce téléphone : lead à préciser' using errcode = 'P0001'; end if;
      select * into l from public.leads where right(regexp_replace(coalesce(contact_tel, ''), '\D', '', 'g'), 10) = right(v_tel, 10)
         and statut not in ('converti','perdu');
    end if;
  end if;
  if l.id is null then raise exception 'Lead introuvable pour cette visite' using errcode = 'P0002'; end if;
  if v_annulee then
    if l.visite_pointage_ref is distinct from v_ref then return jsonb_build_object('lead_id', l.id, 'change', false); end if;
    insert into public.lead_activites (lead_id, type, note, source, pointage_ref, employe_id)
    values (l.id, 'visite_annulee', 'Visite annulée dans Pointage', 'pointage', v_ref, l.assigne_a);
  else
    if l.visite_pointage_ref = v_ref and l.visite_prevue_le = v_le then return jsonb_build_object('lead_id', l.id, 'change', false); end if;
    insert into public.lead_activites (lead_id, type, note, visite_le, source, pointage_ref, employe_id)
    values (l.id, 'visite_planifiee', case when l.visite_pointage_ref = v_ref then 'Visite déplacée dans Pointage' else 'Visite planifiée dans Pointage' end,
            v_le, 'pointage', v_ref, l.assigne_a);
  end if;
  return jsonb_build_object('lead_id', l.id, 'change', true);
end $$;
revoke all on function public.hvac_visite_pointage(jsonb) from public, anon, authenticated;
grant execute on function public.hvac_visite_pointage(jsonb) to service_role;

-- 3. leads_v (l.*) gagne visite_pointage_ref : les vues sont recréées à l'identique (aucune donnée, ce sont des vues)
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
