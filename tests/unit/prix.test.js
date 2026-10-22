import { test } from 'node:test';
import assert from 'node:assert/strict';
import { modifierTypeTravail, creerDemande, soumettrePublique, lienDemande, verifierJeton, baseUrl } from '../../lib/modules/prix.js';
import { handler as prixPublic } from '../../netlify/functions/prix-public.mjs';

const ID = '33333333-3333-4333-8333-333333333333';
const J = 'a'.repeat(64);
function fauxRepo(rep = {}) {
  const appels = [];
  const r = (op) => async (...a) => { appels.push([op, ...a]); return rep[op] ?? { ok: true }; };
  return { appels, update: r('update'), rpc: r('rpc'), list: r('list') };
}

test('prix : édition d\'une ligne (titre, description, unité), rien d\'autre', async () => {
  const repo = fauxRepo();
  await modifierTypeTravail(repo, ID, { nom: '  Remplacement murale 1 tête  ', description: '', code: 'PIRATE', unite: 'forfait' });
  assert.deepEqual(repo.appels[0][3], { nom: 'Remplacement murale 1 tête', description: null, unite: 'forfait' });
  await assert.rejects(modifierTypeTravail(repo, ID, { unite: 'semaine' }), /Unité inconnue/);
  await assert.rejects(modifierTypeTravail(repo, ID, { nom: 'X' }), /trop court/);
});

test('prix : le lien porte le jeton dans le fragment (#), jamais dans l\'adresse du serveur', async () => {
  assert.equal(lienDemande('https://hvac.exemple/', J), `https://hvac.exemple/prix#${J}`);
  const repo = fauxRepo({ rpc: [{ id: ID, jeton: J, expire_le: '2026-11-21' }] });
  const d = await creerDemande(repo, { fournisseur_id: ID, types: [ID] }, 'https://hvac.exemple');
  assert.equal(d.lien, `https://hvac.exemple/prix#${J}`);
  await assert.rejects(creerDemande(repo, { fournisseur_id: ID, types: [] }, ''), /Coche au moins/);
  assert.equal(baseUrl({ headers: { host: 'a.netlify.app' } }, {}), 'https://a.netlify.app');
});

test('prix : soumission publique validée avant la base (prix, nom, signature, validité d\'un an)', async () => {
  const repo = fauxRepo();
  const base = { lignes: [{ id: ID, cout_cents: 125000 }], nom: 'Jean Tremblay', signature: 'data:image/png;base64,AAA', atteste: true };
  await soumettrePublique(repo, J, base);
  assert.equal(repo.appels[0][1], 'hvac_demande_prix_soumettre');
  await assert.rejects(soumettrePublique(repo, J, { ...base, lignes: [{ id: ID }] }), /Chaque ligne/);
  await assert.rejects(soumettrePublique(repo, J, { ...base, atteste: false }), /un an/);
  await assert.rejects(soumettrePublique(repo, J, { ...base, signature: 'javascript:alert(1)' }), /Signature/);
  await soumettrePublique(repo, J, { ...base, lignes: [{ id: ID, non_offert: true, cout_cents: 999 }] });
  assert.deepEqual(repo.appels.at(-1)[2].p_lignes[0], { id: ID, cout_cents: null, non_offert: true, note: null });
  assert.throws(() => verifierJeton('court'), /Lien invalide/);
});

test('prix : fonction publique sans session, jeton par en-tête', async () => {
  const appels = [];
  const adapter = { repo: (token) => ({ rpc: async (fn, a) => { appels.push([token, fn, a]); return { statut: 'envoyee' }; } }) };
  const r = await prixPublic({ httpMethod: 'GET', headers: { 'x-jeton': J } }, {}, { adapter });
  assert.equal(r.statusCode, 200);
  assert.deepEqual(appels[0], [null, 'hvac_demande_prix_lire', { p_jeton: J }], 'clé publique seulement, aucun jeton de session');
  const mauvais = await prixPublic({ httpMethod: 'GET', headers: {} }, {}, { adapter });
  assert.equal(mauvais.statusCode, 400);
  const methode = await prixPublic({ httpMethod: 'DELETE', headers: {} }, {}, { adapter });
  assert.equal(methode.statusCode, 405);
});

import { majMesPrix, confierTravaux, frequence, lireRegistre } from '../../lib/modules/prix.js';

test('portail : le sous-traitant envoie seulement des prix valides ; Belleflamme confie des travaux', async () => {
  const repo = { appels: [], rpc: async (...a) => { repo.appels.push(['rpc', ...a]); return { changes: 1 }; },
    upsert: async (...a) => { repo.appels.push(['upsert', ...a]); }, removeWhere: async (...a) => { repo.appels.push(['removeWhere', ...a]); } };
  await majMesPrix(repo, null, { prix: [{ type_travail_id: ID, cout_cents: 125000 }] });
  assert.deepEqual(repo.appels[0], ['rpc', 'hvac_maj_mes_prix', { p_prix: [{ type_travail_id: ID, cout_cents: 125000 }], p_fournisseur: null }]);
  await assert.rejects(majMesPrix(repo, null, { prix: [{ type_travail_id: ID, cout_cents: -5 }] }), /Prix invalide/);
  await assert.rejects(majMesPrix(repo, null, { prix: [] }), /Aucun prix/);
  await confierTravaux(repo, { fournisseur_id: ID, ajouter: [ID], retirer: [] });
  assert.deepEqual(repo.appels.at(-1), ['rpc', 'hvac_confier_travaux', { p_fournisseur: ID, p_ajouter: [ID], p_retirer: [] }]);
  await assert.rejects(confierTravaux(repo, { fournisseur_id: ID }), /Aucun travail/);
});

test('registre : alerte quand le sous-traitant modifie sa liste 3 fois ou plus en 30 jours', () => {
  const maintenant = new Date('2026-10-22T12:00:00Z');
  const v = (jours, st = true) => ({ par_sous_traitant: st, cree_le: new Date(maintenant.getTime() - jours * 86400000).toISOString() });
  assert.deepEqual(frequence([v(1), v(5)], 3, maintenant), { n30: 2, seuil: 3, alerte: false, jours: 30 });
  assert.equal(frequence([v(1), v(5), v(29)], 3, maintenant).alerte, true);
  assert.equal(frequence([v(1), v(5), v(31)], 3, maintenant).alerte, false, 'plus de 30 jours : ne compte pas');
  assert.equal(frequence([v(1), v(5), v(6, false)], 3, maintenant).alerte, false, 'versions faites par Belleflamme : ne comptent pas');
});

test('registre : lecture triée de la plus récente, seuil lu dans les paramètres', async () => {
  const appels = [];
  const repo = { list: async (t, o) => { appels.push([t, o]); return t === 'parametres' ? [{ valeur: 5 }] : []; } };
  const r = await lireRegistre(repo, ID);
  assert.equal(r.seuil, 5);
  assert.deepEqual(appels[0][1].ordre, { colonne: 'numero', asc: false });
  await assert.rejects(lireRegistre(repo, 'x'), /invalide/);
});
