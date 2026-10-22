// Admin (Simon, Mike ; vérifié par la RLS) :
//   POST { fournisseur_id, type_travail_id, cout_cents, en_vigueur_du? } -> nouveau tarif daté
//   PATCH { marge_bp }                                                   -> taux de marge unique
//   PUT { code, nom, description? }                                     -> nouveau type de travail
import { avecSession } from '../../lib/handler.js';
import { ajouterTarif, changerMarge, ajouterTypeTravail } from '../../lib/modules/devis.js';

export const handler = avecSession({
  POST: async ({ repo, corps }) => ({ status: 201, body: await ajouterTarif(repo, corps) }),
  PATCH: ({ repo, corps }) => changerMarge(repo, corps),
  PUT: async ({ repo, corps }) => ({ status: 201, body: await ajouterTypeTravail(repo, corps) }),
});
