// GET ?fournisseur_id=&de=&a= -> disponibilités (sans fournisseur_id : tous, pour la planification)
// POST { jours: [{ jour, statut: disponible | indisponible | aucun }] } -> par le sous-traitant lui-même
import { avecSession } from '../../lib/handler.js';
import { fournisseurCible, lireDisponibilites, majDisponibilites } from '../../lib/modules/sous-traitants.js';

export const handler = avecSession({
  GET: async ({ repo, data, token, query }) => {
    const { employe } = await data.session(token);
    const cible = employe?.fournisseur_id || query.fournisseur_id || null;
    return lireDisponibilites(repo, cible, query);
  },
  POST: async ({ repo, data, token, corps }) => majDisponibilites(repo, await fournisseurCible(data, token, corps.fournisseur_id), corps),
});
