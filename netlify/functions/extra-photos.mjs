// Photos d'un extra (ADR-082), bucket privé « extras-photos »
// GET ?extra= -> [{ id, url }] (URL signées 10 min) | POST ?extra= { type, donnees (base64) } -> photo ajoutée au brouillon
// PATCH { action: 'retirer', id } -> photo retirée du brouillon
import { avecSession, ErreurValidation } from '../../lib/handler.js';
import { ajouterPhoto, photosExtra, retirerPhoto } from '../../lib/modules/extras.js';

export const handler = avecSession({
  GET: ({ repo, query }) => photosExtra(repo, query.extra),
  POST: async ({ repo, query, corps }) => ({ status: 201, body: await ajouterPhoto(repo, query.extra, corps) }),
  PATCH: ({ repo, corps }) => {
    if (corps?.action !== 'retirer') throw new ErreurValidation('Action inconnue');
    return retirerPhoto(repo, corps.id);
  },
});
