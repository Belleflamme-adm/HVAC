// POST { id } -> { id } du nouveau devis (nouveau numéro, mêmes lignes, brouillon)
import { avecSession } from '../../lib/handler.js';
import { renouveler } from '../../lib/modules/devis.js';

export const handler = avecSession({
  POST: async ({ repo, corps }) => ({ status: 201, body: await renouveler(repo, corps.id) }),
});
