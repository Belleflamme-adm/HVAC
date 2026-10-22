// Contrat d'auth identique à l'app de Mike (CLAUDE.md §3) :
//   { token, user: { id, itemId, email, name, role, masterImpersonation } }
// Le jeton voyage dans un cookie HttpOnly (jamais dans localStorage ni sessionStorage).
// Il est aussi renvoyé dans le corps pour respecter le contrat ; le front le garde en mémoire seulement.
import { cookie, lireCookies, bearer } from './http.js';

export const COOKIE_ACCES = 'bf_session';
export const COOKIE_REFRESH = 'bf_refresh';
const CHEMIN_REFRESH = '/.netlify/functions';
const TRENTE_JOURS = 30 * 24 * 3600;

export function jetonDepuis(event) {
  return bearer(event) || lireCookies(event)[COOKIE_ACCES] || '';
}

export function refreshDepuis(event) {
  return lireCookies(event)[COOKIE_REFRESH] || '';
}

export function cookiesSession(jetons, { secure }) {
  return [
    cookie(COOKIE_ACCES, jetons.accessToken, { maxAge: jetons.expiresIn, secure }),
    cookie(COOKIE_REFRESH, jetons.refreshToken, { maxAge: TRENTE_JOURS, path: CHEMIN_REFRESH, secure }),
  ];
}

export function cookiesEffaces({ secure }) {
  return [
    cookie(COOKIE_ACCES, '', { maxAge: 0, secure }),
    cookie(COOKIE_REFRESH, '', { maxAge: 0, path: CHEMIN_REFRESH, secure }),
  ];
}

export function contratUser(employe, impersonePar = null) {
  return {
    id: employe.id,
    itemId: employe.monday_item_id ?? null,
    email: employe.email,
    name: `${employe.prenom} ${employe.nom}`.trim(),
    role: employe.role,
    succursale: employe.succursale_code,
    masterImpersonation: impersonePar
      ? { id: impersonePar.id, name: `${impersonePar.prenom} ${impersonePar.nom}`.trim() }
      : null,
  };
}
