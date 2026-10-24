import { test } from 'node:test';
import assert from 'node:assert/strict';
import { listerProjets, changerEtape, recevoirSigne, ETAPES } from '../../lib/modules/macro.js';

const ID = '11111111-1111-4111-8111-111111111111';
const fauxRepo = () => { const appels = []; return { appels, list: async (...a) => { appels.push(['list', ...a]); return []; },
  update: async (...a) => { appels.push(['update', ...a]); return {}; }, rpc: async (...a) => { appels.push(['rpc', ...a]); return ID; } }; };

test('Macro : étapes ouvertes par défaut, fermés sur demande', async () => {
  const r = fauxRepo();
  await listerProjets(r, {});
  assert.deepEqual(r.appels[0][2].filtre.statut.val, ETAPES);
  await listerProjets(r, { fermes: '1', succursale: 'RO' });
  assert.ok(r.appels[1][2].filtre.statut.val.includes('annule'));
  assert.equal(r.appels[1][2].filtre.succursale_code, 'RO');
});

test('Macro : changement d\'étape validé', async () => {
  const r = fauxRepo();
  await changerEtape(r, ID, { statut: 'planifie' });
  assert.deepEqual(r.appels[0], ['update', 'projets', ID, { statut: 'planifie' }]);
  await assert.rejects(changerEtape(r, ID, { statut: 'livre' }), /Étape/);
});

test('soumission signée : numéro, montant et lien validés, une seule fonction de la base', async () => {
  const r = fauxRepo();
  assert.deepEqual(await recevoirSigne(r, { lead_id: ID, devis_numero_mike: '#120815', montant_avant_taxes_cents: 985000 }), { projet_id: ID });
  assert.deepEqual(r.appels[0], ['rpc', 'hvac_projet_signe', { p: { devis_numero_mike: '120815', lead_id: ID, montant_avant_taxes_cents: 985000 } }]);
  await assert.rejects(recevoirSigne(r, { lead_id: ID, devis_numero_mike: 'abc' }), /Numéro/);
  await assert.rejects(recevoirSigne(r, { devis_numero_mike: '120815' }), /Lead ou client/);
  await assert.rejects(recevoirSigne(r, { lead_id: ID, devis_numero_mike: '120815', montant_avant_taxes_cents: -5 }), /Montant/);
});
