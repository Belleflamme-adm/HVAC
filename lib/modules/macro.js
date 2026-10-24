// Macro HVAC (ADR-079) : projets signés, par étape. Le client signe dans l'app de Mike ; d'ici la greffe,
// Belleflamme inscrit la soumission signée depuis la fiche du lead (et le HTML de test la simule).
import { uuid, ErreurValidation } from '../handler.js';

export const ETAPES = ['attente_paiement', 'a_planifier', 'planifie', 'en_cours', 'termine', 'facture'];
export const FERMES = ['ferme', 'annule'];
const TYPES = ['mural_simple', 'mural_multi', 'central', 'bienergie'];

export async function listerProjets(repo, { succursale, vendeur, fermes, lead } = {}) {
  const filtre = { statut: { op: 'in', val: fermes === '1' || lead ? [...ETAPES, ...FERMES] : ETAPES } };
  if (lead) filtre.lead_id = uuid(lead, 'lead');
  if (succursale) filtre.succursale_code = String(succursale);
  if (vendeur) filtre.vendeur_id = uuid(vendeur, 'vendeur');
  return repo.list('projets_macro_v', { filtre, ordre: { colonne: 'signe_le', asc: false }, limite: 1000 });
}

// Avancer, reculer d'une étape ou annuler (la base refuse les autres sauts)
export async function changerEtape(repo, id, corps) {
  uuid(id);
  const statut = String(corps?.statut || '');
  if (![...ETAPES, ...FERMES].includes(statut)) throw new ErreurValidation('Étape inconnue');
  return repo.update('projets', id, { statut });
}

// Soumission signée par le client : le projet tombe dans le Macro, le lead passe à Vendu
export async function recevoirSigne(repo, corps) {
  const numero = String(corps?.devis_numero_mike || '').replace(/^#/, '').trim();
  if (!/^\d{4,8}$/.test(numero)) throw new ErreurValidation('Numéro de soumission : 4 à 8 chiffres (ex. 120815)');
  const p = { devis_numero_mike: numero };
  if (corps.lead_id) p.lead_id = uuid(corps.lead_id, 'lead_id');
  if (corps.client_id) p.client_id = uuid(corps.client_id, 'client_id');
  if (!p.lead_id && !p.client_id) throw new ErreurValidation('Lead ou client requis');
  if (corps.montant_avant_taxes_cents !== undefined && corps.montant_avant_taxes_cents !== null && corps.montant_avant_taxes_cents !== '') {
    const m = Number(corps.montant_avant_taxes_cents);
    if (!Number.isInteger(m) || m <= 0 || m > 100000000) throw new ErreurValidation('Montant invalide');
    p.montant_avant_taxes_cents = m;
  }
  if (corps.type_systeme) { if (!TYPES.includes(corps.type_systeme)) throw new ErreurValidation('Type de système inconnu'); p.type_systeme = corps.type_systeme; }
  if (corps.succursale_code) p.succursale_code = String(corps.succursale_code);
  return { projet_id: await repo.rpc('hvac_projet_signe', { p }) };
}
