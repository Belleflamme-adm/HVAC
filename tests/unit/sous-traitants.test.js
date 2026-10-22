import { test } from 'node:test';
import assert from 'node:assert/strict';
import { fournisseurCible, lireTousTerritoires, normaliserRbq, modifierSousTraitant, majTerritoire, majDisponibilites, creerSousTraitant, designerPrincipal } from '../../lib/modules/sous-traitants.js';
import { grilleMois } from '../../public/js/bf-calendrier.js';
import { projeter, cheminSvg, boite, centroide, regrouper, frontieres, choisirEtiquettes, PALETTE_ST, couleurSt, nuancer } from '../../public/js/bf-carte.js';
import { readFileSync } from 'node:fs';
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

test('carte comparative : un sous-traitant ne voit pas le territoire des autres ; refus exclus', async () => {
  const st = { session: async () => ({ employe: { id: 'e', fournisseur_id: F } }) };
  await assert.rejects(() => lireTousTerritoires(fauxRepo(), st, 't'), /Réservé/);
  const repo = fauxRepo();
  await lireTousTerritoires(repo, { session: async () => ({ employe: { id: 'e', fournisseur_id: null } }) }, 't');
  const [op, table, opts] = repo.appels[0];
  assert.equal(op, 'list'); assert.equal(table, 'territoires_sous_traitants');
  assert.deepEqual(opts.filtre.statut.val, ['accepte', 'supplement']);
});

test('couleurs des sous-traitants : distinctes, sans vert / orange / rouge, nuances correctes', () => {
  assert.equal(new Set(PALETTE_ST).size, PALETTE_ST.length);
  for (const c of ['#2e9d63', '#e2a01b', '#c9483f']) assert.ok(!PALETTE_ST.includes(c));
  assert.equal(couleurSt(0), PALETTE_ST[0]);
  assert.equal(couleurSt(PALETTE_ST.length), PALETTE_ST[0]);
  assert.equal(nuancer('#000000', 0.5), '#808080');
  assert.equal(nuancer('#ffffff', -1), '#000000');
  assert.equal(nuancer('#1d4ed8', 0), '#1d4ed8');
});

test('fiche : numéro RBQ normalisé (10 chiffres), vide = aucun', () => {
  assert.equal(normaliserRbq('1234567890'), '1234-5678-90');
  assert.equal(normaliserRbq(' 1234 5678 90 '), '1234-5678-90');
  assert.equal(normaliserRbq('1234-5678-90'), '1234-5678-90');
  assert.equal(normaliserRbq(''), null);
  assert.throws(() => normaliserRbq('12345'), /RBQ/);
  assert.throws(() => normaliserRbq('1234-5678-9A'), /RBQ/);
});

test('fiche : seuls les champs permis, courriels et nom validés', async () => {
  const repo = { ...fauxRepo(), update: async (t, id, patch) => ({ t, id, patch }) };
  const r = await modifierSousTraitant(repo, F, { responsable_nom: ' Jean ', proprietaire_nom: 'Luc', responsable_courriel: 'JEAN@Ex.ca',
    licence_rbq: '1234567890', type: 'fournisseur', id: AUTRE });
  assert.deepEqual(r.patch, { responsable_nom: 'Jean', proprietaire_nom: 'Luc', responsable_courriel: 'jean@ex.ca', licence_rbq: '1234-5678-90' });
  await assert.rejects(() => modifierSousTraitant(repo, F, { responsable_courriel: 'pas-un-courriel' }), /Courriel/);
  await assert.rejects(() => modifierSousTraitant(repo, F, { nom: ' ' }), /Nom/);
  await assert.rejects(() => modifierSousTraitant(repo, F, {}), /Rien/);
  await assert.rejects(() => modifierSousTraitant(repo, 'x', { nom: 'Abc' }), /invalide/);
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

// Trois carrés côte à côte : A et B dans la région R1, C dans R2
const carre = (x, code, region, mrc) => ({ properties: { code, nom: code, region, mrc },
  geometry: { type: 'Polygon', coordinates: [[[x, 46], [x + 1, 46], [x + 1, 47], [x, 47], [x, 46]]] } });
const TROIS = [carre(-75, 'A', 'R1', 'M1'), carre(-74, 'B', 'R1', 'M1'), carre(-73, 'C', 'R2', 'M2')];

test('carte : centre de gravité et regroupement par région', () => {
  const c = centroide(TROIS[0].geometry);
  const [x, y] = projeter([-74.5, 46.5]);
  assert.ok(Math.abs(c.x - x) < 1e-9 && Math.abs(c.y - y) < 1e-9);
  const regions = regrouper(TROIS, 'region');
  assert.deepEqual(regions.map((g) => g.nom), ['R1', 'R2']);
  assert.ok(Math.abs(regions[0].x - projeter([-74, 46.5])[0]) < 1e-9, 'R1 centrée entre A et B');
});

test('carte : frontière de région = arête entre régions différentes + contour, pas entre A et B', () => {
  const d = frontieres(TROIS, 'region');
  const segments = d.split('M').filter(Boolean).length;
  // Contour extérieur : 3 en haut + 3 en bas + 2 côtés = 8 ; plus l'arête B|C = 9 ; l'arête A|B est exclue
  assert.equal(segments, 9);
  const [xab] = projeter([-74, 46]);
  assert.ok(!d.includes(`M${xab.toFixed(2)} -4600.00L${xab.toFixed(2)} -4700.00`), 'pas de trait entre A et B');
});

test('carte : étiquettes par priorité, sans chevauchement, seulement si le nom tient', () => {
  const vis = { x: 0, y: 0, l: 1000, h: 1000 };
  const c = (texte, x, priorite, boiteL) => ({ texte, x, y: 500, taille: 10, priorite, boite: boiteL ? { l: boiteL } : null });
  const r = choisirEtiquettes([
    c('Petite', 520, 5, 80),        // chevauche Grande ville : écartée
    c('Grande ville', 500, 1),
    c('Minuscule', 900, 5, 10),     // ne tient pas dans sa forme : écartée
    c('Hors vue', 2000, 1),
    c('Loin', 100, 5, 200),
    c('Coupée au bord', 995, 1),
  ], vis, 1);
  assert.deepEqual(r.map((e) => e.texte), ['Grande ville', 'Loin']);
});

test('carte : villes repères valides (1 ou 2), sans doublon', () => {
  const brut = readFileSync(new URL('../../public/data/villes-reperes.json', import.meta.url), 'utf8');
  const reperes = JSON.parse(brut);
  for (const [nom, rang] of Object.entries(reperes)) if (!nom.startsWith('_')) assert.ok([1, 2].includes(rang), nom);
  assert.ok(reperes['Saint-Jérôme'] === 1 && reperes['Rosemère'] === 2);
  assert.ok(!brut.includes('\u2014') && !brut.includes('—'), 'jamais de tiret cadratin');
});

test('recentrage CRM : modules de Mike visibles mais en veille, à la fin', () => {
  const t = tuilesPour({ role: 'Vendeur' });
  const devis = t.find((x) => x.cle === 'devis');
  assert.equal(devis.etat, 'veille', 'le devis reste visible, en veille');
  assert.equal(t.find((x) => x.cle === 'leads').etat, 'actif');
  const premiereVeille = t.findIndex((x) => x.etat === 'veille');
  assert.ok(t.slice(premiereVeille).every((x) => x.etat === 'veille'), 'les tuiles en veille sont regroupées à la fin');
  assert.ok(!liensPour({ role: 'Vendeur' }).some(([h]) => h === '/devis'), 'le devis sort du menu');
});

test('menu et tuiles selon le rôle', () => {
  const st = { sousTraitantId: F, role: 'Sous-traitant' };
  assert.deepEqual(liensPour(st).map(([h]) => h), ['/', '/territoire', '/mes-prix', '/disponibilites']);
  assert.ok(!tuilesPour(st).some((t) => ['clients', 'devis'].includes(t.cle)));
  assert.ok(liensPour({ role: 'Coordonnateur' }).some(([h]) => h === '/sous-traitants'));
  assert.ok(!liensPour({ role: 'Vendeur' }).some(([h]) => h === '/sous-traitants'));
});
