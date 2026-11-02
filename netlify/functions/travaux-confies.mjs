// POST { fournisseur_id, ajouter: [type_travail_id], retirer: [type_travail_id] } -> travaux confiés (Simon, Mike, planification ; RLS)
import { avecSession } from '../../lib/handler.js';
import { confierTravaux } from '../../lib/modules/prix.js';

export const handler = avecSession({ POST: ({ repo, corps }) => confierTravaux(repo, corps) });
