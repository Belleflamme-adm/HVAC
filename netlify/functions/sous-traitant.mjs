// GET ?id= -> fiche du sous-traitant | PATCH ?id= { nom?, licence_rbq?, responsable_nom?, responsable_telephone?,
// responsable_courriel?, proprietaire_nom?, telephone?, courriel?, adresse?, neq?, actif? } (ADR-064, RLS : planification)
// GET ?id=&vue=acces -> état de l'accès | POST ?id= { action: envoyer | couper | retablir } (ADR-095, planification)
import { avecSession } from '../../lib/handler.js';
import { obtenirSousTraitant, modifierSousTraitant, lireAcces, gererAcces } from '../../lib/modules/sous-traitants.js';

const introuvable = { status: 404, body: { error: { code: 'introuvable', message: 'Sous-traitant introuvable' } } };

export const handler = avecSession({
  GET: async ({ repo, query }) => (query.vue === 'acces' ? lireAcces(repo, query.id) : (await obtenirSousTraitant(repo, query.id)) || introuvable),
  PATCH: ({ repo, query, corps }) => modifierSousTraitant(repo, query.id, corps),
  POST: ({ repo, data, query, corps }) => gererAcces(repo, data.auth, query.id, corps.action),
});
