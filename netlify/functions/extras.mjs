// Feuille d'extra du sous-traitant (ADR-081)
// GET [?statut=soumis|tous] [?projet=] -> file d'approbation (Belleflamme)
// POST ?projet= { type_travail_id | description+cout_cents+justification, quantite, cause, note? } -> extra en brouillon (sous-traitant)
// PATCH { action: retirer|envoyer|decider|facture, id?, projet?, approuve?, raison? }
import { avecSession } from '../../lib/handler.js';
import { listerExtras, ajouterExtra, geste } from '../../lib/modules/extras.js';

export const handler = avecSession({
  GET: ({ repo, query }) => listerExtras(repo, query),
  POST: async ({ repo, query, corps }) => ({ status: 201, body: await ajouterExtra(repo, query.projet, corps) }),
  PATCH: ({ repo, corps }) => geste(repo, corps),
});
