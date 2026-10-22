// POST { canal: appel|texto|courriel, coordonnee, client_id? , lead_id? } (ADR-067)
// Branché : l'app de Mike place l'appel ou envoie le message, et la communication revient par communications-webhook.
// Non branché (MIKE_COMM_ENABLED=false) : rend le lien tel:, sms: ou mailto: de l'appareil, rien n'est enregistré.
import { avecSession } from '../../lib/handler.js';
import { config } from '../../lib/config.js';
import { lancer } from '../../lib/modules/communications.js';

export const handler = avecSession({ POST: ({ corps }) => lancer(config(), corps) });
