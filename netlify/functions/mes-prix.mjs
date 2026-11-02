// GET ?fournisseur= -> travaux confiés, prix en vigueur, engagements (devis actifs à honorer)
// POST { prix: [{ type_travail_id, cout_cents }], fournisseur_id? } -> nouveaux prix (nouveaux devis seulement)
// Un sous-traitant agit toujours sur son entreprise ; Simon, Mike et la planification choisissent le sous-traitant.
import { avecSession } from '../../lib/handler.js';
import { lireMesPrix, majMesPrix } from '../../lib/modules/prix.js';

const cible = async (data, token, demande) => {
  const { employe } = await data.session(token);
  return employe?.fournisseur_id || demande;
};

export const handler = avecSession({
  GET: async ({ repo, data, token, query }) => lireMesPrix(repo, await cible(data, token, query.fournisseur)),
  POST: async ({ repo, data, token, corps }) => {
    const { employe } = await data.session(token);
    return majMesPrix(repo, employe?.fournisseur_id ? null : corps.fournisseur_id, corps);
  },
});
