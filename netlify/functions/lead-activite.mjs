// POST ?id= { type: prise_en_charge|appel|courriel|texto|note|visite_planifiee|perdu|reouvert, resultat?, note?, visite_le? }
// L'heure est fixée par la base ; le geste est attribué à l'employé connecté.
import { avecSession } from '../../lib/handler.js';
import { ajouterActivite } from '../../lib/modules/crm.js';

export const handler = avecSession({
  POST: async ({ repo, data, token, query, corps }) => {
    const { employe } = await data.session(token);
    return { status: 201, body: await ajouterActivite(repo, query.id, employe?.id, corps) };
  },
});
