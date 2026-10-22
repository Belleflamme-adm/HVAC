// Lecture centralisée des variables d'environnement. Aucune valeur secrète par défaut.

export function bool(v, defaut = false) {
  if (v === undefined || v === null || v === '') return defaut;
  return ['1', 'true', 'oui', 'yes', 'on'].includes(String(v).trim().toLowerCase());
}

export function config(env = process.env) {
  return {
    supabaseUrl: env.SUPABASE_URL || '',
    supabaseAnonKey: env.SUPABASE_ANON_KEY || '',
    dataAdapter: (env.DATA_ADAPTER || 'supabase').toLowerCase(),
    mondayEnabled: bool(env.MONDAY_ENABLED),
    fridaySyncEnabled: bool(env.FRIDAY_SYNC_ENABLED),
    mondayWebhookSecret: env.MONDAY_WEBHOOK_SECRET || '',
    appVersion: env.APP_VERSION || '0.3.0',
    // Cookies « Secure » partout sauf en dev local http (netlify dev).
    cookieSecure: !bool(env.NETLIFY_DEV) && env.CONTEXT !== 'dev',
  };
}
