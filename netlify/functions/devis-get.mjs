// GET ?id= -> { devis, lignes, approbations, client, site }
import { avecSession } from '../../lib/handler.js';
import { obtenirDevis } from '../../lib/modules/devis.js';

const introuvable = { status: 404, body: { error: { code: 'introuvable', message: 'Introuvable' } } };

export const handler = avecSession({
  GET: async ({ repo, query }) => (await obtenirDevis(repo, query.id)) || introuvable,
});
