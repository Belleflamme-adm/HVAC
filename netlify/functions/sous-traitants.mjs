// GET -> sous-traitants | POST { nom, telephone?, courriel?, contact: { prenom, nom, email } } -> fournisseur + compte
// (Création : planification seulement, vérifiée par la RLS. Le compte se connecte après invitation Supabase Auth.)
import { avecSession } from '../../lib/handler.js';
import { listerSousTraitants, creerSousTraitant } from '../../lib/modules/sous-traitants.js';

export const handler = avecSession({
  GET: ({ repo }) => listerSousTraitants(repo),
  POST: async ({ repo, corps }) => ({ status: 201, body: await creerSousTraitant(repo, corps) }),
});
