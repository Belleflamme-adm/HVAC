// GET -> vendeurs du board et employés admissibles | PUT { vendeurs: [{ employe_id, ordre, actif }] } -> board principal
import { avecSession } from '../../lib/handler.js';
import { listerVendeursBoard, majVendeursBoard } from '../../lib/modules/crm.js';

export const handler = avecSession({
  GET: ({ repo }) => listerVendeursBoard(repo),
  PUT: ({ repo, corps }) => majVendeursBoard(repo, corps),
});
