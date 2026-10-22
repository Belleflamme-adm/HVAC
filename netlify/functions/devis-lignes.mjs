// POST { devis_id, produit_id | kit_id | description+prix_unitaire_cents, quantite, rabais_bp }
// PATCH ?id= { quantite, rabais_bp, ... } | DELETE ?id=   (devis en brouillon seulement)
import { avecSession } from '../../lib/handler.js';
import { ajouterLigne, modifierLigne, retirerLigne } from '../../lib/modules/devis.js';

export const handler = avecSession({
  POST: async ({ repo, corps }) => ({ status: 201, body: await ajouterLigne(repo, corps) }),
  PATCH: ({ repo, query, corps }) => modifierLigne(repo, query.id, corps),
  DELETE: ({ repo, query }) => retirerLigne(repo, query.id),
});
