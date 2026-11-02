// GET -> tableau de quantification, chiffres réels par vendeur et cote (bon, moyen, à améliorer)
// PUT { objectifs: [{ indicateur, seuil_bon, seuil_moyen }] } -> board principal seulement (RLS)
import { avecSession } from '../../lib/handler.js';
import { lireRapidite, majObjectifs } from '../../lib/modules/crm.js';

export const handler = avecSession({
  GET: ({ repo }) => lireRapidite(repo),
  PUT: ({ repo, corps }) => majObjectifs(repo, corps),
});
