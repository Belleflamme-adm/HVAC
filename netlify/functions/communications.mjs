// GET ?client_id= | ?lead_id= [&canal=] -> appels, textos et courriels du client (plus récents d'abord) (ADR-067)
// Tous les employés de Belleflamme, sauf les sous-traitants (RLS).
import { avecSession } from '../../lib/handler.js';
import { listerCommunications } from '../../lib/modules/communications.js';

export const handler = avecSession({ GET: ({ repo, query }) => listerCommunications(repo, query) });
