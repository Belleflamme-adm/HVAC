// Tâche planifiée (netlify.toml, chaque jour) : purge des photos 5 ans après « Terminé » (Loi 25, ADR-084).
// PURGE_PHOTOS_ACTIF=false (défaut) : compte seulement, n'efface rien. Simon l'active à la mise en ligne.
import { config } from '../../lib/config.js';
import { creerAccesSysteme } from '../../lib/data/systeme.js';
import { purgerPhotos } from '../../lib/modules/dossier.js';

export const handler = async () => {
  const cfg = config();
  try {
    const r = await purgerPhotos(creerAccesSysteme(cfg), { actif: cfg.purgePhotosActif });
    console.log('purge photos', JSON.stringify(r));
    return { statusCode: 200, body: JSON.stringify(r) };
  } catch (e) {
    console.error('purge photos', e.message);
    return { statusCode: e.status || 500, body: JSON.stringify({ error: e.message }) };
  }
};
