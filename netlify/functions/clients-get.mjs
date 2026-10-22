// GET ?id= -> { client, sites, devis }
import { avecSession } from '../../lib/handler.js';
import { obtenirClient } from '../../lib/modules/clients.js';

const introuvable = { status: 404, body: { error: { code: 'introuvable', message: 'Introuvable' } } };

export const handler = avecSession({
  GET: async ({ repo, query }) => (await obtenirClient(repo, query.id)) || introuvable,
});
