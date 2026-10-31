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

const FICHE = 'id,nom,type,telephone,courriel,licence_rbq,neq,adresse,responsable_nom,responsable_telephone,responsable_courriel,proprietaire_nom,actif,partenaire_depuis';
const COURRIEL = /^[^@\s]+@[^@\s]+\.[^@\s]+$/;

// Numéro de licence RBQ : 10 chiffres, rendu au format 1234-5678-90 ; vide = aucun
export function normaliserRbq(v) {
  const t = String(v ?? '').trim();
  if (!t) return null;
  const chiffres = t.replace(/\D/g, '');
  if (chiffres.length !== 10 || /[^\d\s-]/.test(t)) throw new ErreurValidation('Numéro RBQ : 10 chiffres (ex. 1234-5678-90)');
  return `${chiffres.slice(0, 4)}-${chiffres.slice(4, 8)}-${chiffres.slice(8)}`;
}

export async function listerSousTraitants(repo) {
  return repo.list('fournisseurs', {
    select: FICHE,
    filtre: { type: { op: 'in', val: TYPES_ST } }, ordre: { colonne: 'nom' },
  });
}

export async function creerSousTraitant(repo, corps) {
  const f = choisir(corps, ['nom', 'telephone', 'courriel', 'neq', 'licence_rbq', 'proprietaire_nom'], ['nom']);
  const contact = choisir(corps.contact || {}, ['prenom', 'nom', 'email'], ['prenom', 'nom', 'email']);
  if (f.licence_rbq !== undefined) f.licence_rbq = normaliserRbq(f.licence_rbq);
  // Le contact qui reçoit l'accès est le responsable par défaut ; la fiche se corrige ensuite
  const fournisseur = await repo.insert('fournisseurs', { ...f, type: 'sous-traitant',
    responsable_nom: `${contact.prenom} ${contact.nom}`.trim(), responsable_courriel: String(contact.email).trim().toLowerCase() });
  // Le compte se connecte après invitation Supabase Auth (ADR-026) ; il est lié par courriel.
  const compte = await repo.insert('employes', {
    email: String(contact.email).trim().toLowerCase(), prenom: contact.prenom, nom: contact.nom,
    role: 'Sous-traitant', succursale_code: corps.succursale_code || 'HO', fournisseur_id: fournisseur.id,
  });
  return { fournisseur, compte };
}

// Fiche du sous-traitant (ADR-064) : lecture et modification (RLS : planification)
export async function obtenirSousTraitant(repo, id) {
  uuid(id);
  const [f] = await repo.list('fournisseurs', { select: FICHE, filtre: { id }, limite: 1 });
  return f || null;
}

export async function modifierSousTraitant(repo, id, corps) {
  uuid(id);
  const patch = choisir(corps, ['nom', 'licence_rbq', 'neq', 'adresse', 'telephone', 'courriel',
    'responsable_nom', 'responsable_telephone', 'responsable_courriel', 'proprietaire_nom', 'actif', 'partenaire_depuis']);
  if (!Object.keys(patch).length) throw new ErreurValidation('Rien à modifier');
  for (const [k, v] of Object.entries(patch)) if (typeof v === 'string') patch[k] = v.trim() || null;
  if ('nom' in patch && (!patch.nom || patch.nom.length < 2)) throw new ErreurValidation('Nom de la compagnie requis');
  if ('licence_rbq' in patch) patch.licence_rbq = normaliserRbq(patch.licence_rbq);
  for (const k of ['courriel', 'responsable_courriel']) {
    if (patch[k]) { patch[k] = patch[k].toLowerCase(); if (!COURRIEL.test(patch[k])) throw new ErreurValidation('Courriel invalide'); }
  }
  for (const k of ['responsable_nom', 'proprietaire_nom']) if (patch[k] && patch[k].length > 120) throw new ErreurValidation('Nom trop long');
  if ('actif' in patch && typeof patch.actif !== 'boolean') throw new ErreurValidation('Actif : oui ou non');
  if ('partenaire_depuis' in patch && (!/^\d{4}-\d{2}-\d{2}$/.test(patch.partenaire_depuis || '') || patch.partenaire_depuis > new Date().toISOString().slice(0, 10))) {
    throw new ErreurValidation('Partenaire depuis : une date passée (AAAA-MM-JJ)');
  }
  return repo.update('fournisseurs', id, patch);
}

export async function lireTerritoire(repo, fournisseurId) {
  return repo.list('territoires_sous_traitants', {
    select: 'municipalite_code,statut,supplement_cents', filtre: { fournisseur_id: fournisseurId }, limite: 5000,
  });
}

// Tous les territoires desservis (accepte ou supplément) : carte comparative des sous-traitants (ADR-063).
// Réservé à Belleflamme ; un sous-traitant ne voit pas le territoire des autres (la RLS le garantit aussi).
export async function lireTousTerritoires(repo, data, token) {
  const { employe } = await data.session(token);
  if (!employe) throw Object.assign(new Error('Non connecté'), { status: 401, code: 'non_connecte' });
  if (employe.fournisseur_id) throw Object.assign(new Error('Réservé à Belleflamme'), { status: 403, code: 'interdit' });
  return repo.list('territoires_sous_traitants', {
    select: 'fournisseur_id,municipalite_code,statut,supplement_cents',
    filtre: { statut: { op: 'in', val: ['accepte', 'supplement'] } }, limite: 50000,
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

// Accès du sous-traitant (ADR-095) : un compte, au courriel du responsable, connexion par code reçu par courriel.
// Les règles (planification seulement, compte actif, sous-traitant actif) sont dans la base.
export const ACTIONS_ACCES = ['envoyer', 'couper', 'retablir'];

export async function lireAcces(repo, id) {
  return repo.rpc('hvac_st_acces', { p_fournisseur: uuid(id) });
}

export async function gererAcces(repo, auth, id, action) {
  uuid(id);
  if (!ACTIONS_ACCES.includes(action)) throw new ErreurValidation('Action inconnue');
  if (action === 'envoyer') {
    const email = await repo.rpc('hvac_st_acces_envoyer', { p_fournisseur: id });
    await auth.envoyerCode(email, { creer: true });   // crée le compte Auth au premier envoi
  } else {
    await repo.rpc(action === 'couper' ? 'hvac_st_acces_couper' : 'hvac_st_acces_retablir', { p_fournisseur: id });
  }
  return lireAcces(repo, id);
}

// Partenariat (ADR-096) : depuis quand, compte créé, version active de la liste de prix. Le sous-traitant reçoit
// toujours le sien ; la planification passe le fournisseur.
export async function lirePartenariat(repo, fournisseur) {
  return repo.rpc('hvac_partenariat', { p_fournisseur: fournisseur ? uuid(fournisseur, 'fournisseur') : null });
}
