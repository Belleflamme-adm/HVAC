// Liste de prix des sous-traitants (ADR-060, ADR-061) : édition des lignes, demandes de prix par lien,
// réponse du sous-traitant (sans compte, par jeton), révision et approbation.
import { choisir, uuid, ErreurValidation } from '../handler.js';

export const UNITES = ['forfait', 'tete', 'pied', 'sortie', 'heure', 'unite', 'livre'];
const JETON = /^[0-9a-f]{64}$/;

// Simon et Mike corrigent le titre, la description, l'unité ou la catégorie d'une ligne (RLS : admin)
export async function modifierTypeTravail(repo, id, corps) {
  uuid(id);
  const patch = choisir(corps, ['nom', 'description', 'unite', 'categorie', 'actif']);
  if (patch.nom !== undefined && String(patch.nom).trim().length < 3) throw new ErreurValidation('Titre trop court');
  if (patch.unite !== undefined && !UNITES.includes(patch.unite)) throw new ErreurValidation('Unité inconnue');
  if (patch.nom) patch.nom = String(patch.nom).trim();
  if (patch.description !== undefined) patch.description = String(patch.description || '').trim() || null;
  if (!Object.keys(patch).length) throw new ErreurValidation('Rien à modifier');
  return repo.update('types_travaux', id, patch);
}

// Lien envoyé au sous-traitant : le jeton est dans le fragment (#), jamais envoyé au serveur ni journalisé
export const lienDemande = (base, jeton) => `${String(base).replace(/\/$/, '')}/prix#${jeton}`;

export async function creerDemande(repo, corps, base) {
  const fournisseur = uuid(corps.fournisseur_id, 'fournisseur_id');
  const types = Array.isArray(corps.types) ? corps.types : [];
  if (!types.length) throw new ErreurValidation('Coche au moins un travail');
  if (types.length > 300) throw new ErreurValidation('Trop de travaux');
  types.forEach((t) => uuid(t, 'type de travail'));
  const [r] = await repo.rpc('hvac_creer_demande_prix', { p_fournisseur: fournisseur, p_types: types, p_message: corps.message || null });
  return { id: r.id, expire_le: r.expire_le, lien: lienDemande(base, r.jeton) };
}

const SANS_SECRETS = 'id,fournisseur_id,statut,message,expire_le,created_at,ouverte_le,signataire_nom,signe_le,valide_jusqu,approuvee_le';

export async function listerDemandes(repo, { fournisseur } = {}) {
  const filtre = fournisseur ? { fournisseur_id: uuid(fournisseur, 'fournisseur') } : {};
  return repo.list('demandes_prix', { select: SANS_SECRETS, filtre, ordre: { colonne: 'created_at', asc: false }, limite: 200 });
}

export async function obtenirDemande(repo, id) {
  uuid(id);
  const [demande] = await repo.list('demandes_prix', { select: `${SANS_SECRETS},signature_png,ip_signature`, filtre: { id }, limite: 1 });
  if (!demande) return null;
  const lignes = await repo.list('demandes_prix_lignes', { filtre: { demande_id: id }, ordre: { colonne: 'ordre' }, limite: 500 });
  return { demande, lignes };
}

export async function approuverDemande(repo, id) {
  uuid(id);
  return { tarifs: await repo.rpc('hvac_approuver_demande_prix', { p_demande: id }) };
}

export async function annulerDemande(repo, id) {
  uuid(id);
  return repo.update('demandes_prix', id, { statut: 'annulee' });
}

// ---------- Côté sous-traitant (public, jeton) ----------
export function verifierJeton(jeton) {
  if (!JETON.test(String(jeton || ''))) throw new ErreurValidation('Lien invalide');
  return jeton;
}

export async function lirePublique(repo, jeton) {
  return repo.rpc('hvac_demande_prix_lire', { p_jeton: verifierJeton(jeton) });
}

export async function soumettrePublique(repo, jeton, corps) {
  verifierJeton(jeton);
  const lignes = Array.isArray(corps.lignes) ? corps.lignes : [];
  if (!lignes.length || lignes.length > 300) throw new ErreurValidation('Liste de prix vide');
  const propres = lignes.map((l) => {
    uuid(l.id, 'ligne');
    const nonOffert = l.non_offert === true;
    const cout = l.cout_cents === null || l.cout_cents === undefined || l.cout_cents === '' ? null : Number(l.cout_cents);
    if (!nonOffert && (!Number.isInteger(cout) || cout <= 0 || cout > 100000000)) throw new ErreurValidation('Chaque ligne doit avoir un prix ou être marquée « je n\'offre pas ce service »');
    return { id: l.id, cout_cents: nonOffert ? null : cout, non_offert: nonOffert, note: l.note ? String(l.note).slice(0, 300) : null };
  });
  const nom = String(corps.nom || '').trim();
  if (nom.length < 3) throw new ErreurValidation('Nom du signataire requis');
  const signature = String(corps.signature || '');
  if (!signature.startsWith('data:image/png;base64,') || signature.length > 290000) throw new ErreurValidation('Signature requise');
  if (corps.atteste !== true) throw new ErreurValidation('Il faut confirmer que les prix sont valides un an');
  return repo.rpc('hvac_demande_prix_soumettre', { p_jeton: jeton, p_lignes: propres, p_nom: nom, p_signature: signature, p_atteste: true });
}

// Adresse publique du site pour le lien (Netlify fournit URL ; sinon l'hôte de la requête)
export function baseUrl(event, env = process.env) {
  if (env.URL) return env.URL;
  const h = event.headers || {};
  const hote = h['x-forwarded-host'] || h.host;
  return hote ? `https://${hote}` : '';
}
