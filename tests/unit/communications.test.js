import { test } from 'node:test';
import assert from 'node:assert/strict';
import { listerCommunications, ecouter, lancer } from '../../lib/modules/communications.js';
import { numeroE164, lienAction, lienCarte } from '../../public/js/bf-contact-liens.js';
import { handler as webhook } from '../../netlify/functions/communications-webhook.mjs';

const ID = '11111111-1111-4111-8111-111111111111';
const off = { mikeCommEnabled: false };
const on = { mikeCommEnabled: true };

test('liens de contact : numéro nord-américain, courriel, carte', () => {
  assert.equal(numeroE164('450 555-0110'), '+14505550110');
  assert.equal(numeroE164('1-450-555-0110'), '+14505550110');
  assert.equal(numeroE164('555-0110'), null);
  assert.equal(lienAction('appel', '(450) 555-0110'), 'tel:+14505550110');
  assert.equal(lienAction('texto', '4505550110'), 'sms:+14505550110');
  assert.equal(lienAction('courriel', 'julie@exemple.ca'), 'mailto:julie@exemple.ca');
  assert.equal(lienAction('courriel', 'pas un courriel'), null);
  assert.equal(lienCarte({ adresse: '12 rue des Érables', ville: 'Saint-Jérôme', code_postal: 'J7Z 0A0' }),
    'https://www.google.com/maps/search/?api=1&query=12%20rue%20des%20%C3%89rables%2C%20Saint-J%C3%A9r%C3%B4me%2C%20QC%2C%20J7Z%200A0');
  assert.equal(lienCarte({ adresse: 'x', ville: 'y', latitude: 45.78, longitude: -74.0 }), 'https://www.google.com/maps/search/?api=1&query=45.78%2C-74');
  assert.equal(lienCarte(null), null);
});

test('boutons : lien de l\'appareil tant que l\'app de Mike n\'est pas branchée ; 501 une fois activé sans contrat', () => {
  assert.deepEqual(lancer(off, { canal: 'appel', coordonnee: '450-555-0110', client_id: ID }), { mode: 'appareil', lien: 'tel:+14505550110' });
  assert.throws(() => lancer(off, { canal: 'appel', coordonnee: '123', client_id: ID }), /Numéro/);
  assert.throws(() => lancer(off, { canal: 'fax', coordonnee: '4505550110', client_id: ID }), /Canal/);
  assert.throws(() => lancer(off, { canal: 'appel', coordonnee: '4505550110' }), /requis/);
  assert.throws(() => lancer(on, { canal: 'appel', coordonnee: '4505550110', lead_id: ID }), (e) => e.status === 501);
});

test('historique et écoute : filtres validés, écoute toujours vérifiée par la base', async () => {
  const appels = [];
  const repo = { list: async (...a) => { appels.push(['list', ...a]); return []; }, rpc: async (...a) => { appels.push(['rpc', ...a]); return 'mike:ref'; } };
  await listerCommunications(repo, { client_id: ID, canal: 'appel' });
  assert.deepEqual(appels[0][2].filtre, { client_id: ID, canal: 'appel' });
  await assert.rejects(listerCommunications(repo, {}), /requis/);
  await assert.rejects(listerCommunications(repo, { lead_id: ID, canal: 'pigeon' }), /Canal/);
  const r = await ecouter(repo, off, ID);
  assert.equal(r.disponible, false);
  assert.deepEqual(appels.at(-1), ['rpc', 'hvac_ecouter_enregistrement', { p_communication: ID }]);
  await assert.rejects(ecouter(repo, on, ID), (e) => e.status === 501);
});

test('webhook des communications : 503 tant que désactivé', async () => {
  const avant = process.env.MIKE_COMM_ENABLED;
  delete process.env.MIKE_COMM_ENABLED;
  assert.equal((await webhook({ httpMethod: 'POST', body: '{}' })).statusCode, 503);
  assert.equal((await webhook({ httpMethod: 'GET' })).statusCode, 405);
  if (avant !== undefined) process.env.MIKE_COMM_ENABLED = avant;
});
