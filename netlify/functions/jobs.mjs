// GET [?fournisseur=] -> Mes jobs du sous-traitant (ADR-080) : projets signés, machines à 0 $, son prix d'installation seulement.
// Un sous-traitant voit toujours ses jobs ; Simon, Mike et la planification peuvent voir celles d'un sous-traitant.
import { avecSession } from '../../lib/handler.js';
import { mesJobs } from '../../lib/modules/macro.js';

export const handler = avecSession({
  GET: async ({ repo, data, token, query }) => {
    const { employe } = await data.session(token);
    return mesJobs(repo, employe?.fournisseur_id ? null : query.fournisseur);
  },
});
