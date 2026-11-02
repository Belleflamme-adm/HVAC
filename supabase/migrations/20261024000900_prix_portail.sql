-- Liste de prix gérée par le sous-traitant dans son portail (ADR-062). Remplace la demande par lien (ADR-061, en veille).
-- 1. Simon choisit les travaux confiés à chaque sous-traitant (travaux_sous_traitants).
-- 2. Le sous-traitant modifie ses prix quand il veut : le nouveau prix s'applique aux NOUVEAUX devis.
-- 3. Les devis actifs (envoyés non expirés, ou acceptés) gardent leur prix : le sous-traitant doit les honorer
--    jusqu'à l'expiration ; il voit le rapport de ses engagements avant et après chaque modification.
-- 4. Le vendeur de chaque devis actif touché et Simon / Mike sont avisés. Au renouvellement, le devis prend le
--    prix en vigueur (déjà le cas : la ligne d'installation se recalcule) et le vendeur est avisé de l'écart.

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

-- Les travaux qui ont déjà un prix sont confiés d'office
insert into public.travaux_sous_traitants (fournisseur_id, type_travail_id)
select distinct fournisseur_id, type_travail_id from public.tarifs_sous_traitants on conflict do nothing;

-- Un prix changé deux fois le même jour : on remplace celui du jour (les jours précédents restent l'historique)
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

-- Engagements : lignes d'installation (prix de la grille) des devis actifs d'un sous-traitant
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

-- Le sous-traitant voit ses engagements (sans le nom du client : Loi 25 ; numéro de devis, ville, échéance)
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

-- Le sous-traitant modifie ses prix (travaux confiés seulement). p_prix : [{ type_travail_id, cout_cents }]
-- Retour : nombre de prix changés et engagements touchés.
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
    -- Avis aux vendeurs des devis actifs touchés (une fois par devis et par travail)
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

-- Renouvellement : le devis prend les prix en vigueur (recalcul de la ligne d'installation) et le vendeur
-- est avisé de chaque écart avec le devis d'origine.
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

-- Écarts visibles sur le devis renouvelé
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
