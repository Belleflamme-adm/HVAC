import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { TYPES_TRAVAUX, CATEGORIES, UNITES } from '../../scripts/reference/types-travaux.mjs';
import { genererMigration } from '../../scripts/reference/generer-types-travaux.mjs';

test('liste de prix : codes uniques, catégories et unités connues, jamais de tiret cadratin', () => {
  const codes = TYPES_TRAVAUX.map((t) => t.code);
  assert.equal(new Set(codes).size, codes.length, 'codes uniques');
  const cats = new Set(CATEGORIES.map(([c]) => c));
  for (const t of TYPES_TRAVAUX) {
    assert.ok(cats.has(t.categorie), t.code);
    assert.ok(UNITES[t.unite], t.code);
    assert.match(t.code, /^[A-Z0-9-]{3,40}$/);
    assert.ok(!`${t.nom} ${t.inclus || ''}`.includes('—'), t.code);
  }
  assert.ok(codes.includes('INST-TETE-MULTI'), 'code de Mike repris');
  for (const n of [2, 3, 4, 5]) assert.ok(codes.includes(`INST-MULTI-${n}T`));
});

test('liste de prix : la migration commise correspond à la source', () => {
  assert.equal(readFileSync('supabase/migrations/20261024000700_liste_prix_installation.sql', 'utf8'), genererMigration(),
    'relancer node scripts/reference/generer-types-travaux.mjs');
});
