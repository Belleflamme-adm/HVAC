// GET ?id= -> lead et son journal | PATCH ?id= { assigne_a } -> réattribution (board principal seulement)
import { avecSession } from '../../lib/handler.js';
import { obtenirLead, reattribuer } from '../../lib/modules/crm.js';

export const handler = avecSession({
  GET: async ({ repo, query }) => (await obtenirLead(repo, query.id)) || { status: 404, body: { error: { code: 'introuvable', message: 'Lead introuvable' } } },
  PATCH: ({ repo, query, corps }) => reattribuer(repo, query.id, corps),
});
