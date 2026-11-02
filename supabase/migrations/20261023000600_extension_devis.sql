-- Renouvellement (extension) d'un devis (Simon, 22 oct. 2026) :
-- le code d'origine est conservé et suffixé -E01, -E02... : STV-JEA-TRE-001-E01.
-- Les extensions sont comptées par devis d'origine, même si on renouvelle une extension.

insert into public.formats_numerotation (cle, modele, prefixe, portee, description) values
  ('extension_devis', '{prefixe}-E{seq:2}', '', 'globale', 'Extension d''un devis renouvelé : compteur par code d''origine.')
on conflict (cle) do nothing;

alter table public.devis add column devis_origine_id uuid references public.devis(id);

create or replace function app.prochain_code_extension(p_origine uuid) returns text
language plpgsql security definer set search_path = public as $$
declare v_code text; v_n bigint;
begin
  select code_projet into v_code from public.devis where id = p_origine;
  if v_code is null then raise exception 'Devis d''origine introuvable' using errcode = 'P0002'; end if;
  insert into public.compteurs(cle, periode) values ('extension_devis', v_code) on conflict do nothing;
  update public.compteurs set prochain = prochain + 1, updated_at = now()
   where cle = 'extension_devis' and periode = v_code
  returning prochain - 1 into v_n;
  if v_n > 99 then raise exception 'Plus de 99 extensions pour %', v_code; end if;
  return v_code || '-E' || lpad(v_n::text, 2, '0');
end $$;
revoke all on function app.prochain_code_extension(uuid) from public, authenticated;

create or replace function app.devis_numero() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    new.numero := app.prochain_numero('devis', new.succursale_code, null, new.date_devis);
    if new.devis_origine_id is not null then
      -- Toujours rattaché au devis d'origine (une extension d'extension compte sur l'origine).
      select coalesce(devis_origine_id, id) into new.devis_origine_id from public.devis where id = new.devis_origine_id;
      new.code_projet := app.prochain_code_extension(new.devis_origine_id);
    else
      new.code_projet := app.prochain_code_projet(new.succursale_code, new.division, new.client_id);
    end if;
    new.sous_total_cents := 0; new.rabais_cents := 0; new.tps_cents := 0;
    new.tvq_cents := 0; new.total_cents := 0; new.depot_cents := 0;
    return new;
  end if;
  if new.numero is distinct from old.numero or new.code_projet is distinct from old.code_projet
     or new.devis_origine_id is distinct from old.devis_origine_id then
    raise exception 'Le numéro, le code projet et l''origine d''un devis ne se modifient pas' using errcode = '42501';
  end if;
  if pg_trigger_depth() = 1 then
    new.sous_total_cents := old.sous_total_cents; new.rabais_cents := old.rabais_cents;
    new.tps_cents := old.tps_cents; new.tvq_cents := old.tvq_cents;
    new.total_cents := old.total_cents; new.depot_cents := old.depot_cents;
    if new.depot_bp is distinct from old.depot_bp or new.date_devis is distinct from old.date_devis then
      if old.statut <> 'brouillon' then
        raise exception 'Devis non modifiable (statut %)', old.statut using errcode = '42501';
      end if;
    end if;
    if new.client_id is distinct from old.client_id then
      raise exception 'Le client d''un devis ne se change pas (le code projet en dépend) : créer un nouveau devis'
        using errcode = '42501';
    end if;
  end if;
  return new;
end $$;

-- Renouvellement : même code + extension, mêmes lignes, en brouillon.
create or replace function public.hvac_dupliquer_devis(p_devis uuid) returns uuid
language plpgsql security invoker set search_path = public as $$
declare d public.devis%rowtype; v_id uuid;
begin
  select * into d from public.devis where id = p_devis;
  if not found then raise exception 'Devis introuvable' using errcode = 'P0002'; end if;
  insert into public.devis (division, succursale_code, client_id, site_id, lead_id, inspection_id, vendeur_id,
                            mode_paiement, depot_bp, notes_client, notes_internes, devis_origine_id)
  values (d.division, d.succursale_code, d.client_id, d.site_id, d.lead_id, d.inspection_id,
          coalesce(app.employe_id(), d.vendeur_id), d.mode_paiement, d.depot_bp, d.notes_client,
          concat_ws(E'\n', d.notes_internes, 'Renouvellement du devis ' || d.numero || ' (' || d.code_projet || ')'),
          d.id)
  returning id into v_id;
  insert into public.devis_lignes (devis_id, position, type_ligne, produit_id, kit_id, type_travail_id, sous_traitant_id,
                                   cout_cents, source_cout, reference_soumission, description, quantite,
                                   prix_unitaire_cents, rabais_bp, taxable)
  select v_id, position, type_ligne, produit_id, kit_id, type_travail_id, sous_traitant_id,
         case when source_cout = 'soumission' then cout_cents end, source_cout, reference_soumission,
         description, quantite, prix_unitaire_cents, rabais_bp, taxable
    from public.devis_lignes where devis_id = p_devis order by position;
  return v_id;
end $$;

-- devis_v reprend la nouvelle colonne
drop view public.devis_v;
create view public.devis_v with (security_invoker = true) as
  select d.*,
         case when d.statut = 'envoye' and d.valide_jusqu < current_date then 'expire' else d.statut end as statut_effectif,
         c.prenom as client_prenom, c.nom as client_nom, c.entreprise as client_entreprise,
         e.prenom || ' ' || e.nom as vendeur_nom,
         (select count(*) from public.approbations_rabais a where a.devis_id = d.id and a.statut = 'en_attente') as approbations_en_attente,
         exists (select 1 from public.devis_lignes l where l.devis_id = d.id and l.approbation_requise
                   and not exists (select 1 from public.approbations_rabais a where a.devis_ligne_id = l.id
                                    and a.statut = 'approuvee' and a.rabais_bp >= l.rabais_bp)) as bloque_par_rabais
    from public.devis d
    join public.clients c on c.id = d.client_id
    left join public.employes e on e.id = d.vendeur_id;
grant select on public.devis_v to authenticated;
revoke all on public.devis_v from anon;
