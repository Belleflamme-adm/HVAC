// Feuille d'extra du sous-traitant (ADR-081). Toute la logique d'accès est dans la base (fonctions protégées) :
// ici on valide la forme et on appelle une seule fonction par geste.
import { uuid, ErreurValidation } from '../handler.js';

export const CAUSES = ['oubli_vendeur', 'imprevu_chantier', 'demande_client', 'autre'];

// Belleflamme : file d'approbation (statut=soumis par défaut) ou extras d'un projet
export async function listerExtras(repo, { statut, projet } = {}) {
  const filtre = {};
  if (projet) filtre.projet_id = uuid(projet, 'projet');
  else filtre.statut = statut === 'tous' ? { op: 'in', val: ['soumis', 'approuve', 'refuse'] } : 'soumis';
  return repo.list('extras_v', { filtre, ordre: { colonne: 'created_at', asc: true }, limite: 1000 });
}

// Sous-traitant : ajouter un extra en brouillon (de sa liste, ou hors liste avec prix et justification)
export async function ajouterExtra(repo, projet, corps) {
  uuid(projet, 'projet');
  if (!CAUSES.includes(corps?.cause)) throw new ErreurValidation('Cause requise : oubli du vendeur, imprévu de chantier, demande du client ou autre');
  const quantite = corps.quantite === undefined || corps.quantite === '' ? 1 : Number(corps.quantite);
  if (!Number.isFinite(quantite) || quantite <= 0 || quantite > 999) throw new ErreurValidation('Quantité invalide');
  const p = { cause: corps.cause, quantite };
  if (corps.note) p.note = String(corps.note).trim().slice(0, 500);
  if (corps.type_travail_id) p.type_travail_id = uuid(corps.type_travail_id, 'type_travail_id');   // prix pris dans sa liste, en base
  else {
    const description = String(corps.description || '').trim();
    const cout = Number(corps.cout_cents);
    const justification = String(corps.justification || '').trim();
    if (!description) throw new ErreurValidation('Description requise');
    if (!Number.isInteger(cout) || cout <= 0 || cout > 10000000) throw new ErreurValidation('Prix requis pour un extra hors liste');
    if (justification.length < 10) throw new ErreurValidation('Justification requise pour un extra hors liste (10 caractères et plus)');
    Object.assign(p, { description: description.slice(0, 200), cout_cents: cout, justification: justification.slice(0, 1000) });
  }
  return { id: await repo.rpc('hvac_extra_ajouter', { p_projet: projet, p }) };
}

// Gestes : retirer (brouillon), envoyer (feuille), decider (Belleflamme), facture (finale du sous-traitant)
export async function geste(repo, corps) {
  switch (corps?.action) {
    case 'retirer': await repo.rpc('hvac_extra_retirer', { p_id: uuid(corps.id) }); return { ok: true };
    case 'envoyer': return { envoyes: await repo.rpc('hvac_extras_envoyer', { p_projet: uuid(corps.projet, 'projet') }) };
    case 'decider': {
      const approuve = corps.approuve === true;
      const raison = String(corps.raison || '').trim();
      if (!approuve && !raison) throw new ErreurValidation('Raison du refus requise');
      await repo.rpc('hvac_extra_decider', { p_id: uuid(corps.id), p_approuve: approuve, p_raison: approuve ? null : raison.slice(0, 500) });
      return { ok: true };
    }
    case 'facture': return { total_cents: await repo.rpc('hvac_facture_finale', { p_projet: uuid(corps.projet, 'projet') }) };
    default: throw new ErreurValidation('Action inconnue');
  }
}

// Photos d'un extra (ADR-082) : bucket privé, URL signées de 10 minutes.
export const BUCKET_PHOTOS = 'extras-photos';
const MAX_PHOTO = 4 * 1024 * 1024;   // le navigateur compresse avant l'envoi ; limite du corps des fonctions Netlify : 6 Mo en base64
const SIGNATURES = { 'image/jpeg': [0xff, 0xd8, 0xff], 'image/png': [0x89, 0x50, 0x4e, 0x47] };

export function decoderPhoto(type, donnees) {
  if (!['image/jpeg', 'image/png', 'image/webp'].includes(type)) throw new ErreurValidation('Photo : JPEG, PNG ou WebP');
  const octets = Buffer.from(String(donnees || ''), 'base64');
  if (!octets.length) throw new ErreurValidation('Photo vide');
  if (octets.length > MAX_PHOTO) throw new ErreurValidation('Photo trop lourde (4 Mo au plus)');
  // Le contenu doit être une vraie image du type annoncé (pas un autre fichier renommé)
  const ok = type === 'image/webp'
    ? octets.subarray(0, 4).toString('latin1') === 'RIFF' && octets.subarray(8, 12).toString('latin1') === 'WEBP'
    : SIGNATURES[type].every((b, i) => octets[i] === b);
  if (!ok) throw new ErreurValidation('Le fichier n\'est pas une image valide');
  return octets;
}

export async function ajouterPhoto(repo, extra, { type, donnees } = {}) {
  uuid(extra, 'extra');
  const octets = decoderPhoto(type, donnees);
  const prep = await repo.rpc('hvac_extra_photo_preparer', { p_extra: extra, p_type: type, p_taille: octets.length });
  await repo.televerser(BUCKET_PHOTOS, prep.chemin, octets, type);
  await repo.rpc('hvac_extra_photo_confirmer', { p_id: prep.id });
  return { id: prep.id };
}

export async function photosExtra(repo, extra) {
  const lignes = await repo.rpc('hvac_extra_photos', { p_extra: uuid(extra, 'extra') });
  const urls = await repo.urlsSignees(BUCKET_PHOTOS, lignes.map((l) => l.chemin), 600);
  return lignes.map((l, i) => ({ id: l.id, url: urls[i] }));
}

export async function retirerPhoto(repo, id) {
  await repo.rpc('hvac_extra_photo_retirer', { p_id: uuid(id) });
  return { ok: true };
}
