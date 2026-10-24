// GET [?succursale=&vendeur=&fermes=1&lead=] -> projets HVAC du Macro | PATCH ?id= { statut } -> changer d'étape (ADR-079)
import { avecSession } from '../../lib/handler.js';
import { listerProjets, changerEtape } from '../../lib/modules/macro.js';

export const handler = avecSession({
  GET: ({ repo, query }) => listerProjets(repo, query),
  PATCH: ({ repo, query, corps }) => changerEtape(repo, query.id, corps),
});
