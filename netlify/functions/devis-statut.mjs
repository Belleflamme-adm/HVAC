// POST { id, statut: envoye | accepte | refuse | annule, raison_refus? }
// La base refuse : envoi avec rabais non approuvé, devis vide, acceptation d'un devis expiré.
import { avecSession } from '../../lib/handler.js';
import { changerStatut } from '../../lib/modules/devis.js';

export const handler = avecSession({ POST: ({ repo, corps }) => changerStatut(repo, corps) });
