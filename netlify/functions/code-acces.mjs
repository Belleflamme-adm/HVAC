// POST { zone: 'vendeurs', code } -> { ok } | 403 code incorrect ou rôle non permis | 503 code non configuré (ADR-078)
import { avecSession } from '../../lib/handler.js';
import { config } from '../../lib/config.js';
import { verifierAcces } from '../../lib/modules/codes.js';

export const handler = avecSession({ POST: ({ data, token, corps }) => verifierAcces(data, token, config(), corps) });
