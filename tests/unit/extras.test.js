import { test } from 'node:test';
import assert from 'node:assert/strict';
import { listerExtras, ajouterExtra, geste } from '../../lib/modules/extras.js';

const ID = '11111111-1111-4111-8111-111111111111';
const fauxRepo = () => { const appels = []; return { appels, list: async (...a) => { appels.push(['list', ...a]); return []; },
  rpc: async (...a) => { appels.push(['rpc', ...a]); return 2; } }; };

test('extras : file d\'approbation par défaut, ou par projet', async () => {
  const r = fauxRepo();
  await listerExtras(r, {});
  assert.equal(r.appels[0][2].filtre.statut, 'soumis');
  await listerExtras(r, { projet: ID });
  assert.deepEqual(r.appels[1][2].filtre, { projet_id: ID });
});

test('extra de la liste : aucun prix ne passe du navigateur', async () => {
  const r = fauxRepo();
  await ajouterExtra(r, ID, { type_travail_id: ID, quantite: '10', cout_cents: 1, cause: 'oubli_vendeur' });
  assert.deepEqual(r.appels[0], ['rpc', 'hvac_extra_ajouter', { p_projet: ID, p: { cause: 'oubli_vendeur', quantite: 10, type_travail_id: ID } }]);
});

test('extra hors liste : prix, justification et cause obligatoires', async () => {
  const r = fauxRepo();
  await ajouterExtra(r, ID, { description: 'Support mural', cout_cents: 18000, justification: 'Mur de brique friable', cause: 'imprevu_chantier' });
  assert.equal(r.appels[0][2].p.cout_cents, 18000);
  await assert.rejects(ajouterExtra(r, ID, { description: 'X', cout_cents: 18000, justification: 'court', cause: 'autre' }), /Justification/);
  await assert.rejects(ajouterExtra(r, ID, { description: 'X', cout_cents: 0, justification: 'assez longue ici', cause: 'autre' }), /Prix/);
  await assert.rejects(ajouterExtra(r, ID, { type_travail_id: ID }), /Cause/);
});

test('gestes : refus avec raison, actions connues seulement', async () => {
  const r = fauxRepo();
  assert.deepEqual(await geste(r, { action: 'envoyer', projet: ID }), { envoyes: 2 });
  await geste(r, { action: 'decider', id: ID, approuve: true });
  assert.deepEqual(r.appels[1], ['rpc', 'hvac_extra_decider', { p_id: ID, p_approuve: true, p_raison: null }]);
  await assert.rejects(geste(r, { action: 'decider', id: ID, approuve: false }), /Raison/);
  await assert.rejects(geste(r, { action: 'payer', id: ID }), /inconnue/);
  assert.deepEqual(await geste(r, { action: 'facture', projet: ID }), { total_cents: 2 });
});

test('photo : vraie image du type annoncé, téléversée au chemin préparé par la base', async () => {
  const { ajouterPhoto, photosExtra, decoderPhoto, BUCKET_PHOTOS } = await import('../../lib/modules/extras.js');
  const jpeg = Buffer.from([0xff, 0xd8, 0xff, 0xe0, 1, 2, 3]).toString('base64');
  const appels = [];
  const repo = {
    rpc: async (fn, a) => { appels.push([fn, a]); return fn === 'hvac_extra_photo_preparer' ? { id: ID, chemin: `p/${ID}/x.jpg` } : fn === 'hvac_extra_photos' ? [{ id: ID, chemin: 'p/e/x.jpg' }] : null; },
    televerser: async (...a) => appels.push(['televerser', ...a]),
    urlsSignees: async (b, chemins, s) => chemins.map((c) => `https://signe/${b}/${c}?t=${s}`),
  };
  assert.deepEqual(await ajouterPhoto(repo, ID, { type: 'image/jpeg', donnees: jpeg }), { id: ID });
  assert.deepEqual(appels.map((a) => a[0]), ['hvac_extra_photo_preparer', 'televerser', 'hvac_extra_photo_confirmer']);
  assert.equal(appels[1][1], BUCKET_PHOTOS);
  assert.equal(appels[1][2], `p/${ID}/x.jpg`);
  assert.throws(() => decoderPhoto('image/png', jpeg), /image valide/);
  assert.throws(() => decoderPhoto('application/pdf', jpeg), /JPEG/);
  assert.deepEqual(await photosExtra(repo, ID), [{ id: ID, url: 'https://signe/extras-photos/p/e/x.jpg?t=600' }]);
});
