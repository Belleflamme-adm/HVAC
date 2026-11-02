// Même nom que le test de Mike (tests/project-code-shape.test.js) pour faciliter la greffe.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { bfProjectCodeOf, bfParseProjectCode, estCodeProjet, code3 } from '../../public/js/bf-project-code.js';

test('code complet : [SUCC][DIV]-[PRÉ]-[NOM]-[NNN]', () => {
  assert.equal(bfProjectCodeOf({ succursale: 'ST', division: 'Ventilation', prenom: 'Jean', nom: 'Tremblay', sequence: 1 }), 'STV-JEA-TRE-001');
  assert.equal(bfProjectCodeOf({ succursale: 'GA', division: 'Climatisation', prenom: 'Émilie', nom: 'Côté', sequence: 12 }), 'GAV-EMI-COT-012');
  assert.equal(bfProjectCodeOf({ succursale: 'DR', division: 'Foyer', prenom: 'Pierre-Luc', nom: 'Lévesque', sequence: 1 }), 'DRF-PIE-LEV-001');
});

test('préfixe sans numéro (le numéro vient de la base)', () => {
  assert.equal(bfProjectCodeOf({ succursale: 'RO', division: 'Ventilation', prenom: 'Julie', nom: 'Tremblay' }), 'ROV-JUL-TRE');
  assert.equal(bfProjectCodeOf({ succursale: 'RO', division: 'Ventilation' }), 'ROV');
  assert.equal(bfProjectCodeOf({ succursale: 'HO', division: 'Ventilation' }), 'HOV');
});

test('mêmes règles de lettres que la base (app.code3)', () => {
  assert.equal(code3('Pierre-Luc'), 'PIE');
  assert.equal(code3('Émilie'), 'EMI');
  assert.equal(code3("O'Brien"), 'OBR');
  assert.equal(code3('Li'), 'LIX');
  assert.equal(code3('Œuvre'), 'OEU');
});

test('entreprise sans prénom : le nom de l\'entreprise remplace le prénom', () => {
  assert.equal(bfProjectCodeOf({ succursale: 'ST', division: 'V', entreprise: 'Constructions Éco', nom: 'Gagnon', sequence: 1 }), 'STV-CON-GAG-001');
});

test('entrées invalides : chaîne vide', () => {
  assert.equal(bfProjectCodeOf(null), '');
  assert.equal(bfProjectCodeOf({ succursale: 'SJ', division: 'Ventilation' }), '');
  assert.equal(bfProjectCodeOf({ succursale: 'RO', division: 'Plomberie' }), '');
});

test('un code attribué par la base est retourné tel quel', () => {
  assert.equal(bfProjectCodeOf({ code_projet: 'stv-jea-tre-001' }), 'STV-JEA-TRE-001');
});

test('extension d\'un devis renouvelé : -E01', () => {
  assert.equal(bfProjectCodeOf({ succursale: 'ST', division: 'V', prenom: 'Jean', nom: 'Tremblay', sequence: 1, extension: 1 }), 'STV-JEA-TRE-001-E01');
  const p = bfParseProjectCode('STV-JEA-TRE-001-E02');
  assert.equal(p.extension, 2);
  assert.equal(p.origine, 'STV-JEA-TRE-001');
  assert.equal(estCodeProjet('STV-JEA-TRE-001-E1'), false);
});

test('analyse d\'un code', () => {
  assert.deepEqual(bfParseProjectCode('STV-JEA-TRE-002'),
    { succursale: 'ST', division: 'V', prenom: 'JEA', nom: 'TRE', sequence: 2, prefixe: 'STV', extension: null, origine: 'STV-JEA-TRE-002' });
  assert.equal(estCodeProjet('DRF-NOR-DUB-001'), true);
  assert.equal(estCodeProjet('XXV-JEA-TRE-001'), false);
  assert.equal(estCodeProjet('ROV-001-26'), false);
});
