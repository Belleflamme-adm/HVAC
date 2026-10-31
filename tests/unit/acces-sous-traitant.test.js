// Accès des sous-traitants (ADR-095) : connexion par code, envoi et coupure de l'accès
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { handler as sessionCode } from '../../netlify/functions/session-code.mjs';
import { gererAcces } from '../../lib/modules/sous-traitants.js';
import { DataError } from '../../lib/data/erreurs.js';

const ID = '11111111-1111-4111-8111-111111111111';
const ST = { id: 'e-st', monday_item_id: null, email: 'martin@clim.ca', prenom: 'Martin', nom: 'Lavoie', role: 'Sous-traitant', succursale_code: 'HO', fournisseur_id: ID };

function fauxAdapter({ employe = ST, inconnu = false, limite = false } = {}) {
  const journal = [];
  return {
    journal,
    auth: {
      async envoyerCode(email, o) {
        journal.push(['envoyerCode', email, o.creer]);
        if (limite) throw new DataError('trop_de_demandes', 'Trop de demandes', 429);
        if (inconnu) throw new DataError('code_non_envoye', 'Code non envoyé', 400);
      },
      async verifierCode(email, code) {
        journal.push(['verifierCode', email, code]);
        if (code !== '123456') throw new DataError('code_invalide', 'Code invalide ou expiré', 401);
        return { accessToken: 'acc', refreshToken: 'ref', expiresIn: 3600 };
      },
      async signOut(t) { journal.push(['signOut', t]); },
    },
    async session() { return { employe }; },
  };
}
const post = (b) => ({ httpMethod: 'POST', headers: {}, queryStringParameters: {}, body: JSON.stringify(b) });
const corps = (r) => JSON.parse(r.body);

test('session-code : demande de code, sans création de compte ; même réponse si le courriel est inconnu', async () => {
  for (const inconnu of [false, true]) {
    const a = fauxAdapter({ inconnu });
    const r = await sessionCode(post({ email: ' Martin@Clim.ca ' }), {}, { adapter: a });
    assert.equal(r.statusCode, 200);
    assert.deepEqual(corps(r), { envoye: true });
    assert.deepEqual(a.journal[0], ['envoyerCode', 'martin@clim.ca', false]);
  }
  assert.equal((await sessionCode(post({ email: 'x@y.ca' }), {}, { adapter: fauxAdapter({ limite: true }) })).statusCode, 429);
  assert.equal((await sessionCode(post({ email: 'pas-un-courriel' }), {}, { adapter: fauxAdapter() })).statusCode, 400);
});

test('session-code : bon code -> contrat de Mike + cookies ; mauvais code -> 401', async () => {
  const r = await sessionCode(post({ email: 'martin@clim.ca', code: '123 456' }), {}, { adapter: fauxAdapter() });
  assert.equal(r.statusCode, 200);
  assert.equal(corps(r).token, 'acc');
  assert.equal(corps(r).user.sousTraitantId, ID);
  assert.ok((r.multiValueHeaders?.['Set-Cookie'] || []).some((c) => c.startsWith('bf_session=acc') && c.includes('HttpOnly')));
  assert.equal((await sessionCode(post({ email: 'martin@clim.ca', code: '000000' }), {}, { adapter: fauxAdapter() })).statusCode, 401);
  assert.equal((await sessionCode(post({ email: 'martin@clim.ca', code: 'abc' }), {}, { adapter: fauxAdapter() })).statusCode, 400);
});

test('session-code : accès coupé (aucun employé actif) -> 403 et session révoquée', async () => {
  const a = fauxAdapter({ employe: null });
  const r = await sessionCode(post({ email: 'martin@clim.ca', code: '123456' }), {}, { adapter: a });
  assert.equal(r.statusCode, 403);
  assert.ok(a.journal.some(([op]) => op === 'signOut'));
});

test('accès : envoyer = vérification en base puis code avec création du compte ; couper et rétablir passent par la base', async () => {
  const appels = [];
  const repo = { rpc: async (fn, a) => { appels.push([fn, a]); return fn === 'hvac_st_acces_envoyer' ? 'martin@clim.ca' : { actif: true }; } };
  const auth = fauxAdapter().auth;
  const journal = [];
  auth.envoyerCode = async (email, o) => journal.push([email, o.creer]);
  await gererAcces(repo, auth, ID, 'envoyer');
  assert.deepEqual(appels[0], ['hvac_st_acces_envoyer', { p_fournisseur: ID }]);
  assert.deepEqual(journal, [['martin@clim.ca', true]]);
  await gererAcces(repo, auth, ID, 'couper');
  assert.equal(appels.at(-2)[0], 'hvac_st_acces_couper');
  await gererAcces(repo, auth, ID, 'retablir');
  assert.equal(appels.at(-2)[0], 'hvac_st_acces_retablir');
  await assert.rejects(gererAcces(repo, auth, ID, 'effacer'), /Action inconnue/);
  await assert.rejects(gererAcces(repo, auth, 'pas-un-id', 'couper'), /invalide/);
});
