// POST { client_id, site_id?, notes_client? } -> devis en brouillon, numéroté par la base
import { avecSession } from '../../lib/handler.js';
import { creerDevis } from '../../lib/modules/devis.js';

export const handler = avecSession({
  POST: async ({ repo, data, token, corps }) => ({ status: 201, body: await creerDevis(repo, data, token, corps) }),
});
