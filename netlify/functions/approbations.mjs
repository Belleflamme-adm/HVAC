// GET -> demandes en attente | POST { devis_ligne_id, motif } -> demande
// PATCH { id, decision: approuvee | refusee, commentaire? } -> décision (Simon ou Mike, vérifié par la base)
import { avecSession } from '../../lib/handler.js';
import { approbationsEnAttente, demanderApprobation, deciderApprobation } from '../../lib/modules/devis.js';

export const handler = avecSession({
  GET: ({ repo }) => approbationsEnAttente(repo),
  POST: async ({ repo, corps }) => ({ status: 201, body: await demanderApprobation(repo, corps) }),
  PATCH: ({ repo, corps }) => deciderApprobation(repo, corps),
});
