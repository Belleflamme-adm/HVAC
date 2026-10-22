// Webhook app de Mike -> HVAC : chaque appel (heure, durée, enregistrement, transcription), texto et courriel. INACTIF.
// Répond 503 tant que MIKE_COMM_ENABLED=false (CLAUDE.md §5), puis 501 tant que le contrat avec Mike n'est pas fixé :
// format des données, signature du webhook, endroit où l'audio est conservé (docs/MIGRATION.md, ADR-067).
import { config } from '../../lib/config.js';
import { erreur, methode } from '../../lib/http.js';

export async function handler(event) {
  const refus = methode(event, 'POST');
  if (refus) return refus;
  if (!config().mikeCommEnabled) return erreur(503, 'desactive', 'Communications de l\'app de Mike désactivées (MIKE_COMM_ENABLED=false)');
  return erreur(501, 'non_implemente', 'Contrat du webhook à fixer avec Mike (docs/MIGRATION.md)');
}
