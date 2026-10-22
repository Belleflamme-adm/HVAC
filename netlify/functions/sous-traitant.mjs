// GET ?id= -> fiche du sous-traitant | PATCH ?id= { nom?, licence_rbq?, responsable_nom?, responsable_telephone?,
// responsable_courriel?, proprietaire_nom?, telephone?, courriel?, adresse?, neq?, actif? } (ADR-064, RLS : planification)
import { avecSession } from '../../lib/handler.js';
import { obtenirSousTraitant, modifierSousTraitant } from '../../lib/modules/sous-traitants.js';

const introuvable = { status: 404, body: { error: { code: 'introuvable', message: 'Sous-traitant introuvable' } } };

export const handler = avecSession({
  GET: async ({ repo, query }) => (await obtenirSousTraitant(repo, query.id)) || introuvable,
  PATCH: ({ repo, query, corps }) => modifierSousTraitant(repo, query.id, corps),
});
