// Enveloppe commune des fonctions métier : méthode, session, corps JSON, erreurs.
// La RLS fait l'autorisation : la fonction passe seulement le jeton de l'utilisateur.
import { getAdapter } from './data/index.js';
import { json, erreur, lireJson } from './http.js';
import { jetonDepuis } from './session.js';

export class ErreurValidation extends Error {
  constructor(message) { super(message); this.status = 400; this.code = 'validation'; }
}

export function avecSession(routes) {
  return async function handler(event, _context, { adapter } = {}) {
    const route = routes[event.httpMethod];
    if (!route) {
      return json(405, { error: { code: 'methode', message: `Méthode ${event.httpMethod} non permise` } },
                  { headers: { Allow: Object.keys(routes).join(', ') } });
    }
    const token = jetonDepuis(event);
    if (!token) return erreur(401, 'non_connecte', 'Non connecté');
    let corps = {};
    if (event.httpMethod !== 'GET') {
      corps = lireJson(event);
      if (corps === null) return erreur(400, 'json', 'Corps JSON invalide');
    }
    try {
      const data = adapter || getAdapter();
      const resultat = await route({
        event, corps, query: event.queryStringParameters || {}, repo: data.repo(token), data, token,
      });
      return json(resultat?.status || 200, resultat?.status ? resultat.body : resultat);
    } catch (e) {
      if (e.status) return erreur(e.status, e.code || 'erreur', e.message);
      console.error(e);
      return erreur(500, 'erreur', 'Erreur interne');
    }
  };
}

// Garde seulement les champs permis ; refuse les champs requis manquants.
export function choisir(source, permis, requis = []) {
  const out = {};
  for (const k of permis) if (source?.[k] !== undefined) out[k] = source[k];
  for (const k of requis) {
    if (out[k] === undefined || out[k] === null || out[k] === '') throw new ErreurValidation(`Champ requis : ${k}`);
  }
  return out;
}

export const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
export function uuid(v, nom = 'id') {
  if (!UUID.test(String(v || ''))) throw new ErreurValidation(`${nom} invalide`);
  return v;
}
