// GET ?q=&succursale=&limite= -> clients visibles (RLS : succursales de l'employé)
import { avecSession } from '../../lib/handler.js';
import { listerClients } from '../../lib/modules/clients.js';

export const handler = avecSession({ GET: ({ repo, query }) => listerClients(repo, query) });
