// GET -> état de l'app, sans aucun secret. Utile pour vérifier un déploiement.
import { config } from '../../lib/config.js';
import { json } from '../../lib/http.js';

export async function handler() {
  const c = config();
  return json(200, {
    ok: true,
    version: c.appVersion,
    adapter: c.dataAdapter,
    supabaseConfigure: Boolean(c.supabaseUrl && c.supabaseAnonKey),
    mondayEnabled: c.mondayEnabled,
    fridaySyncEnabled: c.fridaySyncEnabled,
  });
}
