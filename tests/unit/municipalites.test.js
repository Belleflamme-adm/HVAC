import { test } from 'node:test';
import assert from 'node:assert/strict';
import { detecterChamps, genererSql, proprietesCarte } from '../../scripts/municipalites/convertir.mjs';

test('détection des champs : forcés, sinon erreur claire (on ne devine pas)', () => {
  assert.throws(() => detecterChamps({ A: 1, B: 2 }), /Champs disponibles : A, B/);
  assert.deepEqual(detecterChamps({ A: 1, B: 2 }, { code: 'A', nom: 'B' }), { code: 'A', nom: 'B', mrc: undefined, region: undefined });
});

test('SQL généré : apostrophes échappées, doublons ignorés, tri par code', () => {
  const champs = { code: 'c', nom: 'n', mrc: 'm', region: 'r' };
  const sql = genererSql([
    { properties: { c: '2', n: "L'Île", m: 'M', r: 'R' } },
    { properties: { c: '1', n: 'A', m: null, r: 'R' } },
    { properties: { c: '2', n: 'Doublon', m: 'M', r: 'R' } },
  ], champs, new Date('2026-10-22'));
  assert.match(sql, /\('1', 'A', null, 'R'\),\n {2}\('2', 'L''Île', 'M', 'R'\)/);
  assert.doesNotMatch(sql, /Doublon/);
  assert.match(sql, /CC-BY 4\.0/);
});

test('GeoJSON de la carte : code, nom, MRC et région (vides omis)', () => {
  const champs = { code: 'c', nom: 'n', mrc: 'm', region: 'r' };
  assert.deepEqual(proprietesCarte({ c: ' 75017 ', n: 'Saint-Jérôme', m: 'La Rivière-du-Nord', r: 'Laurentides', x: 1 }, champs),
    { code: '75017', nom: 'Saint-Jérôme', mrc: 'La Rivière-du-Nord', region: 'Laurentides' });
  assert.deepEqual(proprietesCarte({ c: '1', n: 'A', m: '', r: null }, champs), { code: '1', nom: 'A' });
});
