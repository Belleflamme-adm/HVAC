-- Photo obligatoire (ADR-083, demande de Simon) : un extra hors liste ou un imprévu de chantier ne part pas
-- pour approbation sans au moins une photo. La règle est vérifiée à l'envoi (on crée le brouillon, puis on ajoute la photo).
create or replace function public.hvac_extras_envoyer(p_projet uuid) returns integer
language plpgsql security definer set search_path = public as $$
declare pr public.projets%rowtype; n integer; v_total bigint; v_sans text;
begin
  pr := app.projet_extras_ouvert(p_projet);
  select string_agg(x.description, ', ' order by x.created_at) into v_sans
    from public.projet_extras x
   where x.projet_id = pr.id and x.statut = 'brouillon' and (x.hors_liste or x.cause = 'imprevu_chantier')
     and not exists (select 1 from public.projet_extra_photos ph where ph.extra_id = x.id and ph.statut = 'televersee');
  if v_sans is not null then
    raise exception 'Photo obligatoire pour un extra hors liste ou un imprévu de chantier : %', v_sans using errcode = 'P0001';
  end if;
  update public.projet_extras set statut = 'soumis', soumis_le = now() where projet_id = pr.id and statut = 'brouillon';
  get diagnostics n = row_count;
  if n = 0 then raise exception 'Aucun extra à envoyer' using errcode = 'P0001'; end if;
  select sum(round(quantite * cout_cents))::bigint into v_total from public.projet_extras where projet_id = pr.id and statut = 'soumis';
  perform app.notifier_planification('extras_a_approuver', 'Extras à approuver | ' || coalesce(pr.code_projet, 'projet'),
    format('%s : %s extra(s) en attente, %s $ avant taxes.', (select nom from public.fournisseurs where id = pr.sous_traitant_id), n,
           to_char(v_total / 100.0, 'FM999G999G990D00')), '/extras');
  return n;
end $$;
