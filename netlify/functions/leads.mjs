// GET ?vue=mes|board&statut=&vendeur= -> leads (RLS : le vendeur ne voit que les siens)
// POST { succursale_code, contact_nom, contact_tel|contact_courriel, source, ... } -> lead saisi à la main (attribué à tour de rôle)
import { avecSession } from '../../lib/handler.js';
import { listerLeads, creerLead } from '../../lib/modules/crm.js';

export const handler = avecSession({
  GET: async ({ repo, data, token, query }) => {
    const { employe } = await data.session(token);
    return listerLeads(repo, { ...query, employeId: employe?.id });
  },
  POST: async ({ repo, corps }) => ({ status: 201, body: await creerLead(repo, corps) }),
});
