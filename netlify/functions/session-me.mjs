// GET -> { token, user }. Rafraîchit la session avec le cookie de refresh si le jeton est expiré.
// ?impersonate=<employe_id> : réservé à « Admin tout », journalisé (masterImpersonation).
import { getAdapter } from '../../lib/data/index.js';
import { config } from '../../lib/config.js';
import { json, erreur, methode } from '../../lib/http.js';
import { jetonDepuis, refreshDepuis, cookiesSession, cookiesEffaces, contratUser } from '../../lib/session.js';

export async function handler(event, _context, { adapter } = {}) {
  const refus = methode(event, 'GET');
  if (refus) return refus;
  const secure = config().cookieSecure;
  let token = jetonDepuis(event);
  const refresh = refreshDepuis(event);
  if (!token && !refresh) return erreur(401, 'non_connecte', 'Non connecté');

  try {
    const data = adapter || getAdapter();
    let cookies = [];
    let employe = null;
    try {
      if (!token) throw Object.assign(new Error('expire'), { status: 401 });
      ({ employe } = await data.session(token));
    } catch (e) {
      if (e.status !== 401 || !refresh) throw e;
      const jetons = await data.auth.refresh(refresh);
      token = jetons.accessToken;
      cookies = cookiesSession(jetons, { secure });
      ({ employe } = await data.session(token));
    }
    if (!employe) return json(401, { error: { code: 'non_connecte', message: 'Non connecté' } }, { cookies: cookiesEffaces({ secure }) });

    const cible = event.queryStringParameters?.impersonate;
    if (cible) {
      const impersonne = await data.repo(token).rpc('hvac_impersonation', { p_employe: cible });
      return json(200, { token, user: contratUser(impersonne, employe) }, { cookies });
    }
    return json(200, { token, user: contratUser(employe) }, { cookies });
  } catch (e) {
    if (e.status === 401) {
      return json(401, { error: { code: 'session_expiree', message: 'Session expirée' } }, { cookies: cookiesEffaces({ secure }) });
    }
    return erreur(e.status || 500, e.code || 'erreur', e.status ? e.message : 'Erreur interne');
  }
}
