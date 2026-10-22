// GET -> { types, sousTraitants, grille, margeBp } pour ajouter une installation à un devis
import { avecSession } from '../../lib/handler.js';
import { optionsInstallation } from '../../lib/modules/devis.js';

export const handler = avecSession({ GET: ({ repo }) => optionsInstallation(repo) });
