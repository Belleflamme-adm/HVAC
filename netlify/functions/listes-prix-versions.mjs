// GET ?fournisseur= -> registre des versions de la liste de prix (plus récente en premier) et alerte de fréquence (ADR-065)
// Un sous-traitant reçoit toujours son propre registre ; la RLS le garantit aussi.
import { avecSession } from '../../lib/handler.js';
import { fournisseurCible } from '../../lib/modules/sous-traitants.js';
import { lireRegistre } from '../../lib/modules/prix.js';

export const handler = avecSession({
  GET: async ({ repo, data, token, query }) => lireRegistre(repo, await fournisseurCible(data, token, query.fournisseur)),
});
