// Webhook Monday -> HVAC, sur le modèle de monday-webhook-sync chez Mike. INACTIF.
// Répond 503 tant que MONDAY_ENABLED=false (CLAUDE.md §5).
// Une fois activé : répond au « challenge » de vérification de Monday (à revalider dans la
// doc officielle de Monday au moment de l'activation), puis 501 tant que le mapping n'est pas fait.
import { config } from '../../lib/config.js';
import { json, erreur, lireJson, methode } from '../../lib/http.js';

export async function handler(event) {
  const refus = methode(event, 'POST');
  if (refus) return refus;
  const cfg = config();
  if (!cfg.mondayEnabled) return erreur(503, 'desactive', 'Synchro Monday désactivée (MONDAY_ENABLED=false)');
  const corps = lireJson(event);
  if (corps && typeof corps.challenge === 'string') return json(200, { challenge: corps.challenge });
  return erreur(501, 'non_implemente', 'Mapping Monday à compléter (docs/MAPPING.md)');
}
