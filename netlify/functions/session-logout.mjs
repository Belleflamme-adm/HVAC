// POST -> efface les cookies et révoque la session côté Supabase.
import { getAdapter } from '../../lib/data/index.js';
import { config } from '../../lib/config.js';
import { json, methode } from '../../lib/http.js';
import { jetonDepuis, cookiesEffaces } from '../../lib/session.js';

export async function handler(event, _context, { adapter } = {}) {
  const refus = methode(event, 'POST');
  if (refus) return refus;
  const token = jetonDepuis(event);
  if (token) {
    try { await (adapter || getAdapter()).auth.signOut(token); } catch { /* on déconnecte quand même */ }
  }
  return json(200, { ok: true }, { cookies: cookiesEffaces({ secure: config().cookieSecure }) });
}
