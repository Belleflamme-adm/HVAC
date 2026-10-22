// Adapter actif : projet Supabase HVAC dédié. Utilise UNIQUEMENT la clé publique (anon)
// et le JWT de l'utilisateur : la RLS s'applique à chaque requête (ADR-020).
import { createClient } from '@supabase/supabase-js';
import { DataError } from './erreurs.js';

const OPTIONS_AUTH = { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false };

function verifierConfig(cfg) {
  if (!cfg.supabaseUrl || !cfg.supabaseAnonKey) {
    throw new DataError('config_manquante', 'SUPABASE_URL et SUPABASE_ANON_KEY doivent être définis', 503);
  }
}

function normaliser(error, statusParDefaut = 400) {
  if (!error) return null;
  const status = error.status || (error.code === '42501' ? 403 : statusParDefaut);
  return new DataError(error.code || 'supabase', error.message || 'Erreur Supabase', status);
}

export function creerAdapterSupabase(cfg, { createClientImpl = createClient } = {}) {
  const client = (accessToken) => {
    verifierConfig(cfg);
    return createClientImpl(cfg.supabaseUrl, cfg.supabaseAnonKey, {
      auth: OPTIONS_AUTH,
      global: accessToken ? { headers: { Authorization: `Bearer ${accessToken}` } } : {},
    });
  };

  const jetons = (s) => ({
    accessToken: s.access_token,
    refreshToken: s.refresh_token,
    expiresIn: s.expires_in,
  });

  return {
    nom: 'supabase',
    auth: {
      async signIn(email, motDePasse) {
        const { data, error } = await client().auth.signInWithPassword({ email, password: motDePasse });
        if (error) throw new DataError('identifiants', 'Courriel ou mot de passe invalide', 401);
        return jetons(data.session);
      },
      async refresh(refreshToken) {
        const { data, error } = await client().auth.refreshSession({ refresh_token: refreshToken });
        if (error || !data.session) throw new DataError('session_expiree', 'Session expirée', 401);
        return jetons(data.session);
      },
      async signOut(accessToken) {
        // POST /auth/v1/logout avec le JWT de l'utilisateur (pas la clé service_role) :
        // révoque le refresh token de cette session. Une erreur ici n'empêche pas la déconnexion locale.
        try { await client().auth.admin.signOut(accessToken, 'local'); } catch { /* déconnexion locale quand même */ }
      },
    },
    async session(accessToken) {
      const { data, error } = await client(accessToken).rpc('hvac_session');
      if (error) {
        if (String(error.message || '').toLowerCase().includes('jwt')) {
          throw new DataError('session_expiree', 'Session expirée', 401);
        }
        throw normaliser(error, 500);
      }
      return { employe: data || null };
    },
    repo(accessToken) {
      const c = client(accessToken);
      const unwrap = ({ data, error }) => { if (error) throw normaliser(error); return data; };
      return {
        async list(table, { filtre = {}, ordre, limite = 100 } = {}) {
          let q = c.from(table).select('*').limit(limite);
          for (const [k, v] of Object.entries(filtre)) q = q.eq(k, v);
          if (ordre) q = q.order(ordre.colonne, { ascending: ordre.asc !== false });
          return unwrap(await q);
        },
        async get(table, id) { return unwrap(await c.from(table).select('*').eq('id', id).maybeSingle()); },
        async insert(table, ligne) { return unwrap(await c.from(table).insert(ligne).select().single()); },
        async update(table, id, patch) { return unwrap(await c.from(table).update(patch).eq('id', id).select().single()); },
        async rpc(fn, args) { return unwrap(await c.rpc(fn, args)); },
      };
    },
  };
}
