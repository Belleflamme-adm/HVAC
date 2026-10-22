import { test } from 'node:test';
import assert from 'node:assert/strict';
import { ajouterLigne, optionsInstallation, changerMarge, ajouterTarif } from '../../lib/modules/devis.js';

const D = '11111111-1111-4111-8111-111111111111';
const T = '22222222-2222-4222-8222-222222222222';
const S = '33333333-3333-4333-8333-333333333333';

function fauxRepo(donnees = {}) {
  const appels = [];
  return {
    appels,
    async list(table, opts) { appels.push(['list', table, opts]); return donnees[`list:${table}`] || []; },
    async get(table) { return donnees[`get:${table}`] ?? null; },
    async insert(table, ligne) { appels.push(['insert', table, ligne]); return ligne; },
    async updateWhere(table, filtre, patch) { appels.push(['updateWhere', table, filtre, patch]); return patch; },
  };
}

test('installation selon la grille : le prix, le coût et la marge ne viennent jamais du formulaire', async () => {
  const repo = fauxRepo({ 'get:types_travaux': { id: T, nom: 'Installation murale' } });
  const l = await ajouterLigne(repo, { devis_id: D, type_ligne: 'installation', type_travail_id: T, sous_traitant_id: S,
    cout_cents: 1, prix_unitaire_cents: 999999, marge_bp: 1, reference_soumission: 'X' });
  assert.equal(l.type_ligne, 'installation');
  assert.equal(l.source_cout, 'grille');
  assert.equal(l.cout_cents, undefined);
  assert.equal(l.reference_soumission, undefined);
  assert.equal(l.marge_bp, undefined);
  assert.equal(l.prix_unitaire_cents, 0);
  assert.equal(l.description, 'Installation murale');
});

test('installation selon la grille : sous-traitant obligatoire', async () => {
  await assert.rejects(() => ajouterLigne(fauxRepo(), { devis_id: D, type_ligne: 'installation', type_travail_id: T }), /Sous-traitant requis/);
});

test('soumission : coût et numéro de soumission obligatoires', async () => {
  const base = { devis_id: D, type_ligne: 'installation', type_travail_id: T, source_cout: 'soumission', description: 'Toit plat' };
  await assert.rejects(() => ajouterLigne(fauxRepo(), { ...base, reference_soumission: 'ST-1' }), /Coût de la soumission/);
  await assert.rejects(() => ajouterLigne(fauxRepo(), { ...base, cout_cents: 175000 }), /Numéro de soumission/);
  const l = await ajouterLigne(fauxRepo(), { ...base, cout_cents: 175000, reference_soumission: 'ST-1' });
  assert.equal(l.cout_cents, 175000);
});

test('options : tarif le plus récent déjà en vigueur, tarif futur ignoré', async () => {
  const repo = fauxRepo({
    'list:tarifs_sous_traitants': [
      { fournisseur_id: S, type_travail_id: T, cout_cents: 120000, en_vigueur_du: '2999-01-01' },
      { fournisseur_id: S, type_travail_id: T, cout_cents: 100000, en_vigueur_du: '2026-01-01' },
      { fournisseur_id: S, type_travail_id: T, cout_cents: 90000, en_vigueur_du: '2020-01-01' },
    ],
    'list:parametres': [{ cle: 'marge_installation_bp', valeur: 3000 }],
  });
  const o = await optionsInstallation(repo);
  assert.equal(o.grille.length, 1);
  assert.equal(o.grille[0].cout_cents, 100000);
  assert.equal(o.margeBp, 3000);
});

test('marge : bornée, enregistrée en points de base', async () => {
  const repo = fauxRepo({ 'list:parametres': [{ cle: 'marge_installation_bp' }] });
  await assert.rejects(() => changerMarge(repo, { marge_bp: 9500 }), /Marge invalide/);
  await assert.rejects(() => changerMarge(repo, { marge_bp: 30.5 }), /Marge invalide/);
  await changerMarge(repo, { marge_bp: 3200 });
  assert.deepEqual(repo.appels.at(-1), ['updateWhere', 'parametres', { cle: 'marge_installation_bp' }, { valeur: 3200 }]);
});

test('tarif : coût positif en cents', async () => {
  await assert.rejects(() => ajouterTarif(fauxRepo(), { fournisseur_id: S, type_travail_id: T, cout_cents: 0 }), /Coût/);
});
