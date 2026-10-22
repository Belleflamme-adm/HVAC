// Argent en cents (entiers), mêmes règles que la base (app.taxes, ADR-018).
// TPS 5 % = 5000 pcm, TVQ 9,975 % = 9975 pcm. Arrondi au cent, demi-cent loin de zéro.

export const TAUX_PCM = Object.freeze({ TPS: 5000, TVQ: 9975 });

export function arrondiTaxe(montantCents, tauxPcm) {
  if (!Number.isInteger(montantCents)) throw new TypeError('montant en cents entiers requis');
  const signe = montantCents < 0 ? -1 : 1;
  // BigInt : évite tout dépassement sur les gros montants.
  const r = (BigInt(Math.abs(montantCents)) * BigInt(tauxPcm) + 50000n) / 100000n;
  return signe * Number(r);
}

export function taxes(montantCents, { exemptTps = false, exemptTvq = false, taux = TAUX_PCM } = {}) {
  const tps = exemptTps ? 0 : arrondiTaxe(montantCents, taux.TPS);
  const tvq = exemptTvq ? 0 : arrondiTaxe(montantCents, taux.TVQ);
  return { tps, tvq, total: montantCents + tps + tvq };
}

// Montant d'une ligne après rabais (rabais en points de base). Même formule que devis_lignes.
export function montantLigne(quantite, prixUnitaireCents, rabaisBp = 0) {
  return Math.round((quantite * prixUnitaireCents * (10000 - rabaisBp)) / 10000);
}

// Plafond de rabais : escompte fournisseur moins 35 points, ou exception de la marque (ADR-010).
export function plafondRabaisBp({ escompteBp = 0, exceptionBp = null, delegationBp = 0 } = {}) {
  const auto = exceptionBp ?? Math.max(escompteBp - 3500, 0);
  return Math.max(auto, delegationBp || 0);
}

const FMT = new Intl.NumberFormat('fr-CA', { style: 'currency', currency: 'CAD' });
export const formatCents = (c) => FMT.format(c / 100);

if (typeof window !== 'undefined') window.bfMoney = { taxes, montantLigne, plafondRabaisBp, formatCents };
