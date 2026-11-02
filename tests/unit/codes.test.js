import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { empreinteCode, verifierCode } from '../../public/js/bf-code.js';
import { verifierAcces } from '../../lib/modules/codes.js';

// Code de test seulement (jamais le vrai code)
const CODE = '0000';

test('empreinte : PBKDF2 salé, vérification à temps constant, format validé', async () => {
  const e1 = await empreinteCode(CODE, { iterations: 1000 });
  const e2 = await empreinteCode(CODE, { iterations: 1000 });
  assert.match(e1, /^pbkdf2\$1000\$[A-Za-z0-9+/=]+\$[A-Za-z0-9+/=]+$/);
  assert.notEqual(e1, e2, 'sel aléatoire : deux empreintes différentes pour le même code');
  assert.equal(await verifierCode(CODE, e1), true);
  assert.equal(await verifierCode('0001', e1), false);
  assert.equal(await verifierCode('abc', e1), false);
  assert.equal(await verifierCode(CODE, 'pas-une-empreinte'), false);
});

test('accès : rôle vérifié avant le code, 503 si non configuré, 403 si incorrect', async () => {
  const empreinte = await empreinteCode(CODE, { iterations: 1000 });
  const session = (role) => ({ session: async () => ({ employe: { role } }) });
  const cfg = { codesAcces: { vendeurs: empreinte } };
  assert.deepEqual(await verifierAcces(session('Admin tout'), 't', cfg, { zone: 'vendeurs', code: CODE }, { delaiEchec: 0 }), { ok: true });
  await assert.rejects(verifierAcces(session('Vendeur'), 't', cfg, { zone: 'vendeurs', code: CODE }, { delaiEchec: 0 }), (e) => e.status === 403);
  await assert.rejects(verifierAcces(session('Comptabilité'), 't', cfg, { zone: 'vendeurs', code: '1234' }, { delaiEchec: 0 }), (e) => e.code === 'code_incorrect');
  await assert.rejects(verifierAcces(session('Direction'), 't', { codesAcces: {} }, { zone: 'vendeurs', code: CODE }, { delaiEchec: 0 }), (e) => e.status === 503);
  await assert.rejects(verifierAcces(session('Direction'), 't', cfg, { zone: 'inconnue', code: CODE }, { delaiEchec: 0 }), /Zone/);
});

test('aucun code d\'accès en clair dans le repo', () => {
  const suivis = execFileSync('git', ['ls-files'], { encoding: 'utf8' }).split('\n').filter((f) => /\.(js|mjs|html|md|sql|json|toml|example)$/.test(f));
  for (const f of suivis) {
    const src = readFileSync(f, 'utf8');
    assert.doesNotMatch(src, /DEMO_CODE_VENDEURS\s*=\s*\d/, `${f} : code de démo en clair`);
    assert.doesNotMatch(src, /CODE_ACCES_VENDEURS\s*=\s*\d{4}/, `${f} : code d'accès en clair au lieu d'une empreinte`);
  }
});
