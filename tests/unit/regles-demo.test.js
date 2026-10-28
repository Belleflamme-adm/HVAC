// Les règles du HTML de test doivent rester identiques à celles de la base (migration du moteur, ADR-090)
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const sql = readFileSync('supabase/migrations/20261028000100_moteur_regles.sql', 'utf8');
const demo = readFileSync('scripts/demo/faux-serveur.js', 'utf8');
const seeds = sql.slice(sql.indexOf('insert into public.regles (code'));
// Chaque règle de la base : ('code', 'nom', ..., 'declencheur', '{conditions}', '[étapes]', '{arret}', commercial)
const lignes = [...seeds.matchAll(/^\('([a-z_]+)', '((?:[^']|'')*)', '((?:[^']|'')*)', '([a-z_]+)',\s*'(\{[^']*\})',\s*'(\[[\s\S]*?\])',\s*'\{([a-z_,]*)\}', (true|false)\)/gm)];

test('les 8 règles de la base sont lues', () => { assert.equal(lignes.length, 8); });

test('mêmes codes, noms, étapes, arrêts et commercial dans le HTML de test', () => {
  const bloc = demo.slice(demo.indexOf('const REGLES_DEMO = ['), demo.indexOf('];', demo.indexOf('const REGLES_DEMO = [')) + 2);
  const REGLES_DEMO = Function(`${bloc.replace('const REGLES_DEMO =', 'return')}`)();
  for (const [, code, nom, , decl, conds, etapes, arret, commercial] of lignes) {
    const d = REGLES_DEMO.find((r) => r.code === code);
    assert.ok(d, `règle ${code} absente du HTML de test`);
    assert.equal(d.nom, nom.replace(/''/g, "'"), `${code} : nom`);
    assert.equal(d.declencheur, decl, `${code} : déclencheur`);
    assert.deepEqual(d.conditions, JSON.parse(conds), `${code} : conditions`);
    assert.deepEqual(d.etapes, JSON.parse(etapes.replace(/''/g, "'")), `${code} : étapes`);
    assert.deepEqual(d.arret, arret ? arret.split(',') : [], `${code} : arrêts`);
    assert.equal(d.commercial, commercial === 'true', `${code} : commercial`);
  }
});
