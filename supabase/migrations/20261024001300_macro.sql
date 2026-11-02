-- Macro HVAC (ADR-079) : chaque projet signé par le client tombe dans la tuile Macro.
-- Le client signe dans l'app de Mike (page publique accepter / refuser) ; à la greffe, son webhook appelle
-- hvac_projet_signe. D'ici là : saisie par Belleflamme (admin, planification) et simulation dans le HTML de test.
-- Le lead d'origine passe à « Vendu » (nouvelle activité « vendu »).

-- 1. Lead vendu
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

-- 2. Projet : lien avec le lead et avec le devis signé chez Mike
alter table public.projets
  add column lead_id uuid references public.leads(id),
  add column devis_numero_mike text unique,           -- numéro du devis signé dans l'app de Mike (#120815)
  add column montant_avant_taxes_cents bigint check (montant_avant_taxes_cents >= 0),
  add column type_systeme text check (type_systeme in ('mural_simple','mural_multi','central','bienergie')),
  add column signe_le timestamptz;
create index projets_lead on public.projets (lead_id);

-- 3. Étapes : un projet avance (une ou plusieurs étapes) ou recule d'une seule ; annulé avant facturation seulement
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

-- 4. Réception d'un projet signé. p : { lead_id?, client_id?, succursale_code?, devis_numero_mike, montant_avant_taxes_cents,
--    type_systeme?, vendeur_id?, signe_le? }. Sans client : créé à partir du lead. Une seule fois par devis.
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

-- 5. Vue de la tuile Macro
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
