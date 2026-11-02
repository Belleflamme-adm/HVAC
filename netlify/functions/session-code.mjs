// Connexion par code reçu par courriel (ADR-095), surtout pour les sous-traitants. Même réponse que session-login.
// POST { email }        -> { envoye: true } : un code part SEULEMENT si le compte existe ; la réponse ne le dit pas.
// POST { email, code }  -> { token, user } + cookies HttpOnly.
import { getAdapter } from '../../lib/data/index.js';
import { config } from '../../lib/config.js';
import { json, erreur, lireJson, methode } from '../../lib/http.js';
import { cookiesSession, contratUser } from '../../lib/session.js';

const COURRIEL = /^[^@\s]+@[^@\s]+\.[^@\s]+$/;

export async function handler(event, _context, { adapter } = {}) {
  const refus = methode(event, 'POST');
  if (refus) return refus;
  const corps = lireJson(event);
  const email = String(corps?.email || '').trim().toLowerCase();
  const code = String(corps?.code || '').replace(/\s/g, '');
  if (!COURRIEL.test(email)) return erreur(400, 'champs', 'Courriel requis');

  try {
    const data = adapter || getAdapter();
    if (!code) {
      try { await data.auth.envoyerCode(email, { creer: false }); }
      catch (e) { if (e.status === 429) throw e; }   // compte inconnu : même réponse (on ne révèle pas qui a un compte)
      return json(200, { envoye: true });
    }
    if (!/^\d{6,10}$/.test(code)) return erreur(400, 'champs', 'Le code a 6 chiffres');
    const jetons = await data.auth.verifierCode(email, code);
    const { employe } = await data.session(jetons.accessToken);
    if (!employe) {
      await data.auth.signOut(jetons.accessToken);
      return erreur(403, 'aucun_employe', 'Accès désactivé : communique avec Belleflamme');
    }
    return json(200, { token: jetons.accessToken, user: contratUser(employe) },
      { cookies: cookiesSession(jetons, { secure: config().cookieSecure }) });
  } catch (e) {
    return erreur(e.status || 500, e.code || 'erreur', e.status ? e.message : 'Erreur interne');
  }
}
