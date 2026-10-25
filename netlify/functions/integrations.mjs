// GET -> { pointage } : branchements actifs avec l'app de Mike, pour adapter les écrans (ADR-086).
// pointage=true : la date de visite vient de Pointage, plus de saisie manuelle dans le lead.
import { avecSession } from '../../lib/handler.js';
import { config } from '../../lib/config.js';

export const handler = avecSession({ GET: () => ({ pointage: config().pointageSyncEnabled }) });
