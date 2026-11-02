import { test } from 'node:test';
import assert from 'node:assert/strict';
import { signer, verifierSignature, normaliserVisite } from '../../lib/modules/pointage.js';
import { handler } from '../../netlify/functions/pointage-webhook.mjs';

const SECRET = 'secret-de-test-bidon';
const ts = () => Math.floor(Date.now() / 1000);

test('signature : bonne, falsifiée, expirée', () => {
  const t = ts(); const corps = '{"pointage_ref":"PI-1"}';
  assert.equal(verifierSignature({ secret: SECRET, horodatage: String(t), signature: signer(SECRET, t, corps), corpsBrut: corps }), null);
  assert.equal(verifierSignature({ secret: SECRET, horodatage: String(t), signature: signer(SECRET, t, corps), corpsBrut: corps + ' ' }), 'signature invalide');
  assert.equal(verifierSignature({ secret: SECRET, horodatage: String(t - 900), signature: signer(SECRET, t - 900, corps), corpsBrut: corps }), 'horodatage expiré');
  assert.equal(verifierSignature({ secret: '', horodatage: String(t), signature: 'x', corpsBrut: corps }), 'secret non configuré');
});

test('visite : date normalisée, annulation, champs requis', () => {
  assert.deepEqual(normaliserVisite({ pointage_ref: 'PI-1', visite_le: '2026-11-03T09:00:00-05:00', lead_ref: '1e000000-0000-0000-0000-0000000000e1' }).visite,
    { pointage_ref: 'PI-1', lead_ref: '1e000000-0000-0000-0000-0000000000e1', visite_le: '2026-11-03T14:00:00.000Z' });
  assert.deepEqual(normaliserVisite({ pointage_ref: 'PI-1', annulee: true }).visite, { pointage_ref: 'PI-1', annulee: true });
  assert.match(normaliserVisite({ visite_le: '2026-11-03' }).erreur, /pointage_ref/);
  assert.match(normaliserVisite({ pointage_ref: 'PI-1' }).erreur, /visite_le/);
  assert.match(normaliserVisite({ pointage_ref: 'PI-1', visite_le: '2026-11-03', lead_ref: 'abc' }).erreur, /lead_ref/);
});

test('webhook : 503 si désactivé, 401 sans signature, 200 signé', async () => {
  const env = { ...process.env };
  const corps = JSON.stringify({ pointage_ref: 'PI-9', visite_le: '2026-11-03T14:00:00Z' });
  const appels = [];
  const systeme = { rpc: async (fn, a) => { appels.push([fn, a]); return { lead_id: 'x', change: true }; } };
  try {
    process.env.POINTAGE_SYNC_ENABLED = 'false';
    assert.equal((await handler({ httpMethod: 'POST', body: corps, headers: {} }, {}, { systeme })).statusCode, 503);
    process.env.POINTAGE_SYNC_ENABLED = 'true'; process.env.POINTAGE_WEBHOOK_SECRET = SECRET;
    assert.equal((await handler({ httpMethod: 'POST', body: corps, headers: {} }, {}, { systeme })).statusCode, 401);
    const t = ts();
    const r = await handler({ httpMethod: 'POST', body: corps, headers: { 'X-Belleflamme-Horodatage': String(t), 'X-Belleflamme-Signature': signer(SECRET, t, corps) } }, {}, { systeme });
    assert.equal(r.statusCode, 200);
    assert.deepEqual(appels[0], ['hvac_visite_pointage', { p: { pointage_ref: 'PI-9', visite_le: '2026-11-03T14:00:00.000Z' } }]);
  } finally { process.env = env; }
});
