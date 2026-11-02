// GET ?q= -> { produits, kits } actifs (2 caractères minimum)
import { avecSession } from '../../lib/handler.js';
import { chercherCatalogue } from '../../lib/modules/devis.js';

export const handler = avecSession({ GET: ({ repo, query }) => chercherCatalogue(repo, query.q) });
