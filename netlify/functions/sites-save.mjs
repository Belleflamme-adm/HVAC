// POST { client_id, adresse, ville, ... } -> nouveau lieu | PATCH ?id= -> modification
import { avecSession } from '../../lib/handler.js';
import { creerSite, modifierSite } from '../../lib/modules/clients.js';

export const handler = avecSession({
  POST: async ({ repo, corps }) => ({ status: 201, body: await creerSite(repo, corps) }),
  PATCH: ({ repo, query, corps }) => modifierSite(repo, query.id, corps),
});
