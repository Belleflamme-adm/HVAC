// GET ?fournisseur_id= -> territoire | GET ?tous=1 -> tous les territoires desservis (Belleflamme) | POST { fournisseur_id?, municipalites: [...], statut, supplement_cents? }
// Un sous-traitant agit toujours sur son propre territoire.
import { avecSession } from '../../lib/handler.js';
import { fournisseurCible, lireTerritoire, lireTousTerritoires, majTerritoire } from '../../lib/modules/sous-traitants.js';

export const handler = avecSession({
  GET: async ({ repo, data, token, query }) => (query.tous
    ? lireTousTerritoires(repo, data, token)
    : lireTerritoire(repo, await fournisseurCible(data, token, query.fournisseur_id))),
  POST: async ({ repo, data, token, corps }) => majTerritoire(repo, await fournisseurCible(data, token, corps.fournisseur_id), corps),
});
