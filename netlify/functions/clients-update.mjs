// PATCH ?id= { champs à modifier }
import { avecSession } from '../../lib/handler.js';
import { modifierClient } from '../../lib/modules/clients.js';

export const handler = avecSession({ PATCH: ({ repo, query, corps }) => modifierClient(repo, query.id, corps) });
