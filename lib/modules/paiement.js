// Dépôt reçu dans l'app de Mike (ADR-087) : le projet passe seul à « À céduler ». Contrat PROPOSÉ à Mike (docs/MIGRATION.md) :
//   POST /.netlify/functions/paiement-webhook, signé comme les autres webhooks (lib/signature.js)
//   Corps : { type: 'depot', devis_numero_mike, paiement_ref, montant_cents?, paye_le? }

export function normaliserDepot(c = {}) {
  if (c.type !== 'depot') return { ignore: `type « ${c.type || '?'} » non traité (seul le dépôt fait avancer le projet)` };
  const numero = String(c.devis_numero_mike || '').replace(/^#/, '').trim();
  if (!/^\d{4,8}$/.test(numero)) return { erreur: 'devis_numero_mike : 4 à 8 chiffres' };
  const ref = String(c.paiement_ref || '').trim();
  if (!ref || ref.length > 100) return { erreur: 'paiement_ref requis' };
  const p = { devis_numero_mike: numero, paiement_ref: ref };
  if (c.montant_cents !== undefined && c.montant_cents !== null) {
    if (!Number.isInteger(c.montant_cents) || c.montant_cents <= 0) return { erreur: 'montant_cents invalide' };
    p.montant_cents = c.montant_cents;
  }
  if (c.paye_le) {
    const d = new Date(c.paye_le);
    if (Number.isNaN(d.getTime())) return { erreur: 'paye_le invalide' };
    p.paye_le = d.toISOString();
  }
  return { depot: p };
}
