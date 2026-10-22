// POST { nom, succursale_code, ..., site?: { adresse, ville, ... }, consentement_hq?, consentement_comm? }
import { avecSession } from '../../lib/handler.js';
import { creerClient } from '../../lib/modules/clients.js';

export const handler = avecSession({
  POST: async ({ repo, corps }) => ({ status: 201, body: await creerClient(repo, corps) }),
});
