// GET ?fournisseur= -> demandes de prix | POST { fournisseur_id, types: [uuid], message? } -> { id, lien, expire_le }
// Le lien contient le jeton une seule fois : il n'est jamais relu ensuite (la base ne garde que son empreinte).
import { avecSession } from '../../lib/handler.js';
import { listerDemandes, creerDemande, baseUrl } from '../../lib/modules/prix.js';

export const handler = avecSession({
  GET: ({ repo, query }) => listerDemandes(repo, query),
  POST: async ({ repo, corps, event }) => ({ status: 201, body: await creerDemande(repo, corps, baseUrl(event)) }),
});
