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

import { casse, distanceKm, dansRayon, proprietesOntario, genererSqlOntario, OTTAWA } from '../../scripts/municipalites/ontario.mjs';

test('Ontario : noms en majuscules remis en casse lisible', () => {
  assert.equal(casse("CANTON D'ELIZABETHTOWN-KITLEY"), "Canton d'Elizabethtown-Kitley");
  assert.equal(casse('COMTÉS UNIS DE PRESCOTT AND RUSSELL'), 'Comtés unis de Prescott and Russell');
  assert.equal(casse('MCNAB / BRAESIDE'), 'McNab / Braeside');
  assert.equal(casse('CLARENCE-ROCKLAND'), 'Clarence-Rockland');
});

test('Ontario : rayon autour d\'Ottawa', () => {
  assert.ok(Math.abs(distanceKm(OTTAWA, [-74.6, 45.6]) - 88) < 5, 'Ottawa-Hawkesbury environ 88 km');
  const carre = (lon, lat) => ({ type: 'Polygon', coordinates: [[[lon, lat], [lon + 0.1, lat], [lon + 0.1, lat + 0.1], [lon, lat]]] });
  assert.ok(dansRayon(carre(-74.6, 45.6), OTTAWA, 150));
  assert.ok(!dansRayon(carre(-79.4, 43.7), OTTAWA, 150), 'Toronto exclu');
});

test('Ontario : code préfixé ON-, comté en guise de MRC, SQL avec province', () => {
  const p = proprietesOntario({ MUNID: '7015', MUNICIPAL_NAME_SHORTFORM_FR: 'BROCKVILLE', UPPER_TIER_MUNICIPALITY_FR: null });
  assert.deepEqual(p, { code: 'ON-7015', nom: 'Brockville', region: "Est de l'Ontario", province: 'ON' });
  const sqlTxt = genererSqlOntario([{ properties: p }], new Date('2026-10-22'));
  assert.match(sqlTxt, /\('ON-7015', 'Brockville', null, 'Est de l''Ontario', 'ON', /);
});
