// Dossier de job LogisVert (ADR-084) : numéro AHRI du système, appareils (marque, modèle, série) et photos
// (plaque et appareil installé, pour chaque appareil ; lignes et drain, pour la job). Exigé pour la facture finale et l'étape « Terminé ».
// Les règles d'accès sont dans la base ; ici : forme des données, fichiers et URL signées.
import { uuid, ErreurValidation } from '../handler.js';
import { decoderPhoto } from './extras.js';

export const BUCKET_JOBS = 'jobs-photos';
export const ROLES = ['exterieur', 'interieur', 'fournaise', 'autre'];
export const CATEGORIES = ['plaque', 'installe', 'lignes', 'drain', 'autre'];   // lignes et drain : photos de la job (ADR-093)

export async function lireDossier(repo, projet) {
  const d = await repo.rpc('hvac_job_dossier', { p_projet: uuid(projet, 'projet') });
  const urls = await repo.urlsSignees(BUCKET_JOBS, d.photos.map((p) => p.chemin), 600);
  return { ...d, photos: d.photos.map(({ chemin, ...p }, i) => ({ ...p, url: urls[i] })) };
}

export async function ajouterAuDossier(repo, projet, corps = {}) {
  uuid(projet, 'projet');
  if (corps.action === 'equipement') {
    if (!ROLES.includes(corps.role)) throw new ErreurValidation('Type d\'appareil : extérieur, intérieur, fournaise ou autre');
    const [marque, modele, serie] = [corps.marque, corps.modele, corps.numero_serie].map((v) => String(v || '').trim());
    if (!marque || !modele || !serie) throw new ErreurValidation('Marque, modèle et numéro de série requis');
    const p = { role: corps.role, marque: marque.slice(0, 80), modele: modele.slice(0, 80), numero_serie: serie.slice(0, 60) };
    return { id: await repo.rpc('hvac_job_equipement_ajouter', { p_projet: projet, p }) };
  }
  if (corps.action === 'photo') {
    if (!CATEGORIES.includes(corps.categorie)) throw new ErreurValidation('Catégorie de photo inconnue');
    const equipement = corps.equipement_id ? uuid(corps.equipement_id, 'equipement_id') : null;
    const octets = decoderPhoto(corps.type, corps.donnees);
    const prep = await repo.rpc('hvac_job_photo_preparer', { p_projet: projet, p_equipement: equipement, p_categorie: corps.categorie, p_type: corps.type, p_taille: octets.length });
    await repo.televerser(BUCKET_JOBS, prep.chemin, octets, corps.type);
    await repo.rpc('hvac_job_photo_confirmer', { p_id: prep.id });
    return { id: prep.id };
  }
  throw new ErreurValidation('Action inconnue');
}

export async function modifierDossier(repo, corps = {}) {
  switch (corps.action) {
    case 'ahri': {
      const n = String(corps.numero_ahri || '').replace(/\s/g, '');
      if (!/^[0-9]{5,12}$/.test(n)) throw new ErreurValidation('Numéro AHRI : 5 à 12 chiffres');
      await repo.rpc('hvac_job_ahri', { p_projet: uuid(corps.projet, 'projet'), p_numero: n }); return { ok: true };
    }
    case 'energy_star': {
      const n = String(corps.numero_energy_star || '').replace(/\s/g, '');
      if (!/^[0-9]{7}$/.test(n)) throw new ErreurValidation('Numéro ENERGY STAR : 7 chiffres');
      await repo.rpc('hvac_job_energy_star', { p_projet: uuid(corps.projet, 'projet'), p_numero: n }); return { ok: true };
    }
    case 'retirer_equipement': await repo.rpc('hvac_job_equipement_retirer', { p_id: uuid(corps.id) }); return { ok: true };
    case 'retirer_photo': await repo.rpc('hvac_job_photo_retirer', { p_id: uuid(corps.id) }); return { ok: true };
    default: throw new ErreurValidation('Action inconnue');
  }
}

// Conservation (Loi 25) : photos purgées 5 ans après « Terminé », ou dès l'annulation du projet (ADR-094). Appelé par la tâche planifiée, avec la clé serveur.
// actif=false : on compte seulement (rien n'est effacé).
export async function purgerPhotos(systeme, { actif = false, limite = 500 } = {}) {
  const lots = await systeme.rpc('hvac_photos_a_purger', { p_limite: limite });
  if (!actif || !lots.length) return { a_purger: lots.length, purgees: 0, actif };
  const parBucket = {};
  for (const l of lots) (parBucket[l.bucket] ||= []).push(l);
  const faits = { job: [], extra: [] };
  for (const [bucket, l] of Object.entries(parBucket)) {
    await systeme.supprimerFichiers(bucket, l.map((x) => x.chemin));
    for (const x of l) faits[x.source].push(x.id);
  }
  const purgees = await systeme.rpc('hvac_photos_purgees', { p_job: faits.job, p_extra: faits.extra });
  return { a_purger: lots.length, purgees, actif };
}
