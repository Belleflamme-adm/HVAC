// PATCH ?id= { site_id, mode_paiement, depot_bp, notes_client, notes_internes } (brouillon seulement pour le dépôt)
import { avecSession } from '../../lib/handler.js';
import { modifierDevis } from '../../lib/modules/devis.js';

export const handler = avecSession({ PATCH: ({ repo, query, corps }) => modifierDevis(repo, query.id, corps) });
