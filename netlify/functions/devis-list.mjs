// GET ?statut=&client_id=&vendeur_id= -> devis visibles (vue devis_v, statut_effectif inclut « expire »)
import { avecSession } from '../../lib/handler.js';
import { listerDevis } from '../../lib/modules/devis.js';

export const handler = avecSession({ GET: ({ repo, query }) => listerDevis(repo, query) });
