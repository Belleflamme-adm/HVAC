// Lecture centralisée des variables d'environnement. Aucune valeur secrète par défaut.

export function bool(v, defaut = false) {
  if (v === undefined || v === null || v === '') return defaut;
  return ['1', 'true', 'oui', 'yes', 'on'].includes(String(v).trim().toLowerCase());
}

export function config(env = process.env) {
  return {
    supabaseUrl: env.SUPABASE_URL || '',
    supabaseAnonKey: env.SUPABASE_ANON_KEY || '',
    // Clé service_role : tâches système seulement (purge des photos), jamais dans le navigateur (ADR-084)
    supabaseServiceRoleKey: env.SUPABASE_SERVICE_ROLE_KEY || '',
    // Purge des photos 5 ans après « Terminé » : compte seulement tant que false (ADR-084)
    purgePhotosActif: bool(env.PURGE_PHOTOS_ACTIF),
    dataAdapter: (env.DATA_ADAPTER || 'supabase').toLowerCase(),
    mondayEnabled: bool(env.MONDAY_ENABLED),
    fridaySyncEnabled: bool(env.FRIDAY_SYNC_ENABLED),
    mondayWebhookSecret: env.MONDAY_WEBHOOK_SECRET || '',
    // Téléphonie, textos, courriels et enregistrements par l'app de Mike (ADR-067). Inactif tant que false.
    mikeCommEnabled: bool(env.MIKE_COMM_ENABLED),
    // Visites de Pointage (app de Mike) vers le lead (ADR-086). Inactif tant que false ; secret partagé avec Mike.
    pointageSyncEnabled: bool(env.POINTAGE_SYNC_ENABLED),
    pointageWebhookSecret: env.POINTAGE_WEBHOOK_SECRET || '',
    // Dépôt reçu dans l'app de Mike -> projet à « À céduler » (ADR-087). Inactif tant que false.
    paiementSyncEnabled: bool(env.PAIEMENT_SYNC_ENABLED),
    paiementWebhookSecret: env.PAIEMENT_WEBHOOK_SECRET || '',
    // Appels manqués de la téléphonie de Mike (ADR-090). Inactif tant que false.
    telephonieSyncEnabled: bool(env.TELEPHONIE_SYNC_ENABLED),
    telephonieWebhookSecret: env.TELEPHONIE_WEBHOOK_SECRET || '',
    // Codes d'accès des tuiles protégées : empreintes seulement (scripts/code-acces.mjs), jamais le code (ADR-078)
    codesAcces: { vendeurs: env.CODE_ACCES_VENDEURS || '' },
    appVersion: env.APP_VERSION || '0.4.0',
    // Cookies « Secure » partout sauf en dev local http (netlify dev).
    cookieSecure: !bool(env.NETLIFY_DEV) && env.CONTEXT !== 'dev',
  };
}
