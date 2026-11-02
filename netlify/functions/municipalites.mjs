// GET ?q= -> municipalités (2 lettres min.) | GET ?pour=<code> -> sous-traitants qui desservent cette municipalité
import { avecSession } from '../../lib/handler.js';
import { chercherMunicipalites, sousTraitantsPour } from '../../lib/modules/sous-traitants.js';

export const handler = avecSession({
  GET: ({ repo, query }) => (query.pour ? sousTraitantsPour(repo, query.pour) : chercherMunicipalites(repo, query.q)),
});
