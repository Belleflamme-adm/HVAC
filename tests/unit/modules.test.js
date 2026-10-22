import { test } from 'node:test';
import assert from 'node:assert/strict';
import { creerClient, modifierClient, listerClients } from '../../lib/modules/clients.js';
import {
  ajouterLigne, changerStatut, creerDevis, demanderApprobation, deciderApprobation, chercherCatalogue, listerDevis, modifierLigne,
} from '../../lib/modules/devis.js';
import { avecSession, choisir } from '../../lib/handler.js';

const ID = '11111111-1111-4111-8111-111111111111';
const ID2 = '22222222-2222-4222-8222-222222222222';

function fauxRepo(donnees = {}) {
  const appels = [];
  return {
    appels,
    async list(table, opts) { appels.push(['list', table, opts]); return donnees[`list:${table}`] || []; },
    async get(table, id) { appels.push(['get', table, id]); return donnees[`get:${table}`] ?? null; },
    async insert(table, ligne) { appels.push(['insert', table, ligne]); return { id: ID2, ...ligne }; },
    async update(table, id, patch) { appels.push(['update', table, id, patch]); return { id, ...patch }; },
    async remove(table, id) { appels.push(['remove', table, id]); return []; },
    async rpc(fn, args) { appels.push(['rpc', fn, args]); return ID2; },
  };
}

test('choisir : champs permis seulement, requis vérifiés', () => {
  assert.deepEqual(choisir({ a: 1, b: 2, pirate: 3 }, ['a', 'b']), { a: 1, b: 2 });
  assert.throws(() => choisir({ a: '' }, ['a'], ['a']), /Champ requis : a/);
});

test('client : nom et succursale requis, champs inconnus ignorés', async () => {
  const repo = fauxRepo();
  await assert.rejects(() => creerClient(repo, { nom: 'X' }), /succursale_code/);
  await creerClient(repo, { nom: 'Roy', succursale_code: 'RO', id: 'pirate', created_by: 'pirate' });
  const [, , ligne] = repo.appels.find(([op]) => op === 'insert');
  assert.equal(ligne.id, undefined);
  assert.equal(ligne.created_by, undefined);
});

test('client : numéros Hydro-Québec refusés sans consentement (Loi 25)', async () => {
  const repo = fauxRepo();
  await assert.rejects(() => creerClient(repo, { nom: 'Roy', succursale_code: 'RO', hq_numero_client: '123456789' }), /Consentement/);
  const c = await creerClient(repo, { nom: 'Roy', succursale_code: 'RO', hq_numero_client: '123456789', consentement_hq: true });
  assert.ok(c.consentement_hq_le);
});

test('client : lieu créé avec le client si une adresse est fournie', async () => {
  const repo = fauxRepo();
  await creerClient(repo, { nom: 'Roy', succursale_code: 'RO', site: { adresse: '1 rue A', ville: 'Rosemère' } });
  assert.ok(repo.appels.some(([op, t, l]) => op === 'insert' && t === 'sites' && l.client_id === ID2));
});

test('client : la succursale ne se change pas par modification', async () => {
  const repo = fauxRepo();
  await assert.rejects(() => modifierClient(repo, ID, { succursale_code: 'GA' }), /Aucun champ/);
});

test('recherche de clients : recherche multi-colonnes', async () => {
  const repo = fauxRepo();
  await listerClients(repo, { q: 'trem' });
  const [, , opts] = repo.appels[0];
  assert.deepEqual(opts.recherche.colonnes, ['nom', 'prenom', 'entreprise', 'courriel', 'telephone']);
});

test('devis : vendeur = employé connecté, succursale = celle du client', async () => {
  const repo = fauxRepo({ 'get:clients': { id: ID, succursale_code: 'GA' } });
  const data = { session: async () => ({ employe: { id: 'emp-1' } }) };
  await creerDevis(repo, data, 'jwt', { client_id: ID, vendeur_id: 'pirate', succursale_code: 'HO' });
  const [, , ligne] = repo.appels.find(([op]) => op === 'insert');
  assert.equal(ligne.vendeur_id, 'emp-1');
  assert.equal(ligne.succursale_code, 'GA');
});

test('ligne de produit : prix laissé à la base (catalogue), description par défaut', async () => {
  const repo = fauxRepo({ 'get:produits': { id: ID2, nom: 'Thermopompe', taxable: true }, 'list:devis_lignes': [{ position: 3 }] });
  await ajouterLigne(repo, { devis_id: ID, produit_id: ID2, prix_unitaire_cents: 1, rabais_bp: 500 });
  const [, , l] = repo.appels.find(([op]) => op === 'insert');
  assert.equal(l.prix_unitaire_cents, 0);
  assert.equal(l.description, 'Thermopompe');
  assert.equal(l.position, 4);
});

test('ligne : rabais invalide, ligne libre sans prix, produit et kit à la fois', async () => {
  const repo = fauxRepo();
  await assert.rejects(() => ajouterLigne(repo, { devis_id: ID, description: 'x', prix_unitaire_cents: 100, rabais_bp: 5.5 }), /Rabais invalide/);
  await assert.rejects(() => ajouterLigne(repo, { devis_id: ID, description: 'x' }), /Prix en cents/);
  await assert.rejects(() => ajouterLigne(repo, { devis_id: ID, produit_id: ID, kit_id: ID2 }), /pas les deux/);
  await assert.rejects(() => modifierLigne(repo, ID, { rabais_bp: 20000 }), /Rabais invalide/);
});

test('statut : seulement les transitions permises', async () => {
  const repo = fauxRepo();
  await assert.rejects(() => changerStatut(repo, { id: ID, statut: 'brouillon' }), /non permis/);
  await changerStatut(repo, { id: ID, statut: 'refuse', raison_refus: 'Trop cher' });
  assert.deepEqual(repo.appels[0][3], { statut: 'refuse', raison_refus: 'Trop cher' });
});

test('approbation : motif requis, valeurs de rabais jamais envoyées par le client', async () => {
  const repo = fauxRepo();
  await assert.rejects(() => demanderApprobation(repo, { devis_ligne_id: ID }), /motif/);
  await demanderApprobation(repo, { devis_ligne_id: ID, motif: 'Concurrent', rabais_bp: 1 });
  assert.deepEqual(repo.appels[0][2], { devis_ligne_id: ID, motif: 'Concurrent' });
  await assert.rejects(() => deciderApprobation(repo, { id: ID, decision: 'peut-etre' }), /Décision/);
});

test('catalogue : prix du kit = somme des composantes si non fixé', async () => {
  const repo = fauxRepo({
    'list:produits': [],
    'list:kits': [{ id: ID, nom: 'Kit', prix_cents: null, kit_items: [{ quantite: 1, produits: { prix_cents: 300000 } }, { quantite: 2, produits: { prix_cents: 10000 } }] }],
  });
  const { kits } = await chercherCatalogue(repo, 'kit');
  assert.equal(kits[0].prix_cents, 320000);
  assert.equal(kits[0].kit_items, undefined);
  assert.deepEqual(await chercherCatalogue(repo, 'k'), { produits: [], kits: [] });
});

test('liste « expire » = envoyés dont la date est passée', async () => {
  const repo = fauxRepo();
  await listerDevis(repo, { statut: 'expire' });
  const { filtre } = repo.appels[0][2];
  assert.equal(filtre.statut, 'envoye');
  assert.equal(filtre.valide_jusqu.op, 'lt');
});

test('avecSession : 401 sans session, 405 mauvaise méthode, erreurs normalisées', async () => {
  const h = avecSession({ GET: async () => { throw Object.assign(new Error('Interdit'), { status: 403, code: '42501' }); } });
  assert.equal((await h({ httpMethod: 'GET', headers: {} })).statusCode, 401);
  assert.equal((await h({ httpMethod: 'PUT', headers: { cookie: 'bf_session=x' } })).statusCode, 405);
  const r = await h({ httpMethod: 'GET', headers: { cookie: 'bf_session=x' } }, {}, { adapter: { repo: () => ({}) } });
  assert.equal(r.statusCode, 403);
  assert.equal(JSON.parse(r.body).error.message, 'Interdit');
});

test('avecSession : erreur inattendue -> 500 sans détail interne', async () => {
  const h = avecSession({ GET: async () => { throw new Error('secret interne'); } });
  const orig = console.error; console.error = () => {};
  const r = await h({ httpMethod: 'GET', headers: { cookie: 'bf_session=x' } }, {}, { adapter: { repo: () => ({}) } });
  console.error = orig;
  assert.equal(r.statusCode, 500);
  assert.ok(!r.body.includes('secret interne'));
});

test('rabais global : mode et valeur validés, montant laissé à la base', async () => {
  const repo = fauxRepo();
  await assert.rejects(() => ajouterLigne(repo, { devis_id: ID, type_ligne: 'rabais', rabais_mode: 'cadeau', rabais_valeur: 100 }), /montant ou pourcentage/);
  await assert.rejects(() => ajouterLigne(repo, { devis_id: ID, type_ligne: 'rabais', rabais_mode: 'pourcentage', rabais_valeur: 15000 }), /100 %/);
  await assert.rejects(() => ajouterLigne(repo, { devis_id: ID, type_ligne: 'rabais', rabais_mode: 'montant', rabais_valeur: -200 }), /positive/);
  await ajouterLigne(repo, { devis_id: ID, type_ligne: 'rabais', rabais_mode: 'montant', rabais_valeur: 20000, prix_unitaire_cents: -999999 });
  const [, , l] = repo.appels.find(([op]) => op === 'insert');
  assert.equal(l.type_ligne, 'rabais');
  assert.equal(l.prix_unitaire_cents, 0);
  assert.equal(l.description, 'Rabais supplémentaire');
});
