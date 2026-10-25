// Visite planifiée dans Pointage (ADR-086) : l'app de Mike envoie la visite (pré-installation Ventilation) à notre
// webhook ; la date arrive seule dans le lead. Contrat PROPOSÉ à Mike (docs/MIGRATION.md) :
//   POST /.netlify/functions/pointage-webhook
//   En-têtes : X-Belleflamme-Horodatage: <secondes Unix> ; X-Belleflamme-Signature: sha256=<hex>
//   Signature : HMAC-SHA256(secret partagé, `${horodatage}.${corps brut}`) ; refusée après 5 minutes (rejeu).
//   Corps : { lead_ref?, telephone?, pointage_ref, visite_le?, annulee? }
import { signer, verifierSignature, FENETRE_SECONDES } from '../signature.js';

export { signer, verifierSignature, FENETRE_SECONDES };

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export function normaliserVisite(c = {}) {
  const ref = String(c.pointage_ref || '').trim();
  if (!ref || ref.length > 100) return { erreur: 'pointage_ref requis' };
  const p = { pointage_ref: ref };
  if (c.lead_ref) { if (!UUID.test(String(c.lead_ref))) return { erreur: 'lead_ref invalide' }; p.lead_ref = String(c.lead_ref); }
  if (c.telephone) p.telephone = String(c.telephone).slice(0, 30);
  if (c.annulee === true) p.annulee = true;
  else {
    const d = new Date(c.visite_le);
    if (!c.visite_le || Number.isNaN(d.getTime())) return { erreur: 'visite_le requis (date ISO)' };
    p.visite_le = d.toISOString();
  }
  return { visite: p };
}
