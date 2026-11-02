#!/usr/bin/env node
// Génère la migration de la liste de prix des sous-traitants à partir de scripts/reference/types-travaux.mjs.
// Usage : node scripts/reference/generer-types-travaux.mjs
import { writeFileSync } from 'node:fs';
import { CATEGORIES, TYPES_TRAVAUX, UNITES } from './types-travaux.mjs';

const sql = (v) => (v === null || v === undefined ? 'null' : `'${String(v).replace(/'/g, "''")}'`);

export function genererMigration() {
  const ordreCat = Object.fromEntries(CATEGORIES.map(([c], i) => [c, i + 1]));
  const lignes = TYPES_TRAVAUX.map((x, i) => `  (${sql(x.code)}, ${sql(x.nom)}, ${sql(x.inclus)}, ${sql(x.categorie)}, ${sql(x.unite)}, ${ordreCat[x.categorie] * 100 + i})`);
  return `-- GÉNÉRÉ par scripts/reference/generer-types-travaux.mjs. Ne pas modifier à la main.
-- Liste de prix des sous-traitants (ADR-060) : catégorie, unité, ordre d'affichage, tous les travaux à chiffrer.

alter table public.types_travaux
  add column categorie text,
  add column unite text not null default 'forfait' check (unite in (${Object.keys(UNITES).map(sql).join(',')})),
  add column ordre integer not null default 0;

create table public.categories_travaux (
  code   text primary key,
  nom    text not null,
  ordre  integer not null
);
alter table public.categories_travaux enable row level security;
create policy lecture on public.categories_travaux for select to authenticated using (app.employe_id() is not null);
insert into public.categories_travaux (code, nom, ordre) values
${CATEGORIES.map(([c, n], i) => `  (${sql(c)}, ${sql(n)}, ${i + 1})`).join(',\n')};
alter table public.types_travaux add constraint types_travaux_categorie_fk foreign key (categorie) references public.categories_travaux(code);

insert into public.types_travaux (code, nom, description, categorie, unite, ordre) values
${lignes.join(',\n')}
on conflict (code) do update set nom = excluded.nom, description = excluded.description,
  categorie = excluded.categorie, unite = excluded.unite, ordre = excluded.ordre, updated_at = now();
`;
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const fichier = 'supabase/migrations/20261024000700_liste_prix_installation.sql';
  writeFileSync(fichier, genererMigration());
  console.log(`OK : ${TYPES_TRAVAUX.length} travaux dans ${CATEGORIES.length} catégories | ${fichier}`);
}
