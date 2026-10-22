import { test } from 'node:test';
import assert from 'node:assert/strict';
import { fournisseurCible, majTerritoire, majDisponibilites, creerSousTraitant, designerPrincipal } from '../../lib/modules/sous-traitants.js';
import { grilleMois } from '../../public/js/bf-calendrier.js';
import { projeter, cheminSvg, boite } from '../../public/js/bf-carte.js';
import { tuilesPour } from '../../public/js/bf-tuiles.js';
import { liensPour } from '../../public/js/bf-page.js';

const F = '33333333-3333-4333-8333-333333333333';
const AUTRE = '44444444-4444-4444-8444-444444444444';

function fauxRepo() {
  const appels = [];
  const r = (op) => async (...a) => { appels.push([op, ...a]); return op === 'insert' ? { id: F, ...a[1] } : []; };
  return { appels, insert: r('insert'), upsert: r('upsert'), removeWhere: r('removeWhere'), list: r('list') };
}

test('un sous-traitant agit toujours sur son propre fournisseur, même s\'il en demande un autre', async () => {
  const st = { session: async () => ({ employe: { id: 'e', fournisseur_id: F } }) };
  assert.equal(await fournisseurCible(st, 't', AUTRE), F);
  const coord = { session: async () => ({ employe: { id: 'e', fournisseur_id: null } }) };
  assert.equal(await fournisseurCible(coord, 't', AUTRE), AUTRE);
  await assert.rejects(() => fournisseurCible(coord, 't', 'pas-un-uuid'), /invalide/);
});

test('territoire : statut et supplément validés, « aucun » efface', async () => {
  const repo = fauxRepo();
  await assert.rejects(() => majTerritoire(repo, F, { municipalites: ['1'], statut: 'peut-etre' }), /Statut/);
  await assert.rejects(() => majTerritoire(repo, F, { municipalites: ['1'], statut: 'supplement' }), /Supplément/);
  await assert.rejects(() => majTerritoire(repo, F, { municipalites: [], statut: 'accepte' }), /invalide/);
  await majTerritoire(repo, F, { municipalites: ['1', '2'], statut: 'supplement', supplement_cents: 15000 });
  const [, table, lignes, opts] = repo.appels.at(-1);
  assert.equal(table, 'territoires_sous_traitants');
  assert.deepEqual(lignes[1], { fournisseur_id: F, municipalite_code: '2', statut: 'supplement', supplement_cents: 15000 });
  assert.equal(opts.onConflict, 'fournisseur_id,municipalite_code');
  await majTerritoire(repo, F, { municipalites: ['1'], statut: 'aucun' });
  assert.equal(repo.appels.at(-1)[0], 'removeWhere');
});

test('disponibilités : dates valides, pas dans le passé', async () => {
  const repo = fauxRepo();
  await assert.rejects(() => majDisponibilites(repo, F, { jours: [{ jour: '2001-01-01', statut: 'disponible' }] }), /passées/);
  await assert.rejects(() => majDisponibilites(repo, F, { jours: [{ jour: '20-1-1', statut: 'disponible' }] }), /invalide/);
  await assert.rejects(() => majDisponibilites(repo, F, { jours: [{ jour: '2999-01-01', statut: 'occupé' }] }), /Statut/);
  const r = await majDisponibilites(repo, F, { jours: [{ jour: '2999-01-01', statut: 'disponible' }, { jour: '2999-01-02', statut: 'aucun' }] });
  assert.deepEqual(r, { ok: true, ecrits: 1, effaces: 1 });
});

test('création d\'un sous-traitant : fournisseur + compte au rôle Sous-traitant', async () => {
  const repo = fauxRepo();
  await assert.rejects(() => creerSousTraitant(repo, { nom: 'X', contact: { prenom: 'A' } }), /Champ requis/);
  await creerSousTraitant(repo, { nom: 'Réfrig X', contact: { prenom: 'A', nom: 'B', email: 'A@X.CA ' } });
  const compte = repo.appels.find(([, t]) => t === 'employes')[2];
  assert.equal(compte.role, 'Sous-traitant');
  assert.equal(compte.email, 'a@x.ca');
  assert.equal(compte.fournisseur_id, F);
});

test('principal : retirer = fournisseur null', async () => {
  const repo = fauxRepo();
  await designerPrincipal(repo, { municipalite_code: '1' });
  assert.equal(repo.appels.at(-1)[2][0].fournisseur_id, null);
});

test('calendrier : semaines du lundi au dimanche', () => {
  const g = grilleMois(2026, 10);   // novembre 2026 : le 1er est un dimanche
  assert.equal(g[0].filter(Boolean).length, 1);
  assert.equal(g[0][6].getDate(), 1);
  assert.equal(g.flat().filter(Boolean).length, 30);
  assert.ok(g.every((s) => s.length === 7));
});

test('carte : projection, tracé et boîte', () => {
  const [x, y] = projeter([-74, 46]);
  assert.ok(x < 0 && y === -4600);
  const geom = { type: 'MultiPolygon', coordinates: [[[[-74, 46], [-73, 46], [-73, 47], [-74, 46]]]] };
  assert.match(cheminSvg(geom), /^M-?\d+\.\d{2} -4600\.00L.*Z$/);
  const b = boite([{ geometry: geom }]);
  assert.equal(b.h, 100);
});

test('menu et tuiles selon le rôle', () => {
  const st = { sousTraitantId: F, role: 'Sous-traitant' };
  assert.deepEqual(liensPour(st).map(([h]) => h), ['/', '/territoire', '/disponibilites']);
  assert.ok(!tuilesPour(st).some((t) => ['clients', 'devis'].includes(t.cle)));
  assert.ok(liensPour({ role: 'Coordonnateur' }).some(([h]) => h === '/sous-traitants'));
  assert.ok(!liensPour({ role: 'Vendeur' }).some(([h]) => h === '/sous-traitants'));
});
