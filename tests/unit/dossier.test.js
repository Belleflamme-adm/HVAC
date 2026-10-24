import { test } from 'node:test';
import assert from 'node:assert/strict';
import { lireDossier, ajouterAuDossier, modifierDossier, purgerPhotos, BUCKET_JOBS } from '../../lib/modules/dossier.js';
import { creerAccesSysteme } from '../../lib/data/systeme.js';
import { config } from '../../lib/config.js';

const ID = '11111111-1111-4111-8111-111111111111';
const jpeg = Buffer.from([0xff, 0xd8, 0xff, 0xe0, 9, 9]).toString('base64');
const fauxRepo = () => {
  const appels = [];
  return { appels,
    rpc: async (fn, a) => { appels.push([fn, a]);
      if (fn === 'hvac_job_dossier') return { numero_ahri: '210987654', equipements: [], photos: [{ id: ID, categorie: 'plaque', chemin: `${ID}/a.jpg` }], manques: [] };
      if (fn === 'hvac_job_photo_preparer') return { id: ID, chemin: `${ID}/b.jpg` };
      return ID; },
    televerser: async (...a) => appels.push(['televerser', ...a]),
    urlsSignees: async (b, chemins) => chemins.map((c) => `https://x.supabase.co/sign/${b}/${c}`) };
};

test('dossier : URL signées à la place des chemins', async () => {
  const r = fauxRepo();
  const d = await lireDossier(r, ID);
  assert.equal(d.photos[0].url, `https://x.supabase.co/sign/${BUCKET_JOBS}/${ID}/a.jpg`);
  assert.equal(d.photos[0].chemin, undefined);
});

test('dossier : appareil complet, photo vérifiée et téléversée au chemin préparé', async () => {
  const r = fauxRepo();
  await ajouterAuDossier(r, ID, { action: 'equipement', role: 'exterieur', marque: ' Mitsubishi ', modele: 'MXZ', numero_serie: '31U' });
  assert.deepEqual(r.appels[0][1].p, { role: 'exterieur', marque: 'Mitsubishi', modele: 'MXZ', numero_serie: '31U' });
  await assert.rejects(ajouterAuDossier(r, ID, { action: 'equipement', role: 'exterieur', marque: 'M', modele: 'X' }), /série/);
  await ajouterAuDossier(r, ID, { action: 'photo', equipement_id: ID, categorie: 'plaque', type: 'image/jpeg', donnees: jpeg });
  assert.deepEqual(r.appels.slice(1).map((a) => a[0]), ['hvac_job_photo_preparer', 'televerser', 'hvac_job_photo_confirmer']);
  assert.equal(r.appels[2][1], BUCKET_JOBS);
  await assert.rejects(ajouterAuDossier(r, ID, { action: 'photo', categorie: 'selfie', type: 'image/jpeg', donnees: jpeg }), /Catégorie/);
});

test('dossier : numéro AHRI validé', async () => {
  const r = fauxRepo();
  await modifierDossier(r, { action: 'ahri', projet: ID, numero_ahri: '210 987 654' });
  assert.deepEqual(r.appels[0], ['hvac_job_ahri', { p_projet: ID, p_numero: '210987654' }]);
  await assert.rejects(modifierDossier(r, { action: 'ahri', projet: ID, numero_ahri: 'AB-12' }), /AHRI/);
});

test('purge : compte seulement tant que non active ; sinon fichiers effacés puis marqués', async () => {
  const lots = [{ source: 'job', id: 'a', bucket: 'jobs-photos', chemin: 'p/a.jpg' }, { source: 'extra', id: 'b', bucket: 'extras-photos', chemin: 'p/e/b.jpg' }];
  const appels = [];
  const systeme = { rpc: async (fn, a) => { appels.push([fn, a]); return fn === 'hvac_photos_a_purger' ? lots : 2; },
    supprimerFichiers: async (b, c) => appels.push(['supprimer', b, c]) };
  assert.deepEqual(await purgerPhotos(systeme, { actif: false }), { a_purger: 2, purgees: 0, actif: false });
  assert.equal(appels.filter((a) => a[0] === 'supprimer').length, 0);
  assert.deepEqual(await purgerPhotos(systeme, { actif: true }), { a_purger: 2, purgees: 2, actif: true });
  assert.deepEqual(appels.at(-1), ['hvac_photos_purgees', { p_job: ['a'], p_extra: ['b'] }]);
});

test('accès système : clé requise, seulement les gestes de la purge', async () => {
  assert.throws(() => creerAccesSysteme({ supabaseUrl: 'https://x.supabase.co', supabaseServiceRoleKey: '' }), /SERVICE_ROLE/);
  const sys = creerAccesSysteme({ supabaseUrl: 'https://x.supabase.co', supabaseServiceRoleKey: 'cle-bidon' }, { createClientImpl: () => ({ rpc: async () => ({ data: [] }) }) });
  await assert.rejects(sys.rpc('hvac_projet_signe', {}), /non permise/);
  await assert.rejects(sys.supprimerFichiers('hvac-documents', ['x']), /non permis/);
  assert.equal(config({}).purgePhotosActif, false);
});
