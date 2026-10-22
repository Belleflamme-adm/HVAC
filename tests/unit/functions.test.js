import { test, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import { handler as login } from '../../netlify/functions/session-login.mjs';
import { handler as me } from '../../netlify/functions/session-me.mjs';
import { handler as logout } from '../../netlify/functions/session-logout.mjs';
import { handler as mondayWebhook } from '../../netlify/functions/monday-webhook-sync.mjs';
import { handler as fridaySync } from '../../netlify/functions/friday-sync.mjs';
import { handler as health } from '../../netlify/functions/health.mjs';
import { DataError } from '../../lib/data/erreurs.js';

const EMPLOYE = { id: 'e1', monday_item_id: 123, email: 'simon@test', prenom: 'Simon', nom: 'Cardinal',
                  role: 'Admin tout', succursale_code: 'HO' };

function fauxAdapter({ employe = EMPLOYE, sessionExpiree = false } = {}) {
  const journal = [];
  return {
    journal,
    auth: {
      async signIn(email, mdp) {
        journal.push(['signIn', email]);
        if (mdp !== 'bon') throw new DataError('identifiants', 'Courriel ou mot de passe invalide', 401);
        return { accessToken: 'acc', refreshToken: 'ref', expiresIn: 3600 };
      },
      async refresh(rt) { journal.push(['refresh', rt]); return { accessToken: 'acc2', refreshToken: 'ref2', expiresIn: 3600 }; },
      async signOut(t) { journal.push(['signOut', t]); },
    },
    async session(token) {
      if (sessionExpiree && token === 'vieux') throw new DataError('session_expiree', 'Session expirée', 401);
      return { employe };
    },
    repo() {
      return { async rpc(fn, args) { journal.push([fn, args]); return { ...EMPLOYE, id: args.p_employe, prenom: 'Annie', nom: 'Lavoie', role: 'Vendeur' }; } };
    },
  };
}

const ev = (o = {}) => ({ httpMethod: 'GET', headers: {}, queryStringParameters: {}, ...o });
const corps = (r) => JSON.parse(r.body);
const cookies = (r) => r.multiValueHeaders?.['Set-Cookie'] || [];

beforeEach(() => { delete process.env.MONDAY_ENABLED; delete process.env.FRIDAY_SYNC_ENABLED; });

test('session-login : contrat de Mike + cookies HttpOnly', async () => {
  const r = await login(ev({ httpMethod: 'POST', body: JSON.stringify({ email: 'Simon@Test ', password: 'bon' }) }), {}, { adapter: fauxAdapter() });
  assert.equal(r.statusCode, 200);
  const b = corps(r);
  assert.equal(b.token, 'acc');
  assert.deepEqual(Object.keys(b.user).sort(), ['email', 'id', 'itemId', 'masterImpersonation', 'name', 'peutApprouverRabais', 'role', 'succursale'].sort());
  assert.equal(b.user.name, 'Simon Cardinal');
  assert.equal(b.user.itemId, 123);
  assert.equal(b.user.masterImpersonation, null);
  const c = cookies(r);
  assert.ok(c.some((x) => x.startsWith('bf_session=acc') && x.includes('HttpOnly') && x.includes('Secure') && x.includes('SameSite=Lax')));
  assert.ok(c.some((x) => x.startsWith('bf_refresh=ref') && x.includes('Path=/.netlify/functions')));
  assert.equal(r.headers['Cache-Control'], 'no-store');
});

test('session-login : mauvais mot de passe -> 401, champs manquants -> 400, GET -> 405', async () => {
  const a = fauxAdapter();
  assert.equal((await login(ev({ httpMethod: 'POST', body: '{"email":"a@b","password":"mauvais"}' }), {}, { adapter: a })).statusCode, 401);
  assert.equal((await login(ev({ httpMethod: 'POST', body: '{}' }), {}, { adapter: a })).statusCode, 400);
  assert.equal((await login(ev({ httpMethod: 'POST', body: 'pas du json' }), {}, { adapter: a })).statusCode, 400);
  assert.equal((await login(ev(), {}, { adapter: a })).statusCode, 405);
});

test('session-login : compte sans fiche employé -> 403 et session révoquée', async () => {
  const a = fauxAdapter({ employe: null });
  const r = await login(ev({ httpMethod: 'POST', body: '{"email":"x@y","password":"bon"}' }), {}, { adapter: a });
  assert.equal(r.statusCode, 403);
  assert.ok(a.journal.some(([op]) => op === 'signOut'));
});

test('session-me : sans cookie -> 401', async () => {
  assert.equal((await me(ev(), {}, { adapter: fauxAdapter() })).statusCode, 401);
});

test('session-me : cookie valide -> user', async () => {
  const r = await me(ev({ headers: { cookie: 'bf_session=acc' } }), {}, { adapter: fauxAdapter() });
  assert.equal(r.statusCode, 200);
  assert.equal(corps(r).user.role, 'Admin tout');
});

test('session-me : jeton expiré -> refresh et nouveaux cookies', async () => {
  const a = fauxAdapter({ sessionExpiree: true });
  const r = await me(ev({ headers: { cookie: 'bf_session=vieux; bf_refresh=ref' } }), {}, { adapter: a });
  assert.equal(r.statusCode, 200);
  assert.equal(corps(r).token, 'acc2');
  assert.ok(cookies(r).some((x) => x.startsWith('bf_session=acc2')));
});

test('session-me : impersonation -> masterImpersonation renseigné', async () => {
  const a = fauxAdapter();
  const r = await me(ev({ headers: { cookie: 'bf_session=acc' }, queryStringParameters: { impersonate: 'e3' } }), {}, { adapter: a });
  const u = corps(r).user;
  assert.equal(u.id, 'e3');
  assert.deepEqual(u.masterImpersonation, { id: 'e1', name: 'Simon Cardinal' });
  assert.ok(a.journal.some(([fn]) => fn === 'hvac_impersonation'));
});

test('session-logout : efface les deux cookies', async () => {
  const a = fauxAdapter();
  const r = await logout(ev({ httpMethod: 'POST', headers: { cookie: 'bf_session=acc' } }), {}, { adapter: a });
  assert.equal(r.statusCode, 200);
  assert.ok(cookies(r).every((x) => x.includes('Max-Age=0')));
  assert.equal(cookies(r).length, 2);
});

test('monday-webhook-sync : 503 tant que MONDAY_ENABLED=false', async () => {
  const r = await mondayWebhook(ev({ httpMethod: 'POST', body: '{"challenge":"abc"}' }));
  assert.equal(r.statusCode, 503);
});

test('monday-webhook-sync activé : renvoie le challenge, sinon 501', async () => {
  process.env.MONDAY_ENABLED = 'true';
  assert.deepEqual(corps(await mondayWebhook(ev({ httpMethod: 'POST', body: '{"challenge":"abc"}' }))), { challenge: 'abc' });
  assert.equal((await mondayWebhook(ev({ httpMethod: 'POST', body: '{"event":{}}' }))).statusCode, 501);
});

test('friday-sync : 503 tant que FRIDAY_SYNC_ENABLED=false', async () => {
  assert.equal((await fridaySync(ev({ httpMethod: 'POST' }))).statusCode, 503);
});

test('health : aucun secret exposé', async () => {
  process.env.SUPABASE_ANON_KEY = 'cle-test';
  const r = await health();
  delete process.env.SUPABASE_ANON_KEY;
  assert.equal(r.statusCode, 200);
  assert.ok(!r.body.includes('cle-test'));
});
