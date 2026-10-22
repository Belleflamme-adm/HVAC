-- Lot B | Commande : à l'acceptation d'un devis, la base crée le projet, le bon de travail (BT#RV001)
-- et les bons de commande (BC) en brouillon. Planification dans les disponibilités du sous-traitant,
-- jobs du sous-traitant, notifications (ADR-037, ADR-046, ADR-047).

insert into public.parametres (cle, valeur, description) values
  ('adresse_entrepot', '"1090 boul. des Laurentides, local 108, Saint-Jérôme (Québec) J7Z 7L1"',
   'Adresse de livraison par défaut des bons de commande (entrepôt).')
on conflict (cle) do nothing;

insert into public.formats_numerotation (cle, modele, prefixe, portee, description) values
  ('bt_projet', 'RV{seq:3}', 'RV', 'globale', 'BT « Vendu » d''un projet : RV001, RV002... par code projet.'),
  ('bc', '{prefixe}-{seq}', '', 'globale', 'Bon de commande : préfixe du code projet + série à partir de 100.')
on conflict (cle) do nothing;

-- Adresse du fournisseur : le sous-traitant doit savoir où ramasser le matériel.
alter table public.fournisseurs add column adresse text;

-- Préfixe d'un code projet : STV-JEA-TRE-001-E01 -> STV-JEA-TRE
create or replace function app.prefixe_de_code(p_code text) returns text
language sql immutable as $$ select substring(p_code from '^[A-Z]{3}-[A-Z]{3}-[A-Z]{3}') $$;

-- ---------------------------------------------------------------------------
-- Bons de travail : numéro BT#RV001 <code projet>, brouillon, lignes reprises du devis
-- ---------------------------------------------------------------------------
alter table public.bons_travail drop constraint bons_travail_statut_check;
alter table public.bons_travail add constraint bons_travail_statut_check
  check (statut in ('brouillon','planifie','en_cours','termine','annule'));
alter table public.bons_travail add column type text not null default 'RV';

create or replace function app.bt_numero() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_code text; v_n bigint;
begin
  if tg_op = 'INSERT' then
    if new.projet_id is not null then
      select code_projet into v_code from public.projets where id = new.projet_id;
      insert into public.compteurs(cle, periode) values ('bt_projet', v_code) on conflict do nothing;
      update public.compteurs set prochain = prochain + 1, updated_at = now()
       where cle = 'bt_projet' and periode = v_code returning prochain - 1 into v_n;
      new.numero := new.type || lpad(v_n::text, 3, '0') || ' ' || v_code;
    else
      new.numero := app.prochain_numero('bt', new.succursale_code, null, current_date);
    end if;
  elsif new.numero is distinct from old.numero then
    raise exception 'Le numéro ne se modifie pas' using errcode = '42501';
  end if;
  return new;
end $$;
drop trigger trg_numero on public.bons_travail;
create trigger trg_numero before insert or update on public.bons_travail
  for each row execute function app.bt_numero();

alter table public.bt_lignes
  add column position integer not null default 1,
  add column devis_ligne_id uuid references public.devis_lignes(id),
  add column type_ligne text not null default 'produit' check (type_ligne in ('produit','installation','service')),
  add column provenance text check (provenance in ('a_determiner','entrepot','a_commander')),
  add column quantite_installee numeric(10,2);

-- ---------------------------------------------------------------------------
-- Bons de commande (au coût) : un par fournisseur
-- ---------------------------------------------------------------------------
create table public.bons_commande (
  id                uuid primary key default gen_random_uuid(),
  numero            text unique,
  division          text not null default 'Ventilation' references public.divisions(nom),
  succursale_code   text not null references public.succursales(code),
  projet_id         uuid references public.projets(id),
  bon_travail_id    uuid references public.bons_travail(id),
  fournisseur_id    uuid not null references public.fournisseurs(id),
  statut            text not null default 'brouillon' check (statut in ('brouillon','envoye','confirme','recu','annule')),
  mode_livraison    text not null default 'entrepot' check (mode_livraison in ('entrepot','ramassage')),
  ramassage_par     uuid references public.fournisseurs(id),     -- sous-traitant qui ramasse chez le fournisseur
  adresse_livraison text,
  date_livraison    date,                                        -- null = « TBD »
  sous_total_cents  bigint not null default 0,
  tps_cents         bigint not null default 0,
  tvq_cents         bigint not null default 0,
  total_cents       bigint not null default 0,
  notes             text,
  envoye_le         timestamptz,
  recu_le           timestamptz,
  created_by        uuid references public.employes(id) default app.employe_id(),
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  check (mode_livraison <> 'ramassage' or ramassage_par is not null)
);
call app.preparer_table('public.bons_commande');
create index on public.bons_commande (projet_id);

create table public.bc_lignes (
  id                  uuid primary key default gen_random_uuid(),
  bon_commande_id     uuid not null references public.bons_commande(id),
  position            integer not null default 1,
  produit_id          uuid not null references public.produits(id),
  bt_ligne_id         uuid references public.bt_lignes(id),
  description         text not null,
  quantite            numeric(10,2) not null check (quantite > 0),
  cout_unitaire_cents bigint not null default 0,
  montant_cents       bigint not null default 0,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);
call app.preparer_table('public.bc_lignes', false);
alter table public.bt_lignes add column bc_ligne_id uuid references public.bc_lignes(id);

create or replace function app.bc_avant() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_code text; v_prefixe text; v_n bigint;
begin
  if tg_op = 'INSERT' then
    select code_projet into v_code from public.projets where id = new.projet_id;
    v_prefixe := coalesce(app.prefixe_de_code(v_code), 'HVAC');
    insert into public.compteurs(cle, periode, prochain) values ('bc', v_prefixe, 100) on conflict do nothing;
    update public.compteurs set prochain = prochain + 1, updated_at = now()
     where cle = 'bc' and periode = v_prefixe returning prochain - 1 into v_n;
    new.numero := v_prefixe || '-' || v_n;
    new.adresse_livraison := coalesce(new.adresse_livraison,
      (select valeur #>> '{}' from public.parametres where cle = 'adresse_entrepot'));
    return new;
  end if;
  if new.numero is distinct from old.numero then
    raise exception 'Le numéro de BC ne se modifie pas' using errcode = '42501';
  end if;
  if pg_trigger_depth() = 1 then   -- totaux : calculés par la base seulement
    new.sous_total_cents := old.sous_total_cents; new.tps_cents := old.tps_cents;
    new.tvq_cents := old.tvq_cents; new.total_cents := old.total_cents;
  end if;
  if new.statut <> old.statut then
    if not (old.statut, new.statut) in (('brouillon','envoye'),('brouillon','annule'),('envoye','confirme'),
                                        ('envoye','recu'),('confirme','recu'),('envoye','annule'),('confirme','annule')) then
      raise exception 'Passage de BC non permis : % -> %', old.statut, new.statut using errcode = 'P0001';
    end if;
    if new.statut = 'envoye' then
      if not exists (select 1 from public.bc_lignes where bon_commande_id = new.id) then
        raise exception 'BC % vide', new.numero using errcode = 'P0001';
      end if;
      new.envoye_le := now();
    end if;
    if new.statut = 'recu' then new.recu_le := now(); end if;
  elsif old.statut <> 'brouillon' and pg_trigger_depth() = 1
        and (new.fournisseur_id, new.projet_id) is distinct from (old.fournisseur_id, old.projet_id) then
    raise exception 'BC envoyé : fournisseur et projet figés' using errcode = '42501';
  end if;
  return new;
end $$;
create trigger trg_bc_avant before insert or update on public.bons_commande
  for each row execute function app.bc_avant();
create trigger trg_bc_delete before delete on public.bons_commande
  for each row execute function app.interdit();
create trigger trg_audit after insert or update on public.bons_commande
  for each row execute function app.audit();

-- Lignes : coût imposé par le catalogue, modifiables en brouillon seulement.
create or replace function app.bc_ligne_avant() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_statut text;
begin
  select statut into v_statut from public.bons_commande where id = coalesce(new.bon_commande_id, old.bon_commande_id);
  if v_statut <> 'brouillon' then
    raise exception 'BC non modifiable (statut %)', v_statut using errcode = '42501';
  end if;
  if tg_op = 'DELETE' then return old; end if;
  select cout_cents into new.cout_unitaire_cents from public.produits where id = new.produit_id;
  new.montant_cents := round(new.quantite * new.cout_unitaire_cents)::bigint;
  return new;
end $$;
create trigger trg_bc_ligne_avant before insert or update or delete on public.bc_lignes
  for each row execute function app.bc_ligne_avant();

create or replace function app.recalculer_bc(p_bc uuid) returns void
language plpgsql security definer set search_path = public as $$
declare v_net bigint; v_tps bigint; v_tvq bigint;
begin
  select coalesce(sum(montant_cents), 0) into v_net from public.bc_lignes where bon_commande_id = p_bc;
  select t.tps, t.tvq into v_tps, v_tvq from app.taxes(v_net, current_date) t;
  update public.bons_commande set sous_total_cents = v_net, tps_cents = v_tps, tvq_cents = v_tvq,
         total_cents = v_net + v_tps + v_tvq where id = p_bc;
end $$;
create or replace function app.bc_lignes_apres() returns trigger
language plpgsql security definer set search_path = public as $$
begin perform app.recalculer_bc(coalesce(new.bon_commande_id, old.bon_commande_id)); return null; end $$;
create trigger trg_bc_lignes_apres after insert or update or delete on public.bc_lignes
  for each row execute function app.bc_lignes_apres();

-- ---------------------------------------------------------------------------
-- Notifications (dans l'app) et file d'envois (courriel, SMS : fournisseur à choisir)
-- ---------------------------------------------------------------------------
create table public.notifications (
  id                     uuid primary key default gen_random_uuid(),
  destinataire_employe_id uuid references public.employes(id),
  destinataire_fournisseur_id uuid references public.fournisseurs(id),   -- tous les comptes de ce sous-traitant
  type                   text not null,
  titre                  text not null,
  message                text,
  lien                   text,
  lu_le                  timestamptz,
  created_at             timestamptz not null default now(),
  check (destinataire_employe_id is not null or destinataire_fournisseur_id is not null)
);
create table public.envois (
  id              uuid primary key default gen_random_uuid(),
  notification_id uuid references public.notifications(id),
  canal           text not null check (canal in ('courriel','sms')),
  destinataire    text not null,
  sujet           text,
  corps           text not null,
  statut          text not null default 'en_attente' check (statut in ('en_attente','envoye','echec','annule')),
  essais          integer not null default 0,
  derniere_erreur text,
  created_at      timestamptz not null default now(),
  envoye_le       timestamptz
);

create or replace function app.notifier_fournisseur(p_fournisseur uuid, p_type text, p_titre text, p_message text, p_lien text)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid; f public.fournisseurs%rowtype;
begin
  insert into public.notifications (destinataire_fournisseur_id, type, titre, message, lien)
  values (p_fournisseur, p_type, p_titre, p_message, p_lien) returning id into v_id;
  select * into f from public.fournisseurs where id = p_fournisseur;
  if f.courriel is not null then
    insert into public.envois (notification_id, canal, destinataire, sujet, corps) values (v_id, 'courriel', f.courriel, p_titre, p_message);
  end if;
  if f.telephone is not null then
    insert into public.envois (notification_id, canal, destinataire, corps) values (v_id, 'sms', f.telephone, p_titre || ' : ' || p_message);
  end if;
  return v_id;
end $$;

-- ---------------------------------------------------------------------------
-- Acceptation d'un devis : projet + BT brouillon + BC brouillons (un par fournisseur)
-- ---------------------------------------------------------------------------

-- Fournisseur d'un produit : le sien, sinon celui de sa marque.
create or replace function app.fournisseur_produit(p_produit uuid) returns uuid
language sql stable security definer set search_path = public as $$
  select coalesce(p.fournisseur_id, m.fournisseur_id)
    from public.produits p left join public.marques m on m.id = p.marque_id where p.id = p_produit
$$;
create or replace function app.creer_commande(p_devis uuid) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  d public.devis%rowtype; v_projet uuid; v_bt uuid; v_st uuid; v_pos int := 0; v_bc uuid;
  l record; c record;
begin
  select * into d from public.devis where id = p_devis;
  if exists (select 1 from public.projets where devis_id = p_devis) then
    return (select id from public.projets where devis_id = p_devis);
  end if;
  select sous_traitant_id into v_st from public.devis_lignes
   where devis_id = p_devis and type_ligne = 'installation' order by position limit 1;

  insert into public.projets (division, succursale_code, client_id, site_id, devis_id, vendeur_id, statut)
  values (d.division, d.succursale_code, d.client_id, d.site_id, d.id, d.vendeur_id, 'a_planifier')
  returning id into v_projet;

  insert into public.bons_travail (division, succursale_code, projet_id, assigne_fournisseur_id, statut, travaux)
  values (d.division, d.succursale_code, v_projet, v_st, 'brouillon',
          'Brouillon automatique à l''acceptation du devis #' || d.numero || '. À planifier (sous-traitant et date).')
  returning id into v_bt;

  -- Lignes du BT : produits (kits dépliés en composantes), installation, autres services. Rabais exclus.
  for l in
    select dl.id as devis_ligne_id, dl.position, 'produit' as type_ligne, dl.produit_id, dl.description, dl.quantite
      from public.devis_lignes dl where dl.devis_id = p_devis and dl.type_ligne = 'produit'
    union all
    select dl.id, dl.position, 'produit', ki.produit_id, p.nom, dl.quantite * ki.quantite
      from public.devis_lignes dl join public.kit_items ki on ki.kit_id = dl.kit_id join public.produits p on p.id = ki.produit_id
     where dl.devis_id = p_devis and dl.type_ligne = 'kit'
    union all
    select dl.id, dl.position, case when dl.type_ligne = 'installation' then 'installation' else 'service' end, null, dl.description, dl.quantite
      from public.devis_lignes dl where dl.devis_id = p_devis and dl.type_ligne in ('installation','libre')
    order by 2
  loop
    v_pos := v_pos + 1;
    insert into public.bt_lignes (bon_travail_id, position, devis_ligne_id, type_ligne, produit_id, description, quantite, provenance)
    values (v_bt, v_pos, l.devis_ligne_id, l.type_ligne, l.produit_id, l.description, l.quantite,
            case when l.type_ligne <> 'produit' then null
                 when app.fournisseur_produit(l.produit_id) is not null
                      and exists (select 1 from public.produits p where p.id = l.produit_id and p.stocke)
                   then 'a_commander' else 'a_determiner' end);
  end loop;

  -- BC brouillons : un par fournisseur, pour les lignes « à commander »
  for c in
    select app.fournisseur_produit(bl.produit_id) as fournisseur_id from public.bt_lignes bl
     where bl.bon_travail_id = v_bt and bl.provenance = 'a_commander' group by 1
  loop
    insert into public.bons_commande (division, succursale_code, projet_id, bon_travail_id, fournisseur_id, mode_livraison, ramassage_par)
    values (d.division, d.succursale_code, v_projet, v_bt, c.fournisseur_id,
            case when v_st is not null then 'ramassage' else 'entrepot' end, v_st)
    returning id into v_bc;
    insert into public.bc_lignes (bon_commande_id, position, produit_id, bt_ligne_id, description, quantite)
    select v_bc, bl.position, bl.produit_id, bl.id, bl.description, bl.quantite
      from public.bt_lignes bl
     where bl.bon_travail_id = v_bt and bl.provenance = 'a_commander' and app.fournisseur_produit(bl.produit_id) = c.fournisseur_id;
    update public.bt_lignes bl set bc_ligne_id = x.id
      from public.bc_lignes x where x.bt_ligne_id = bl.id and x.bon_commande_id = v_bc;
  end loop;
  return v_projet;
end $$;

create or replace function app.devis_accepte_apres() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform app.creer_commande(new.id);
  return null;
end $$;
create trigger trg_devis_accepte after update of statut on public.devis
  for each row when (new.statut = 'accepte' and old.statut is distinct from 'accepte')
  execute function app.devis_accepte_apres();

-- ---------------------------------------------------------------------------
-- Planification : journée disponible du sous-traitant + dépôt payé ou financement approuvé.
-- Confirmée automatiquement ; le sous-traitant est avisé (ADR-047).
-- ---------------------------------------------------------------------------
create or replace function app.paiement_permet_planif(p_projet uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.factures f where f.projet_id = p_projet and f.type = 'depot' and f.statut = 'payee')
      or exists (select 1 from public.financements fi where fi.projet_id = p_projet and fi.statut in ('approuve','finance'))
$$;

create or replace function public.hvac_planifier_bt(p_bt uuid, p_jour date, p_heure time default '08:00',
                                                    p_fuseau text default 'America/Toronto')
returns jsonb language plpgsql security definer set search_path = public as $$
declare b public.bons_travail%rowtype; v_debut timestamptz; v_code text; v_adresse text;
begin
  if not app.est_planification() then
    raise exception 'Planification réservée à la coordination, Simon et Mike' using errcode = '42501';
  end if;
  select * into b from public.bons_travail where id = p_bt for update;
  if not found then raise exception 'BT introuvable' using errcode = 'P0002'; end if;
  if b.statut not in ('brouillon','planifie') then
    raise exception 'BT % : statut % non planifiable', b.numero, b.statut using errcode = 'P0001';
  end if;
  if b.assigne_fournisseur_id is null then
    raise exception 'BT % : aucun sous-traitant assigné', b.numero using errcode = 'P0001';
  end if;
  if p_jour < current_date then raise exception 'Date passée' using errcode = 'P0001'; end if;
  if not exists (select 1 from public.disponibilites_sous_traitants
                  where fournisseur_id = b.assigne_fournisseur_id and jour = p_jour and statut = 'disponible') then
    raise exception 'Le sous-traitant n''est pas disponible le %', p_jour using errcode = 'P0001';
  end if;
  if not app.paiement_permet_planif(b.projet_id) then
    raise exception 'Planification bloquée : dépôt non payé et financement non approuvé' using errcode = 'P0001';
  end if;

  v_debut := (p_jour + p_heure) at time zone p_fuseau;
  update public.bons_travail set prevu_le = v_debut, statut = 'planifie' where id = p_bt;
  update public.projets set installation_prevue_le = v_debut, statut = 'planifie' where id = b.projet_id;

  select p.code_projet, s.adresse || ', ' || s.ville into v_code, v_adresse
    from public.projets p left join public.sites s on s.id = p.site_id where p.id = b.projet_id;
  perform app.notifier_fournisseur(b.assigne_fournisseur_id, 'job_planifiee',
    'Nouvelle job planifiée le ' || to_char(p_jour, 'YYYY-MM-DD'),
    'Projet ' || v_code || coalesce(' | ' || v_adresse, '') || ' | ' || to_char(p_heure, 'HH24:MI') || '. Détails dans l''app (Mes jobs).',
    '/jobs');
  return jsonb_build_object('bt', b.numero, 'prevu_le', v_debut);
end $$;
revoke all on function public.hvac_planifier_bt(uuid, date, time, text) from public, anon;
grant execute on function public.hvac_planifier_bt(uuid, date, time, text) to authenticated;

-- ---------------------------------------------------------------------------
-- Jobs du sous-traitant : seulement ce dont il a besoin (minimisation, Loi 25), accès journalisé.
-- ---------------------------------------------------------------------------
create or replace function public.hvac_mes_jobs() returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_f uuid := app.mon_fournisseur(); v_res jsonb;
begin
  if v_f is null then raise exception 'Réservé aux sous-traitants' using errcode = '42501'; end if;
  select coalesce(jsonb_agg(j order by j->>'prevu_le'), '[]'::jsonb) into v_res from (
    select jsonb_build_object(
      'id', b.id, 'numero', b.numero, 'statut', b.statut, 'prevu_le', b.prevu_le, 'code_projet', p.code_projet,
      'client', concat_ws(' ', c.prenom, c.nom), 'telephone', c.telephone,
      'adresse', s.adresse, 'ville', s.ville, 'code_postal', s.code_postal,
      'lignes', (select coalesce(jsonb_agg(jsonb_build_object('description', bl.description, 'quantite', bl.quantite,
                   'type', bl.type_ligne, 'provenance', bl.provenance) order by bl.position), '[]'::jsonb)
                   from public.bt_lignes bl where bl.bon_travail_id = b.id),
      'materiel', (select coalesce(jsonb_agg(jsonb_build_object('bc', bc.numero, 'statut', bc.statut, 'mode', bc.mode_livraison,
                   'fournisseur', fo.nom, 'adresse_fournisseur', fo.adresse, 'date_livraison', bc.date_livraison,
                   'adresse_livraison', bc.adresse_livraison)), '[]'::jsonb)
                   from public.bons_commande bc join public.fournisseurs fo on fo.id = bc.fournisseur_id
                  where bc.bon_travail_id = b.id and bc.statut <> 'annule')) as j
      from public.bons_travail b
      join public.projets p on p.id = b.projet_id
      join public.clients c on c.id = p.client_id
      left join public.sites s on s.id = p.site_id
     where b.assigne_fournisseur_id = v_f and b.statut in ('planifie','en_cours','termine')
  ) x;
  perform app.journaliser('lecture', 'jobs_sous_traitant', v_f::text, jsonb_build_object('nb', jsonb_array_length(v_res)));
  return v_res;
end $$;
revoke all on function public.hvac_mes_jobs() from public, anon;
grant execute on function public.hvac_mes_jobs() to authenticated;

-- Le sous-traitant fait avancer sa job : en cours, terminée.
create or replace function public.hvac_job_statut(p_bt uuid, p_statut text) returns void
language plpgsql security definer set search_path = public as $$
declare b public.bons_travail%rowtype;
begin
  select * into b from public.bons_travail where id = p_bt;
  if b.assigne_fournisseur_id is distinct from app.mon_fournisseur() then
    raise exception 'Cette job ne t''est pas assignée' using errcode = '42501';
  end if;
  if not (b.statut, p_statut) in (('planifie','en_cours'),('en_cours','termine')) then
    raise exception 'Passage non permis : % -> %', b.statut, p_statut using errcode = 'P0001';
  end if;
  update public.bons_travail set statut = p_statut,
         debut_le = case when p_statut = 'en_cours' then now() else debut_le end,
         fin_le = case when p_statut = 'termine' then now() else fin_le end
   where id = p_bt;
end $$;
revoke all on function public.hvac_job_statut(uuid, text) from public, anon;
grant execute on function public.hvac_job_statut(uuid, text) to authenticated;

-- ---------------------------------------------------------------------------
-- Sécurité
-- ---------------------------------------------------------------------------
alter table public.bons_commande enable row level security;
alter table public.bc_lignes enable row level security;
alter table public.notifications enable row level security;
alter table public.envois enable row level security;
revoke all on public.bons_commande, public.bc_lignes, public.notifications, public.envois from anon;

create or replace function app.voit_bc(p_bc uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select app.acces_succursale((select succursale_code from public.bons_commande where id = p_bc))
$$;
create or replace function app.gere_achats() returns boolean
language sql stable as $$ select app.est_planification() or coalesce(app.role() = 'Comptabilité', false) $$;

create policy lecture on public.bons_commande for select to authenticated using (app.acces_succursale(succursale_code));
create policy maj on public.bons_commande for update to authenticated
  using (app.gere_achats() and app.acces_succursale(succursale_code));
create policy lecture on public.bc_lignes for select to authenticated using (app.voit_bc(bon_commande_id));
create policy ajout on public.bc_lignes for insert to authenticated with check (app.gere_achats() and app.voit_bc(bon_commande_id));
create policy maj on public.bc_lignes for update to authenticated using (app.gere_achats() and app.voit_bc(bon_commande_id));
create policy retrait on public.bc_lignes for delete to authenticated using (app.gere_achats() and app.voit_bc(bon_commande_id));

-- BT : la planification modifie (assignation, provenance des lignes) ; le sous-traitant passe par les RPC.
create policy maj_planif on public.bt_lignes for update to authenticated using (app.est_planification());

create policy lecture on public.notifications for select to authenticated
  using (destinataire_employe_id = app.employe_id()
         or (destinataire_fournisseur_id is not null and destinataire_fournisseur_id = app.mon_fournisseur()));
create policy lu on public.notifications for update to authenticated
  using (destinataire_employe_id = app.employe_id()
         or (destinataire_fournisseur_id is not null and destinataire_fournisseur_id = app.mon_fournisseur()));
create policy lecture_admin on public.envois for select to authenticated using (app.est_admin());
