// GET ?id= -> enregistrement d'un appel : accès vérifié et écoute journalisée par la base, audio servi par l'app de Mike (ADR-067)
import { avecSession } from '../../lib/handler.js';
import { config } from '../../lib/config.js';
import { ecouter } from '../../lib/modules/communications.js';

export const handler = avecSession({ GET: ({ repo, query }) => ecouter(repo, config(), query.id) });
