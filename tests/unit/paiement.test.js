import { test } from 'node:test';
import assert from 'node:assert/strict';
import { normaliserDepot, normaliserFacturePayee } from '../../lib/modules/paiement.js';
import { signer } from '../../lib/signature.js';
import { handler } from '../../netlify/functions/paiement-webhook.mjs';

test('dépôt : forme validée, autres paiements ignorés', () => {
  assert.deepEqual(normaliserDepot({ type: 'depot', devis_numero_mike: '#121401', paiement_ref: 'PAY-1', montant_cents: 336000 }).depot,
    { devis_numero_mike: '121401', paiement_ref: 'PAY-1', montant_cents: 336000 });
  assert.match(normaliserDepot({ type: 'solde', devis_numero_mike: '121401', paiement_ref: 'P' }).ignore, /non traité/);
  assert.match(normaliserDepot({ type: 'depot', devis_numero_mike: 'abc', paiement_ref: 'P' }).erreur, /4 à 8/);
  assert.match(normaliserDepot({ type: 'depot', devis_numero_mike: '121401' }).erreur, /paiement_ref/);
  assert.match(normaliserDepot({ type: 'depot', devis_numero_mike: '121401', paiement_ref: 'P', montant_cents: 12.5 }).erreur, /montant/);
});

test('webhook paiement : 503 désactivé, 401 non signé, 200 signé', async () => {
  const env = { ...process.env };
  const corps = JSON.stringify({ type: 'depot', devis_numero_mike: '121401', paiement_ref: 'PAY-1' });
  const appels = [];
  const systeme = { rpc: async (fn, a) => { appels.push([fn, a]); return { change: true }; } };
  try {
    process.env.PAIEMENT_SYNC_ENABLED = 'false';
    assert.equal((await handler({ httpMethod: 'POST', body: corps, headers: {} }, {}, { systeme })).statusCode, 503);
    process.env.PAIEMENT_SYNC_ENABLED = 'true'; process.env.PAIEMENT_WEBHOOK_SECRET = 'secret-bidon';
    assert.equal((await handler({ httpMethod: 'POST', body: corps, headers: {} }, {}, { systeme })).statusCode, 401);
    const t = Math.floor(Date.now() / 1000);
    const r = await handler({ httpMethod: 'POST', body: corps, headers: { 'x-belleflamme-horodatage': String(t), 'x-belleflamme-signature': signer('secret-bidon', t, corps) } }, {}, { systeme });
    assert.equal(r.statusCode, 200);
    assert.deepEqual(appels[0], ['hvac_depot_recu', { p: { devis_numero_mike: '121401', paiement_ref: 'PAY-1' } }]);
  } finally { process.env = env; }
});

test('facture payée : forme validée', () => {
  assert.deepEqual(normaliserFacturePayee({ devis_numero_mike: '121601', paiement_ref: 'PAY-F1', facture_numero_mike: 'F-42' }).facture,
    { devis_numero_mike: '121601', paiement_ref: 'PAY-F1', facture_numero_mike: 'F-42' });
  assert.match(normaliserFacturePayee({ devis_numero_mike: '121601' }).erreur, /paiement_ref/);
});
