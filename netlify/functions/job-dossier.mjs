// Dossier de job LogisVert (ADR-084)
// GET ?projet= -> { numero_ahri, equipements, photos [{ id, equipement_id, categorie, url }], manques }
// POST ?projet= { action: 'equipement', role, marque, modele, numero_serie } | { action: 'photo', equipement_id?, categorie, type, donnees }
// PATCH { action: 'ahri', projet, numero_ahri } | { action: 'retirer_equipement' | 'retirer_photo', id }
import { avecSession } from '../../lib/handler.js';
import { lireDossier, ajouterAuDossier, modifierDossier } from '../../lib/modules/dossier.js';

export const handler = avecSession({
  GET: ({ repo, query }) => lireDossier(repo, query.projet),
  POST: async ({ repo, query, corps }) => ({ status: 201, body: await ajouterAuDossier(repo, query.projet, corps) }),
  PATCH: ({ repo, corps }) => modifierDossier(repo, corps),
});
