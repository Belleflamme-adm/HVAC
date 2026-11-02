// Liens de contact sans dépendance (navigateur et serveur) : téléphone, texto, courriel, carte (ADR-067).

// Numéro nord-américain : 10 chiffres (ou 11 avec le 1) -> +1XXXXXXXXXX ; sinon null
export function numeroE164(v) {
  const d = String(v || '').replace(/\D/g, '');
  if (d.length === 10) return `+1${d}`;
  if (d.length === 11 && d.startsWith('1')) return `+${d}`;
  return null;
}
const COURRIEL = /^[^@\s]+@[^@\s]+\.[^@\s]+$/;

export function lienAction(canal, coordonnee) {
  if (canal === 'courriel') { const c = String(coordonnee || '').trim(); return COURRIEL.test(c) ? `mailto:${c}` : null; }
  const n = numeroE164(coordonnee);
  if (!n) return null;
  return canal === 'texto' ? `sms:${n}` : `tel:${n}`;
}

// Carte du client : Google Maps (URL officielle « Maps URLs », sans clé). Position exacte si connue, sinon l'adresse.
// À la greffe : remplacée par la carte du client de l'app de Mike.
export function lienCarte(site) {
  if (!site) return null;
  const { latitude: lat, longitude: lng } = site;
  const q = lat !== null && lat !== undefined && lng !== null && lng !== undefined
    ? `${Number(lat)},${Number(lng)}`
    : [site.adresse, site.ville, site.province || 'QC', site.code_postal].filter(Boolean).join(', ');
  if (!q.replace(/[,\s]/g, '')) return null;
  return `https://www.google.com/maps/search/?api=1&query=${encodeURIComponent(q)}`;
}
