// Codes d'accès des tuiles protégées (ADR-078). Le code n'est JAMAIS écrit dans le repo : on ne garde que son
// empreinte PBKDF2-SHA256 (variable d'environnement côté serveur, injectée au build du HTML de test).
// Même module dans le navigateur (WebCrypto) et dans les fonctions Netlify (Node 20 : globalThis.crypto).
// Format : pbkdf2$<itérations>$<sel base64>$<empreinte base64>
const enc = new TextEncoder();
const b64 = (u8) => (typeof btoa === 'function' ? btoa(String.fromCharCode(...u8)) : Buffer.from(u8).toString('base64'));
const deb64 = (s) => Uint8Array.from(typeof atob === 'function' ? atob(s) : Buffer.from(s, 'base64').toString('binary'), (c) => c.charCodeAt(0));

async function deriver(code, sel, iterations) {
  const cle = await globalThis.crypto.subtle.importKey('raw', enc.encode(String(code)), 'PBKDF2', false, ['deriveBits']);
  return new Uint8Array(await globalThis.crypto.subtle.deriveBits({ name: 'PBKDF2', hash: 'SHA-256', salt: sel, iterations }, cle, 256));
}

export async function empreinteCode(code, { iterations = 210000, sel } = {}) {
  const s = sel || globalThis.crypto.getRandomValues(new Uint8Array(16));
  return `pbkdf2$${iterations}$${b64(s)}$${b64(await deriver(code, s, iterations))}`;
}

// Comparaison à temps constant (aucune fuite par la durée)
export async function verifierCode(code, empreinte) {
  const [algo, it, sel, attendu] = String(empreinte || '').split('$');
  if (algo !== 'pbkdf2' || !Number(it) || !sel || !attendu || !/^\d{4,12}$/.test(String(code || ''))) return false;
  const a = await deriver(code, deb64(sel), Number(it)); const b = deb64(attendu);
  if (a.length !== b.length) return false;
  let d = 0;
  for (let i = 0; i < a.length; i++) d |= a[i] ^ b[i];
  return d === 0;
}
