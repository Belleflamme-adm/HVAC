// Synchro Friday (miroir Supabase de Mike). INACTIF : 503 tant que FRIDAY_SYNC_ENABLED=false.
import { config } from '../../lib/config.js';
import { erreur, methode } from '../../lib/http.js';

export async function handler(event) {
  const refus = methode(event, 'POST');
  if (refus) return refus;
  if (!config().fridaySyncEnabled) return erreur(503, 'desactive', 'Synchro Friday désactivée (FRIDAY_SYNC_ENABLED=false)');
  return erreur(501, 'non_implemente', 'Synchro Friday à implémenter lors de la migration');
}
