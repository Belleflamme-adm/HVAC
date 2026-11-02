// GET -> sous-traitant principal par municipalité | POST { municipalite_code, fournisseur_id | null } (planification)
import { avecSession } from '../../lib/handler.js';
import { lirePrincipaux, designerPrincipal } from '../../lib/modules/sous-traitants.js';

export const handler = avecSession({
  GET: ({ repo }) => lirePrincipaux(repo),
  POST: ({ repo, corps }) => designerPrincipal(repo, corps),
});
