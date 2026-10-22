// GET ?id= -> demande, lignes, signature | POST ?id=&action=approuver|annuler
import { avecSession, ErreurValidation } from '../../lib/handler.js';
import { obtenirDemande, approuverDemande, annulerDemande } from '../../lib/modules/prix.js';

export const handler = avecSession({
  GET: async ({ repo, query }) => (await obtenirDemande(repo, query.id)) || { status: 404, body: { error: { code: 'introuvable', message: 'Demande introuvable' } } },
  POST: ({ repo, query }) => {
    if (query.action === 'approuver') return approuverDemande(repo, query.id);
    if (query.action === 'annuler') return annulerDemande(repo, query.id);
    throw new ErreurValidation('Action : approuver ou annuler');
  },
});
