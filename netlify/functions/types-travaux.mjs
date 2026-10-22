// PATCH ?id= { nom?, description?, unite?, categorie?, actif? } -> Simon et Mike corrigent une ligne de la liste de prix (RLS)
import { avecSession } from '../../lib/handler.js';
import { modifierTypeTravail } from '../../lib/modules/prix.js';

export const handler = avecSession({ PATCH: ({ repo, query, corps }) => modifierTypeTravail(repo, query.id, corps) });
