// Même nom que le test de Mike (tests/project-code-shape.test.js) pour faciliter la greffe.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { bfProjectCodeOf, bfParseProjectCode, estCodeProjet } from '../../public/js/bf-project-code.js';

test('préfixe : succursale + lettre de division', () => {
  assert.equal(bfProjectCodeOf({ succursale: 'RO', division: 'Ventilation' }), 'ROV');
  assert.equal(bfProjectCodeOf({ succursale: 'GA', division: 'Climatisation' }), 'GAV');
  assert.equal(bfProjectCodeOf({ succursale_code: 'ST', division: 'V' }), 'STV');
  assert.equal(bfProjectCodeOf({ succursale: 'dr', division: 'ventilation' }), 'DRV');
  assert.equal(bfProjectCodeOf({ succursale: 'HO', division: 'Foyer-Gaz' }), 'HOF');
});

test('Saint-Jérôme utilise HO (ADR-003)', () => {
  assert.equal(bfProjectCodeOf({ succursale: 'HO', division: 'Ventilation' }), 'HOV');
});

test('entrées invalides : chaîne vide', () => {
  assert.equal(bfProjectCodeOf(null), '');
  assert.equal(bfProjectCodeOf({ succursale: 'SJ', division: 'Ventilation' }), '');
  assert.equal(bfProjectCodeOf({ succursale: 'RO', division: 'Plomberie' }), '');
});

test('un code attribué par la base est retourné tel quel', () => {
  assert.equal(bfProjectCodeOf({ code_projet: 'rov-001-26' }), 'ROV-001-26');
});

test('analyse d\'un code XXX-XXX-XXX', () => {
  assert.deepEqual(bfParseProjectCode('ROV-001-26'),
    { succursale: 'RO', division: 'V', segment2: '001', segment3: '26', prefixe: 'ROV' });
  assert.equal(estCodeProjet('ROV-123-456'), true);
  assert.equal(estCodeProjet('XXV-001-26'), false);
  assert.equal(estCodeProjet('ROV001'), false);
});
