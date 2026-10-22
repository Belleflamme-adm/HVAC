// Lot A | Sous-traitants : territoire, principal, disponibilités, création de compte.
// Un sous-traitant agit toujours sur SON fournisseur (imposé ici et par la RLS).
import { choisir, uuid, ErreurValidation } from '../handler.js';

const TYPES_ST = ['sous-traitant', 'les deux'];
const STATUTS_TERRITOIRE = ['accepte', 'supplement', 'refuse', 'aucun'];
const JOUR = /^\d{4}-\d{2}-\d{2}$/;

// Fournisseur visé : le sien pour un sous-traitant, sinon celui demandé (planification).
export async function fournisseurCible(data, token, demande) {
  const { employe } = await data.session(token);
  if (!employe) throw Object.assign(new Error('Non connecté'), { status: 401, code: 'non_connecte' });
  if (employe.fournisseur_id) return employe.fournisseur_id;
  return uuid(demande, 'fournisseur_id');
}

export async function listerSousTraitants(repo) {
  return repo.list('fournisseurs', {
    select: 'id,nom,type,telephone,courriel,licence_rbq,actif',
    filtre: { type: { op: 'in', val: TYPES_ST } }, ordre: { colonne: 'nom' },
  });
}

export async function creerSousTraitant(repo, corps) {
  const f = choisir(corps, ['nom', 'telephone', 'courriel', 'neq', 'licence_rbq'], ['nom']);
  const contact = choisir(corps.contact || {}, ['prenom', 'nom', 'email'], ['prenom', 'nom', 'email']);
  const fournisseur = await repo.insert('fournisseurs', { ...f, type: 'sous-traitant' });
  // Le compte se connecte après invitation Supabase Auth (ADR-026) ; il est lié par courriel.
  const compte = await repo.insert('employes', {
    email: String(contact.email).trim().toLowerCase(), prenom: contact.prenom, nom: contact.nom,
    role: 'Sous-traitant', succursale_code: corps.succursale_code || 'HO', fournisseur_id: fournisseur.id,
  });
  return { fournisseur, compte };
}

export async function lireTerritoire(repo, fournisseurId) {
  return repo.list('territoires_sous_traitants', {
    select: 'municipalite_code,statut,supplement_cents', filtre: { fournisseur_id: fournisseurId }, limite: 5000,
  });
}

// Applique un statut à plusieurs municipalités d'un coup (clic, sélection, région entière).
export async function majTerritoire(repo, fournisseurId, corps) {
  const { municipalites, statut } = choisir(corps, ['municipalites', 'statut', 'supplement_cents'], ['municipalites', 'statut']);
  if (!Array.isArray(municipalites) || !municipalites.length || municipalites.length > 2000) {
    throw new ErreurValidation('Liste de municipalités invalide (1 à 2000)');
  }
  if (!STATUTS_TERRITOIRE.includes(statut)) throw new ErreurValidation('Statut : accepte, supplement, refuse ou aucun');
  const codes = municipalites.map((m) => String(m).trim()).filter(Boolean);
  if (statut === 'aucun') return repo.removeWhere('territoires_sous_traitants', { fournisseur_id: fournisseurId, municipalite_code: codes });
  let supplement = null;
  if (statut === 'supplement') {
    supplement = corps.supplement_cents;
    if (!Number.isInteger(supplement) || supplement <= 0) throw new ErreurValidation('Supplément en cents requis (plus de 0 $)');
  }
  return repo.upsert('territoires_sous_traitants',
    codes.map((code) => ({ fournisseur_id: fournisseurId, municipalite_code: code, statut, supplement_cents: supplement })),
    { onConflict: 'fournisseur_id,municipalite_code' });
}

export async function lirePrincipaux(repo) {
  return repo.list('principaux_municipalites', { select: 'municipalite_code,fournisseur_id', limite: 5000 });
}

export async function designerPrincipal(repo, corps) {
  const { municipalite_code, fournisseur_id } = choisir(corps, ['municipalite_code', 'fournisseur_id'], ['municipalite_code']);
  if (fournisseur_id) uuid(fournisseur_id, 'fournisseur_id');
  return repo.upsert('principaux_municipalites', [{ municipalite_code, fournisseur_id: fournisseur_id || null }], { onConflict: 'municipalite_code' });
}

export async function lireDisponibilites(repo, fournisseurId, { de, a } = {}) {
  const filtre = {};
  if (fournisseurId) filtre.fournisseur_id = fournisseurId;
  if (de) { if (!JOUR.test(de)) throw new ErreurValidation('Date de début invalide'); filtre.jour = { op: 'gte', val: de }; }
  const lignes = await repo.list('disponibilites_sous_traitants', {
    select: 'fournisseur_id,jour,statut,note', filtre, ordre: { colonne: 'jour' }, limite: 2000,
  });
  if (a && !JOUR.test(a)) throw new ErreurValidation('Date de fin invalide');
  return a ? lignes.filter((l) => l.jour <= a) : lignes;
}

// jours : [{ jour: 'AAAA-MM-JJ', statut: 'disponible' | 'indisponible' | 'aucun' }]
export async function majDisponibilites(repo, fournisseurId, corps) {
  const jours = corps?.jours;
  if (!Array.isArray(jours) || !jours.length || jours.length > 400) throw new ErreurValidation('Liste de jours invalide (1 à 400)');
  const aujourdhui = new Date().toISOString().slice(0, 10);
  for (const j of jours) {
    if (!JOUR.test(j.jour)) throw new ErreurValidation(`Date invalide : ${j.jour}`);
    if (j.jour < aujourdhui) throw new ErreurValidation('Les journées passées ne se modifient pas');
    if (!['disponible', 'indisponible', 'aucun'].includes(j.statut)) throw new ErreurValidation('Statut : disponible, indisponible ou aucun');
  }
  const aEffacer = jours.filter((j) => j.statut === 'aucun').map((j) => j.jour);
  const aEcrire = jours.filter((j) => j.statut !== 'aucun')
    .map((j) => ({ fournisseur_id: fournisseurId, jour: j.jour, statut: j.statut, note: j.note ? String(j.note).slice(0, 200) : null }));
  if (aEffacer.length) await repo.removeWhere('disponibilites_sous_traitants', { fournisseur_id: fournisseurId, jour: aEffacer });
  if (aEcrire.length) await repo.upsert('disponibilites_sous_traitants', aEcrire, { onConflict: 'fournisseur_id,jour' });
  return { ok: true, ecrits: aEcrire.length, effaces: aEffacer.length };
}

export async function chercherMunicipalites(repo, q) {
  const terme = String(q || '').trim();
  if (terme.length < 2) return [];
  return repo.list('municipalites', {
    select: 'code,nom,mrc,region', filtre: { actif: true }, recherche: { colonnes: ['nom'], terme }, ordre: { colonne: 'nom' }, limite: 20,
  });
}

export async function sousTraitantsPour(repo, municipalite) {
  if (!municipalite) throw new ErreurValidation('Municipalité requise');
  return repo.rpc('hvac_sous_traitants_pour', { p_municipalite: String(municipalite) });
}
