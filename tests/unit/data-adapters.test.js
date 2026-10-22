import { test } from 'node:test';
import assert from 'node:assert/strict';
import { getAdapter } from '../../lib/data/index.js';
import { creerAdapterSupabase } from '../../lib/data/supabase.js';
import { config, bool } from '../../lib/config.js';

test('adapter par défaut : supabase', () => {
  assert.equal(getAdapter({}).nom, 'supabase');
});

test('adapter inconnu refusé', () => {
  assert.throws(() => getAdapter({ DATA_ADAPTER: 'excel' }), /inconnu/);
});

test('Monday et Friday désactivés par défaut : 503', async () => {
  for (const nom of ['monday', 'friday']) {
    const a = getAdapter({ DATA_ADAPTER: nom });
    await assert.rejects(async () => a.session('x'), (e) => e.status === 503 && e.code === 'adapter_desactive');
  }
});

test('Monday activé mais non implémenté : 501, jamais de faux résultat', async () => {
  const a = getAdapter({ DATA_ADAPTER: 'monday', MONDAY_ENABLED: 'true' });
  await assert.rejects(async () => a.repo('x').list('clients'), (e) => e.status === 501);
});

test('Supabase sans configuration : erreur claire, aucune requête', async () => {
  const a = getAdapter({});
  await assert.rejects(() => a.session('x'), (e) => e.code === 'config_manquante' && e.status === 503);
});

test('Supabase utilise la clé publique et le JWT de l\'utilisateur, jamais service_role', async () => {
  const appels = [];
  const faux = (url, cle, opts) => {
    appels.push({ url, cle, opts });
    return { rpc: async () => ({ data: { id: 'e1' }, error: null }) };
  };
  const cfg = config({ SUPABASE_URL: 'https://x.supabase.co', SUPABASE_ANON_KEY: 'anon', SUPABASE_SERVICE_ROLE_KEY: 'secret' });
  const a = creerAdapterSupabase(cfg, { createClientImpl: faux });
  const s = await a.session('jwt-utilisateur');
  assert.deepEqual(s, { employe: { id: 'e1' } });
  assert.equal(appels[0].cle, 'anon');
  assert.equal(appels[0].opts.global.headers.Authorization, 'Bearer jwt-utilisateur');
  assert.equal(appels[0].opts.auth.persistSession, false);
});

test('drapeaux booléens', () => {
  assert.equal(bool('true'), true);
  assert.equal(bool('OUI'), true);
  assert.equal(bool('false'), false);
  assert.equal(bool(undefined), false);
  assert.equal(config({}).mondayEnabled, false);
  assert.equal(config({}).fridaySyncEnabled, false);
});
