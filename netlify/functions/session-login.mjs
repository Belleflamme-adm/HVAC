// POST { email, password } -> { token, user } + cookies HttpOnly. Même contrat que chez Mike.
import { getAdapter } from '../../lib/data/index.js';
import { config } from '../../lib/config.js';
import { json, erreur, lireJson, methode } from '../../lib/http.js';
import { cookiesSession, contratUser } from '../../lib/session.js';

export async function handler(event, _context, { adapter } = {}) {
  const refus = methode(event, 'POST');
  if (refus) return refus;
  const corps = lireJson(event);
  const email = String(corps?.email || '').trim().toLowerCase();
  const password = String(corps?.password || '');
  if (!email || !password) return erreur(400, 'champs', 'Courriel et mot de passe requis');

  try {
    const data = adapter || getAdapter();
    const jetons = await data.auth.signIn(email, password);
    const { employe } = await data.session(jetons.accessToken);
    if (!employe) {
      await data.auth.signOut(jetons.accessToken);
      return erreur(403, 'aucun_employe', 'Ce compte n\'est lié à aucun employé actif');
    }
    return json(200, { token: jetons.accessToken, user: contratUser(employe) },
      { cookies: cookiesSession(jetons, { secure: config().cookieSecure }) });
  } catch (e) {
    return erreur(e.status || 500, e.code || 'erreur', e.status ? e.message : 'Erreur interne');
  }
}
