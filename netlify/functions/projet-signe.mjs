// POST { lead_id | client_id, devis_numero_mike, montant_avant_taxes_cents?, type_systeme?, succursale_code? } (ADR-079)
// Soumission signée par le client (dans l'app de Mike) : le projet tombe dans le Macro, le lead passe à Vendu.
// À la greffe, le webhook de Mike remplacera la saisie manuelle.
import { avecSession } from '../../lib/handler.js';
import { recevoirSigne } from '../../lib/modules/macro.js';

export const handler = avecSession({ POST: async ({ repo, corps }) => ({ status: 201, body: await recevoirSigne(repo, corps) }) });
