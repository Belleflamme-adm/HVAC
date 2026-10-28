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
export const SUBVENTION = ['a_deposer', 'deposee', 'acceptee', 'versee', 'refusee'];

export async function changerEtape(repo, id, corps) {
  uuid(id);
  // Facture finale conforme LogisVert (ADR-092) : payée (d'ici la greffe) et vérifiée (les 4 mentions vues sur la facture de Mike)
  if (corps?.action === 'facture_payee') {
    const n = String(corps.facture_numero_mike || '').trim();
    if (!n) throw new ErreurValidation('Numéro de la facture de Mike requis');
    await repo.rpc('hvac_facture_payee_manuel', { p_projet: id, p_numero_facture: n.slice(0, 40) }); return { ok: true };
  }
  if (corps?.action === 'facture_verifiee') { await repo.rpc('hvac_facture_verifiee', { p_projet: id }); return { ok: true }; }
  // Étape de la subvention LogisVert (ADR-090) : chaque étape envoie un texto au client (règle « Suivi de subvention »)
  if (corps?.subvention_statut !== undefined) {
    if (!SUBVENTION.includes(corps.subvention_statut)) throw new ErreurValidation('Étape de subvention inconnue');
    await repo.rpc('hvac_subvention_etape', { p_projet: id, p_statut: corps.subvention_statut });
    return { ok: true };
  }
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
  if (corps.sous_traitant_id) p.sous_traitant_id = uuid(corps.sous_traitant_id, 'sous_traitant_id');
  if (corps.lignes !== undefined) p.lignes = lignesSignees(corps.lignes, Boolean(p.sous_traitant_id));
  return { projet_id: await repo.rpc('hvac_projet_signe', { p }) };
}

// Lignes du projet (ADR-080) : machines sans prix, installation sans prix non plus (la base prend le coût
// dans la liste du sous-traitant). Le navigateur n'envoie jamais de montant de ligne.
function lignesSignees(lignes, avecSousTraitant) {
  if (!Array.isArray(lignes) || lignes.length > 50) throw new ErreurValidation('Lignes invalides');
  return lignes.map((l) => {
    const quantite = l.quantite === undefined || l.quantite === '' ? 1 : Number(l.quantite);
    if (!Number.isFinite(quantite) || quantite <= 0 || quantite > 999) throw new ErreurValidation('Quantité invalide');
    if (l.type_ligne === 'machine') {
      const description = String(l.description || '').trim();
      if (!description) throw new ErreurValidation('Description de la machine requise');
      return { type_ligne: 'machine', description: description.slice(0, 200), quantite };
    }
    if (l.type_ligne === 'installation') {
      if (!avecSousTraitant) throw new ErreurValidation('Choisis le sous-traitant de l\'installation');
      return { type_ligne: 'installation', type_travail_id: uuid(l.type_travail_id, 'type_travail_id'), quantite };
    }
    throw new ErreurValidation('Type de ligne inconnu');
  });
}

// Mes jobs : projets signés du sous-traitant, machines à 0 $, ses prix seulement (fonction protégée de la base)
export async function mesJobs(repo, fournisseur) {
  return repo.rpc('hvac_mes_projets', fournisseur ? { p_fournisseur: uuid(fournisseur, 'fournisseur') } : {});
}
