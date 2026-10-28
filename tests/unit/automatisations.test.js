import { test } from 'node:test';
import assert from 'node:assert/strict';
import { modifierAutomatisations, modifierAvis } from '../../lib/modules/automatisations.js';
import { changerEtape } from '../../lib/modules/macro.js';
import { handler as appelManque } from '../../netlify/functions/appel-manque-webhook.mjs';
import { signer } from '../../lib/signature.js';

const ID = '11111111-1111-4111-8111-111111111111';
const fauxRepo = () => { const appels = []; return { appels, update: async (...a) => { appels.push(['update', ...a]); return {}; }, rpc: async (...a) => { appels.push(['rpc', ...a]); return null; } }; };

test('règle : activer ou changer les étapes, étapes validées', async () => {
  const r = fauxRepo();
  await modifierAutomatisations(r, { action: 'regle', id: ID, actif: false });
  assert.deepEqual(r.appels[0], ['update', 'regles', ID, { actif: false }]);
  await modifierAutomatisations(r, { action: 'regle', id: ID, etapes: [{ type: 'sms', texte: 'Bonjour {prenom}' }] });
  await assert.rejects(modifierAutomatisations(r, { action: 'regle', id: ID, etapes: [{ type: 'teleporter' }] }), /inconnue/);
  await assert.rejects(modifierAutomatisations(r, { action: 'regle', id: ID, etapes: [{ type: 'sms', texte: 'x'.repeat(321) }] }), /trop long/);
  await assert.rejects(modifierAutomatisations(r, { action: 'regle', id: ID }), /Rien/);
});

test('heures, lien d\'avis, relance, tâches', async () => {
  const r = fauxRepo();
  await modifierAutomatisations(r, { action: 'heures', succursale_code: 'RO', heures: [{ jour: 1, ouvre: '08:30', ferme: '17:00' }] });
  assert.deepEqual(r.appels[0], ['rpc', 'hvac_heures', { p_succ: 'RO', p_heures: [{ jour: 1, ouvre: '08:30', ferme: '17:00' }] }]);
  await assert.rejects(modifierAutomatisations(r, { action: 'heures', succursale_code: 'RO', heures: [{ jour: 9, ouvre: '8', ferme: '17' }] }), /invalides/);
  await modifierAutomatisations(r, { action: 'relancer', id: ID });
  await modifierAvis(r, { action: 'tache_faite', id: ID });
  assert.deepEqual(r.appels.at(-1), ['rpc', 'hvac_tache_faite', { p_id: ID }]);
});

test('Macro : étape de subvention validée', async () => {
  const r = fauxRepo();
  await changerEtape(r, ID, { subvention_statut: 'deposee' });
  assert.deepEqual(r.appels[0], ['rpc', 'hvac_subvention_etape', { p_projet: ID, p_statut: 'deposee' }]);
  await assert.rejects(changerEtape(r, ID, { subvention_statut: 'perdue' }), /inconnue/);
});

test('webhook appel manqué : 503 désactivé, 401 non signé, 200 signé', async () => {
  const env = { ...process.env };
  const corps = JSON.stringify({ telephone: '450-555-0101', succursale_code: 'RO' });
  const appels = [];
  const systeme = { rpc: async (fn, a) => { appels.push([fn, a]); return { lead_id: ID }; } };
  try {
    process.env.TELEPHONIE_SYNC_ENABLED = 'false';
    assert.equal((await appelManque({ httpMethod: 'POST', body: corps, headers: {} }, {}, { systeme })).statusCode, 503);
    process.env.TELEPHONIE_SYNC_ENABLED = 'true'; process.env.TELEPHONIE_WEBHOOK_SECRET = 'secret-bidon';
    assert.equal((await appelManque({ httpMethod: 'POST', body: corps, headers: {} }, {}, { systeme })).statusCode, 401);
    const t = Math.floor(Date.now() / 1000);
    const r = await appelManque({ httpMethod: 'POST', body: corps, headers: { 'x-belleflamme-horodatage': String(t), 'x-belleflamme-signature': signer('secret-bidon', t, corps) } }, {}, { systeme });
    assert.equal(r.statusCode, 200);
    assert.deepEqual(appels[0], ['hvac_appel_manque', { p: { telephone: '450-555-0101', succursale_code: 'RO' } }]);
  } finally { process.env = env; }
});
