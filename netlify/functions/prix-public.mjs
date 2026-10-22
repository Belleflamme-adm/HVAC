// Page publique du sous-traitant (SANS compte) : le jeton arrive dans l'en-tête X-Jeton (lu du fragment # du lien).
// GET -> liste à remplir | POST { lignes, nom, signature, atteste } -> soumission signée, une seule fois.
// Aucune clé secrète : clé publique seulement ; la base vérifie le jeton (fonctions hvac_demande_prix_*).
import { getAdapter } from '../../lib/data/index.js';
import { json, erreur, lireJson } from '../../lib/http.js';
import { lirePublique, soumettrePublique } from '../../lib/modules/prix.js';

export async function handler(event, _context, { adapter } = {}) {
  if (!['GET', 'POST'].includes(event.httpMethod)) return erreur(405, 'methode', `Méthode ${event.httpMethod} non permise`);
  const h = event.headers || {};
  const jeton = h['x-jeton'] || h['X-Jeton'] || '';
  try {
    const repo = (adapter || getAdapter()).repo(null);
    if (event.httpMethod === 'GET') return json(200, await lirePublique(repo, jeton));
    const corps = lireJson(event);
    if (corps === null) return erreur(400, 'json', 'Corps JSON invalide');
    return json(200, await soumettrePublique(repo, jeton, corps));
  } catch (e) {
    if (e.status) return erreur(e.status, e.code || 'erreur', e.message);
    console.error(e);
    return erreur(500, 'erreur', 'Erreur interne');
  }
}
