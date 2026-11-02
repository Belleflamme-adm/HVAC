// Signature des webhooks de l'app de Mike (Pointage ADR-086, paiements ADR-087) :
//   En-têtes : X-Belleflamme-Horodatage: <secondes Unix> ; X-Belleflamme-Signature: sha256=<hex>
//   Signature : HMAC-SHA256(secret partagé, `${horodatage}.${corps brut}`) ; refusée après 5 minutes (rejeu).
import { createHmac, timingSafeEqual } from 'node:crypto';

export const FENETRE_SECONDES = 300;

export function signer(secret, horodatage, corpsBrut) {
  return `sha256=${createHmac('sha256', secret).update(`${horodatage}.${corpsBrut}`).digest('hex')}`;
}

export function verifierSignature({ secret, horodatage, signature, corpsBrut, maintenant = Date.now() }) {
  if (!secret) return 'secret non configuré';
  if (!horodatage || !signature) return 'signature absente';
  const ts = Number(horodatage);
  if (!Number.isInteger(ts) || Math.abs(maintenant / 1000 - ts) > FENETRE_SECONDES) return 'horodatage expiré';
  const attendu = Buffer.from(signer(secret, ts, corpsBrut));
  const recu = Buffer.from(String(signature));
  if (attendu.length !== recu.length || !timingSafeEqual(attendu, recu)) return 'signature invalide';
  return null;
}

// Vérifie les en-têtes d'un événement Netlify ; rend le corps brut, ou { probleme }
export function lireSigne(event, secret) {
  const h = Object.fromEntries(Object.entries(event.headers || {}).map(([k, v]) => [k.toLowerCase(), v]));
  const corpsBrut = event.isBase64Encoded ? Buffer.from(event.body || '', 'base64').toString('utf8') : (event.body || '');
  const probleme = verifierSignature({ secret, horodatage: h['x-belleflamme-horodatage'], signature: h['x-belleflamme-signature'], corpsBrut });
  return { corpsBrut, probleme };
}
