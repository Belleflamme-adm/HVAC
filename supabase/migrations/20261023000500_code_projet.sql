-- Code projet réel de Belleflamme (Simon, 22 oct. 2026, voir docs/reference/FORMATS-MIKE.md) :
--   [SUCC][DIV]-[3 lettres prénom]-[3 lettres nom]-[NNN]      ex. STV-JEA-TRE-001
--   NNN : 001 pour le 1er devis, 002 pour le 2e, etc.
-- Le code est attribué à chaque DEVIS ; le projet issu d'un devis accepté reprend son code.
-- Le compteur est tenu par préfixe (ex. STV-JEA-TRE) : deux clients aux noms semblables
-- (Jean et Jeanne Tremblay) ne peuvent jamais recevoir le même code.

insert into public.formats_numerotation (cle, modele, prefixe, portee, description) values
  ('code_projet', '{prefixe}-{seq:3}', '', 'globale', 'Code projet Belleflamme : compteur par préfixe [SUCC][DIV]-[PRÉ]-[NOM].')
on conflict (cle) do update set modele = excluded.modele, description = excluded.description;

-- 3 lettres majuscules sans accents ; complété avec X si le mot est trop court.
create or replace function app.code3(p_texte text) returns text
language sql immutable as $$
  select rpad(left(regexp_replace(upper(translate(
           replace(replace(replace(replace(coalesce(p_texte, ''), 'œ', 'oe'), 'Œ', 'OE'), 'æ', 'ae'), 'Æ', 'AE'),
           'àâäáãåçéèêëíìîïñóòôöõúùûüýÿÀÂÄÁÃÅÇÉÈÊËÍÌÎÏÑÓÒÔÖÕÚÙÛÜÝŸ',
           'aaaaaaceeeeiiiinooooouuuuyyAAAAAACEEEEIIIINOOOOOUUUUYY')), '[^A-Z]', '', 'g'), 3), 3, 'X')
$$;

-- Préfixe d'un client : entreprise sans prénom -> le nom de l'entreprise tient lieu de prénom.
create or replace function app.prefixe_code_projet(p_succursale text, p_division text, p_client uuid) returns text
language sql stable security definer set search_path = public as $$
  select p_succursale || d.lettre || '-' || app.code3(coalesce(nullif(c.prenom, ''), c.entreprise, c.nom)) || '-' || app.code3(c.nom)
    from public.clients c, public.divisions d
   where c.id = p_client and d.nom = p_division
$$;

-- Réserve le prochain code (sans trou, jamais décrémenté : table compteurs).
create or replace function app.prochain_code_projet(p_succursale text, p_division text, p_client uuid) returns text
language plpgsql security definer set search_path = public as $$
declare v_prefixe text := app.prefixe_code_projet(p_succursale, p_division, p_client); v_n bigint;
begin
  if v_prefixe is null then raise exception 'Code projet : client ou division introuvable'; end if;
  insert into public.compteurs(cle, periode) values ('code_projet', v_prefixe) on conflict do nothing;
  update public.compteurs set prochain = prochain + 1, updated_at = now()
   where cle = 'code_projet' and periode = v_prefixe
  returning prochain - 1 into v_n;
  if v_n > 999 then raise exception 'Code projet : plus de 999 devis pour %', v_prefixe; end if;
  return v_prefixe || '-' || lpad(v_n::text, 3, '0');
end $$;
revoke all on function app.prochain_code_projet(text, text, uuid) from public, authenticated;

alter table public.devis add column code_projet text unique;

create or replace function app.devis_numero() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    new.numero := app.prochain_numero('devis', new.succursale_code, null, new.date_devis);
    new.code_projet := app.prochain_code_projet(new.succursale_code, new.division, new.client_id);
    new.sous_total_cents := 0; new.rabais_cents := 0; new.tps_cents := 0;
    new.tvq_cents := 0; new.total_cents := 0; new.depot_cents := 0;
    return new;
  end if;
  if new.numero is distinct from old.numero or new.code_projet is distinct from old.code_projet then
    raise exception 'Le numéro et le code projet d''un devis ne se modifient pas' using errcode = '42501';
  end if;
  if pg_trigger_depth() = 1 then
    new.sous_total_cents := old.sous_total_cents; new.rabais_cents := old.rabais_cents;
    new.tps_cents := old.tps_cents; new.tvq_cents := old.tvq_cents;
    new.total_cents := old.total_cents; new.depot_cents := old.depot_cents;
    if new.depot_bp is distinct from old.depot_bp or new.client_id is distinct from old.client_id
       or new.date_devis is distinct from old.date_devis then
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

-- Projet : reprend le code du devis accepté ; sans devis, nouveau code pour le client.
create or replace function app.projet_avant() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    if new.devis_id is not null then
      select code_projet into new.code_projet from public.devis where id = new.devis_id;
    end if;
    if new.code_projet is null then
      new.code_projet := app.prochain_code_projet(new.succursale_code, new.division, new.client_id);
    end if;
  elsif new.code_projet is distinct from old.code_projet then
    raise exception 'Le code projet ne se modifie pas' using errcode = '42501';
  end if;
  new.solde_du_le := new.installation_prevue_le
    - coalesce((select (valeur #>> '{}')::int from public.parametres where cle = 'delai_solde_heures'), 72)
      * interval '1 hour';
  return new;
end $$;

-- La vue des devis expose le code projet (recréée : nouvelle colonne dans devis).
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
