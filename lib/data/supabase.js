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

const estJwtExpire = (error) => error.code === 'PGRST301' || /jwt/i.test(String(error.message || ''));

function normaliser(error, statusParDefaut = 400) {
  if (!error) return null;
  if (estJwtExpire(error)) return new DataError('session_expiree', 'Session expirée', 401);
  // 42501 : droits ou RLS ; P0001 : règle métier ; P0002 : introuvable ; 23xxx : contrainte
  const status = error.code === '42501' ? 403 : error.code === 'P0002' ? 404
    : error.code === 'P0001' || String(error.code || '').startsWith('23') ? 422 : (error.status || statusParDefaut);
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
        if (estJwtExpire(error)) {
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
        // filtre : { col: valeur } (égalité) ou { col: { op: 'in'|'gte'|'lte'|'neq'|'is', val } }
        // recherche : { colonnes: ['nom','courriel'], terme } (ilike, OU entre colonnes)
        async list(table, { select = '*', filtre = {}, recherche, ordre, limite = 100 } = {}) {
          let q = c.from(table).select(select).limit(Math.min(limite, 500));
          for (const [k, v] of Object.entries(filtre)) {
            if (v && typeof v === 'object' && v.op) q = q[v.op](k, v.val);
            else q = q.eq(k, v);
          }
          if (recherche?.terme) {
            const t = String(recherche.terme).replace(/[%,()*]/g, ' ').trim();
            if (t) q = q.or(recherche.colonnes.map((col) => `${col}.ilike.*${t}*`).join(','));
          }
          if (ordre) q = q.order(ordre.colonne, { ascending: ordre.asc !== false });
          return unwrap(await q);
        },
        async get(table, id, { select = '*' } = {}) { return unwrap(await c.from(table).select(select).eq('id', id).maybeSingle()); },
        async insert(table, ligne) { return unwrap(await c.from(table).insert(ligne).select().single()); },
        async update(table, id, patch) { return unwrap(await c.from(table).update(patch).eq('id', id).select().single()); },
        async updateWhere(table, filtre, patch) {
          let q = c.from(table).update(patch);
          for (const [k, v] of Object.entries(filtre)) q = q.eq(k, v);
          const lignes = unwrap(await q.select());
          if (!lignes.length) throw new DataError('refuse', 'Modification refusée (droits insuffisants)', 403);
          return lignes[0];
        },
        async upsert(table, lignes, { onConflict } = {}) {
          return unwrap(await c.from(table).upsert(lignes, { onConflict }).select());
        },
        async removeWhere(table, filtre) {
          let q = c.from(table).delete();
          for (const [k, v] of Object.entries(filtre)) q = Array.isArray(v) ? q.in(k, v) : q.eq(k, v);
          return unwrap(await q.select());
        },
        async remove(table, id) { return unwrap(await c.from(table).delete().eq('id', id).select()); },
        async rpc(fn, args) { return unwrap(await c.rpc(fn, args)); },
        // Fichiers (Supabase Storage) avec le jeton de l'utilisateur : la RLS de storage.objects s'applique
        async televerser(bucket, chemin, octets, type) {
          const { error } = await c.storage.from(bucket).upload(chemin, octets, { contentType: type, upsert: false });
          if (error) throw normaliser(error, 403);
        },
        async urlsSignees(bucket, chemins, secondes = 600) {
          if (!chemins.length) return [];
          return unwrap(await c.storage.from(bucket).createSignedUrls(chemins, secondes)).map((x) => x.signedUrl);
        },
      };
    },
  };
}
