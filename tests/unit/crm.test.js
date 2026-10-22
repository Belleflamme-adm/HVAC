import { test } from 'node:test';
import assert from 'node:assert/strict';
import { listerLeads, creerLead, ajouterActivite, majObjectifs, majVendeursBoard, reattribuer } from '../../lib/modules/crm.js';
import { duree } from '../../public/js/bf-crm.js';

const E = '11111111-1111-4111-8111-111111111111';
const L = '22222222-2222-4222-8222-222222222222';

function fauxRepo() {
  const appels = [];
  const r = (op) => async (...a) => { appels.push([op, ...a]); return op === 'list' ? [] : { ok: true }; };
  return { appels, list: r('list'), insert: r('insert'), update: r('update'), updateWhere: r('updateWhere'), upsert: r('upsert'), removeWhere: r('removeWhere') };
}

test('CRM : « Mes leads » filtre sur le vendeur connecté ; « actifs » exclut vendus et perdus', async () => {
  const repo = fauxRepo();
  await listerLeads(repo, { vue: 'mes', employeId: E, statut: 'actifs' });
  const [, table, { filtre }] = repo.appels[0];
  assert.equal(table, 'leads_v');
  assert.equal(filtre.assigne_a, E);
  assert.ok(!filtre.statut.val.includes('perdu') && !filtre.statut.val.includes('converti'));
  await assert.rejects(listerLeads(repo, { vue: 'board', statut: 'n_importe_quoi' }), /Statut inconnu/);
});

test('CRM : un lead saisi exige un nom et un moyen de contact', async () => {
  const repo = fauxRepo();
  await assert.rejects(creerLead(repo, { succursale_code: 'RO', contact_nom: 'X' }), /Téléphone ou courriel/);
  await assert.rejects(creerLead(repo, { succursale_code: 'RO', contact_nom: 'X', contact_tel: '1', source: 'tiktok' }), /Source inconnue/);
  await creerLead(repo, { succursale_code: 'RO', contact_nom: 'X', contact_tel: '450', assigne_a: E, statut: 'converti' });
  const ligne = repo.appels.at(-1)[2];
  assert.ok(!('assigne_a' in ligne) && !('statut' in ligne), 'attribution et statut : décidés par la base');
});

test('CRM : activités validées, attribuées à l\'employé connecté, sans heure fournie par le client', async () => {
  const repo = fauxRepo();
  await assert.rejects(ajouterActivite(repo, L, E, { type: 'visite_planifiee' }), /Date de visite/);
  await assert.rejects(ajouterActivite(repo, L, E, { type: 'perdu', note: '  ' }), /Raison/);
  await assert.rejects(ajouterActivite(repo, L, E, { type: 'attribution' }), /inconnu/);
  await ajouterActivite(repo, L, E, { type: 'appel', resultat: 'joint', fait_le: '2020-01-01', employe_id: 'autre' });
  const ligne = repo.appels.at(-1)[2];
  assert.equal(ligne.employe_id, E);
  assert.ok(!('fait_le' in ligne), 'l\'heure vient de la base');
});

test('CRM : seuils du tableau de quantification (vide = non évalué, virgule acceptée)', async () => {
  const repo = fauxRepo();
  await majObjectifs(repo, { objectifs: [{ indicateur: 'minutes_premier_contact', seuil_bon: '15', seuil_moyen: '' },
    { indicateur: 'pct_visites', seuil_bon: '62,5', seuil_moyen: 40 }] });
  assert.deepEqual(repo.appels[0][3], { seuil_bon: 15, seuil_moyen: null });
  assert.deepEqual(repo.appels[1][3], { seuil_bon: 62.5, seuil_moyen: 40 });
  await assert.rejects(majObjectifs(repo, { objectifs: [{ indicateur: 'x; drop', seuil_bon: 1 }] }), /Indicateur invalide/);
  await assert.rejects(majObjectifs(repo, { objectifs: [{ indicateur: 'pct_visites', seuil_bon: -3 }] }), /Seuil invalide/);
});

test('CRM : vendeurs du board, ordre par défaut = position', async () => {
  const repo = fauxRepo();
  await majVendeursBoard(repo, { vendeurs: [{ employe_id: E }, { employe_id: L, actif: false, ordre: 5 }] });
  assert.deepEqual(repo.appels[0][2], [{ employe_id: E, ordre: 1, actif: true }, { employe_id: L, ordre: 5, actif: false }]);
});

test('CRM : affichage des délais', () => {
  assert.equal(duree(7), '7 min');
  assert.equal(duree(75), '1 h 15');
  assert.equal(duree(60 * 24 * 2 + 90), '2 j 1 h');
});

test('CRM : qualifications des vendeurs par type de demande', async () => {
  const repo = fauxRepo();
  await majVendeursBoard(repo, { vendeurs: [{ employe_id: E, types: ['mural_simple', 'central'] }] });
  const ajout = repo.appels.find(([op, t]) => op === 'upsert' && t === 'crm_vendeur_types');
  const retrait = repo.appels.find(([op, t]) => op === 'removeWhere' && t === 'crm_vendeur_types');
  assert.deepEqual(ajout[2].map((x) => x.type_demande), ['mural_simple', 'central']);
  assert.deepEqual(retrait[2], { employe_id: E, type_demande: ['mural_multi', 'bienergie'] });
  await assert.rejects(majVendeursBoard(repo, { vendeurs: [{ employe_id: E, types: ['piscine'] }] }), /Type de demande inconnu/);
});

test('CRM : type de demande à la saisie et correction par le board', async () => {
  const repo = fauxRepo();
  await assert.rejects(creerLead(repo, { succursale_code: 'RO', contact_nom: 'X', contact_tel: '1', type_demande: 'spa' }), /Type de demande/);
  await creerLead(repo, { succursale_code: 'RO', contact_nom: 'X', contact_tel: '1', type_demande: 'bienergie' });
  assert.equal(repo.appels.at(-1)[2].type_demande, 'bienergie');
  await reattribuer(repo, L, { type_demande: 'central' });
  assert.deepEqual(repo.appels.at(-1)[3], { type_demande: 'central' });
  await assert.rejects(reattribuer(repo, L, {}), /Rien à modifier/);
});
