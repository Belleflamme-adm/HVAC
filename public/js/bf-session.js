// Session côté navigateur, contrat de Mike : { token, user }.
// Le jeton reste EN MÉMOIRE seulement : le cookie HttpOnly bf_session fait foi.
// Rien d'identifiant n'est écrit dans localStorage ni sessionStorage (CLAUDE.md §3).

let courant = null;

async function appel(fn, options = {}) {
  const r = await fetch(`/.netlify/functions/${fn}${options.query || ''}`, {
    method: options.method || 'GET',
    credentials: 'same-origin',
    headers: options.body ? { 'Content-Type': 'application/json' } : {},
    body: options.body ? JSON.stringify(options.body) : undefined,
  });
  const data = await r.json().catch(() => ({}));
  if (!r.ok) throw Object.assign(new Error(data?.error?.message || `Erreur ${r.status}`), { status: r.status, code: data?.error?.code });
  return data;
}

export async function login(email, password) {
  courant = await appel('session-login', { method: 'POST', body: { email, password } });
  return courant.user;
}

// Connexion par code reçu par courriel (ADR-095)
export async function demanderCode(email) {
  await appel('session-code', { method: 'POST', body: { email } });
}

export async function connecterCode(email, code) {
  courant = await appel('session-code', { method: 'POST', body: { email, code } });
  return courant.user;
}

export async function me() {
  try {
    courant = await appel('session-me');
    return courant.user;
  } catch (e) {
    if (e.status === 401) { courant = null; return null; }
    throw e;
  }
}

export async function impersonate(employeId) {
  courant = await appel('session-me', { query: `?impersonate=${encodeURIComponent(employeId)}` });
  return courant.user;
}

export async function logout() {
  try { await appel('session-logout', { method: 'POST' }); } finally { courant = null; }
}

export const user = () => courant?.user ?? null;

// Garde de page : redirige vers /login (pretty URL) si personne n'est connecté.
export async function exigerSession() {
  const u = await me();
  if (!u) {
    location.replace(`/login?retour=${encodeURIComponent(location.pathname)}`);
    return null;
  }
  return u;
}

export { appel };
