-- Projet annulé : on ne garde rien (ADR-094, décision de Simon). Les photos de la job et des extras d'un projet annulé
-- (annulé en plein chantier, par exemple) sont purgées à la prochaine passe de la tâche planifiée, sans délai.
-- Les jobs terminées gardent la règle des 5 ans après « Terminé » (ADR-084). Un projet annulé ne revient jamais.

create or replace function public.hvac_photos_a_purger(p_limite integer default 500)
returns table (source text, id uuid, bucket text, chemin text)
language sql stable security definer set search_path = public as $$
  (select 'job', ph.id, 'jobs-photos', ph.chemin from public.projet_photos ph join public.projets p on p.id = ph.projet_id
    where ph.statut in ('televersee','retiree','prevue')
      and (p.statut = 'annule' or p.installation_terminee_le < now() - interval '5 years'))
  union all
  (select 'extra', ph.id, 'extras-photos', ph.chemin from public.projet_extra_photos ph
     join public.projet_extras x on x.id = ph.extra_id join public.projets p on p.id = x.projet_id
    where ph.statut in ('televersee','retiree','prevue')
      and (p.statut = 'annule' or p.installation_terminee_le < now() - interval '5 years'))
  limit p_limite
$$;
revoke all on function public.hvac_photos_a_purger(integer) from public, anon, authenticated;
grant execute on function public.hvac_photos_a_purger(integer) to service_role;
