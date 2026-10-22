// Helpers HTTP communs aux Netlify Functions (format handler(event)).

export function json(statusCode, body, extra = {}) {
  const { cookies, headers } = extra;
  const res = {
    statusCode,
    headers: { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store', ...headers },
    body: JSON.stringify(body),
  };
  if (cookies && cookies.length) res.multiValueHeaders = { 'Set-Cookie': cookies };
  return res;
}

export const erreur = (statusCode, code, message) => json(statusCode, { error: { code, message } });

export function lireJson(event) {
  if (!event.body) return {};
  const brut = event.isBase64Encoded ? Buffer.from(event.body, 'base64').toString('utf8') : event.body;
  try { return JSON.parse(brut); } catch { return null; }
}

export function lireCookies(event) {
  const h = event.headers || {};
  const brut = h.cookie || h.Cookie || '';
  const out = {};
  for (const part of brut.split(';')) {
    const i = part.indexOf('=');
    if (i > 0) out[part.slice(0, i).trim()] = decodeURIComponent(part.slice(i + 1).trim());
  }
  return out;
}

export function cookie(nom, valeur, { maxAge, path = '/', secure = true } = {}) {
  const parts = [`${nom}=${encodeURIComponent(valeur)}`, `Path=${path}`, 'HttpOnly', 'SameSite=Lax'];
  if (secure) parts.push('Secure');
  if (maxAge !== undefined) parts.push(`Max-Age=${Math.max(0, Math.floor(maxAge))}`);
  return parts.join('; ');
}

export function bearer(event) {
  const h = event.headers || {};
  const a = h.authorization || h.Authorization || '';
  return a.startsWith('Bearer ') ? a.slice(7).trim() : '';
}

export function methode(event, ...permises) {
  return permises.includes(event.httpMethod) ? null
    : json(405, { error: { code: 'methode', message: `Méthode ${event.httpMethod} non permise` } },
           { headers: { Allow: permises.join(', ') } });
}
