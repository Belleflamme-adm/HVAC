-- Phase 1 | Numérotation séquentielle sans trou (ADR-004).
-- Principe : une table de compteurs verrouillée par UPDATE dans la même transaction
-- que l'insertion du document. Si la transaction échoue, le compteur revient en
-- arrière avec elle : aucun trou. Pas de SEQUENCE (elle crée des trous).
-- Règle de Mike / Revenu Québec : un compteur ne décrémente jamais.

-- Format configurable par type de document. Les formats réels de Mike sont à confirmer.
-- Jetons : {prefixe} {annee} {aa} {succ} {div} {seq} {seq:N} (N = largeur, zéros à gauche)
create table public.formats_numerotation (
  cle         text primary key,       -- devis | facture | note_credit | projet | bt | asv | contrat
  modele      text not null,
  prefixe     text not null default '',
  portee      text not null default 'annuelle'
              check (portee in ('globale','annuelle','succursale','succursale_annuelle')),
  description text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
call app.preparer_table('public.formats_numerotation', false);

create table public.compteurs (
  cle        text not null references public.formats_numerotation(cle),
  periode    text not null,          -- '*' | '2026' | 'RO' | 'RO-2026'
  prochain   bigint not null default 1 check (prochain >= 1),
  updated_at timestamptz not null default now(),
  primary key (cle, periode)
);

create or replace function app.compteur_garde() returns trigger
language plpgsql as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'Suppression d''un compteur interdite (Revenu Québec)' using errcode = '42501';
  end if;
  if new.prochain < old.prochain then
    raise exception 'Décrément du compteur % interdit (% -> %)', old.cle, old.prochain, new.prochain
      using errcode = '42501';
  end if;
  return new;
end $$;

create trigger trg_compteur_garde before update or delete on public.compteurs
  for each row execute function app.compteur_garde();

-- Réserve le prochain numéro. Doit être appelée dans la transaction qui insère le document.
create or replace function app.prochain_numero(
  p_cle text, p_succursale text default null, p_division_lettre text default null,
  p_date date default current_date
) returns text
language plpgsql security definer set search_path = public as $$
declare
  f        public.formats_numerotation%rowtype;
  v_periode text;
  v_n      bigint;
  v_txt    text;
  v_largeur text;
begin
  select * into f from public.formats_numerotation where cle = p_cle;
  if not found then
    raise exception 'Format de numérotation inconnu : %', p_cle;
  end if;
  if f.portee in ('succursale','succursale_annuelle') and p_succursale is null then
    raise exception 'Succursale requise pour numéroter %', p_cle;
  end if;

  v_periode := case f.portee
    when 'globale' then '*'
    when 'annuelle' then to_char(p_date, 'YYYY')
    when 'succursale' then p_succursale
    else p_succursale || '-' || to_char(p_date, 'YYYY')
  end;

  insert into public.compteurs(cle, periode) values (p_cle, v_periode)
    on conflict do nothing;

  -- L'UPDATE pose un verrou de ligne : les transactions concurrentes attendent.
  update public.compteurs
     set prochain = prochain + 1, updated_at = now()
   where cle = p_cle and periode = v_periode
  returning prochain - 1 into v_n;

  v_txt := f.modele;
  v_txt := replace(v_txt, '{prefixe}', f.prefixe);
  v_txt := replace(v_txt, '{annee}', to_char(p_date, 'YYYY'));
  v_txt := replace(v_txt, '{aa}', to_char(p_date, 'YY'));
  v_txt := replace(v_txt, '{succ}', coalesce(p_succursale, ''));
  v_txt := replace(v_txt, '{div}', coalesce(p_division_lettre, ''));
  v_largeur := substring(v_txt from '\{seq:(\d+)\}');
  if v_largeur is not null then
    v_txt := regexp_replace(v_txt, '\{seq:\d+\}', lpad(v_n::text, v_largeur::int, '0'));
  end if;
  v_txt := replace(v_txt, '{seq}', v_n::text);
  return v_txt;
end $$;

revoke all on function app.prochain_numero(text, text, text, date) from public;
