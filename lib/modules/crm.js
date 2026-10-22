// CRM des leads (ADR-056) : board principal, vue du vendeur, journal, rapidité, tableau de quantification.
// La base attribue (tour de rôle), horodate et fait avancer les statuts ; la RLS limite le vendeur à ses leads.
import { choisir, uuid, ErreurValidation } from '../handler.js';

export const SOURCES = ['google', 'facebook', 'instagram', 'site_web', 'telephone', 'magasin', 'reference', 'salon', 'autre'];
export const STATUTS = ['nouveau', 'pris_en_charge', 'contacte', 'qualifie', 'inspection_planifiee', 'converti', 'perdu'];
export const TYPES_ACTIVITE = ['prise_en_charge', 'appel', 'courriel', 'texto', 'note', 'visite_planifiee', 'perdu', 'reouvert'];
const RESULTATS = ['joint', 'message_laisse', 'pas_de_reponse', 'envoye'];
const LISTE = 'id,recu_le,source,campagne,statut,contact_nom,contact_tel,contact_courriel,ville,besoin,assigne_a,vendeur_nom,'
  + 'pris_en_charge_le,premier_contact_le,premier_contact_canal,visite_prevue_le,minutes_premier_contact,minutes_en_attente,en_retard';

// vue = 'mes' (le vendeur) ou 'board' (tous les leads visibles ; la RLS décide)
export async function listerLeads(repo, { vue, employeId, statut, vendeur, limite } = {}) {
  const filtre = {};
  if (vue === 'mes') filtre.assigne_a = uuid(employeId, 'employe');
  else if (vendeur) filtre.assigne_a = uuid(vendeur, 'vendeur');
  if (statut === 'actifs') filtre.statut = { op: 'in', val: STATUTS.filter((s) => !['converti', 'perdu'].includes(s)) };
  else if (statut) {
    if (!STATUTS.includes(statut)) throw new ErreurValidation('Statut inconnu');
    filtre.statut = statut;
  }
  return repo.list('leads_v', { select: LISTE, filtre, ordre: { colonne: 'recu_le', asc: false }, limite: Number(limite) || 200 });
}

export async function obtenirLead(repo, id) {
  uuid(id);
  const [lead] = await repo.list('leads_v', { filtre: { id }, limite: 1 });
  if (!lead) return null;
  const activites = await repo.list('lead_activites', {
    select: 'id,type,resultat,note,visite_le,employe_id,fait_le', filtre: { lead_id: id }, ordre: { colonne: 'fait_le' }, limite: 500,
  });
  return { lead, activites };
}

// Saisie manuelle (lead téléphonique, magasin) ; les leads Google/Facebook viendront de Monday.
export async function creerLead(repo, corps) {
  const ligne = choisir(corps, ['succursale_code', 'source', 'campagne', 'contact_nom', 'contact_tel', 'contact_courriel',
    'ville', 'besoin'], ['succursale_code', 'contact_nom']);
  if (ligne.source && !SOURCES.includes(ligne.source)) throw new ErreurValidation('Source inconnue');
  if (!ligne.contact_tel && !ligne.contact_courriel) throw new ErreurValidation('Téléphone ou courriel requis');
  return repo.insert('leads', ligne);
}

export async function ajouterActivite(repo, leadId, employeId, corps) {
  uuid(leadId, 'lead');
  const a = choisir(corps, ['type', 'resultat', 'note', 'visite_le'], ['type']);
  if (!TYPES_ACTIVITE.includes(a.type)) throw new ErreurValidation('Type d\'activité inconnu');
  if (a.resultat && !RESULTATS.includes(a.resultat)) throw new ErreurValidation('Résultat inconnu');
  if (a.type === 'visite_planifiee' && !a.visite_le) throw new ErreurValidation('Date de visite requise');
  if (a.type === 'perdu' && !String(a.note || '').trim()) throw new ErreurValidation('Raison de la perte requise');
  return repo.insert('lead_activites', { ...a, lead_id: leadId, employe_id: uuid(employeId, 'employe') });
}

export async function reattribuer(repo, leadId, corps) {
  uuid(leadId, 'lead');
  return repo.update('leads', leadId, { assigne_a: uuid(corps.assigne_a, 'assigne_a') });
}

// Vendeurs du board (ordre du tour de rôle)
export async function listerVendeursBoard(repo) {
  const [membres, employes] = await Promise.all([
    repo.list('crm_vendeurs', { ordre: { colonne: 'ordre' } }),
    repo.list('employes', { select: 'id,prenom,nom,role,succursale_code,actif',
      filtre: { role: { op: 'in', val: ['Vendeur', 'Gérant de succursale', 'Direction', 'Admin tout'] }, actif: true },
      ordre: { colonne: 'prenom' } }),
  ]);
  return { membres, employes };
}

export async function majVendeursBoard(repo, corps) {
  const lignes = (corps.vendeurs || []).map((v, i) => ({
    employe_id: uuid(v.employe_id, 'employe_id'), ordre: Number.isInteger(v.ordre) ? v.ordre : i + 1, actif: v.actif !== false,
  }));
  if (!lignes.length) throw new ErreurValidation('Aucun vendeur');
  return repo.upsert('crm_vendeurs', lignes, { onConflict: 'employe_id' });
}

// Rapidité réelle + comparaison au tableau de quantification
export async function lireRapidite(repo) {
  const [objectifs, vendeurs, evaluation] = await Promise.all([
    repo.list('crm_objectifs', { ordre: { colonne: 'ordre' } }),
    repo.list('crm_rapidite_v', { ordre: { colonne: 'vendeur_nom' } }),
    repo.list('crm_evaluation_v', { select: 'employe_id,indicateur,valeur,cote', limite: 1000 }),
  ]);
  return { objectifs, vendeurs, evaluation };
}

const seuil = (v) => {
  if (v === null || v === undefined || v === '') return null;
  const n = Number(String(v).replace(',', '.'));
  if (!Number.isFinite(n) || n < 0) throw new ErreurValidation('Seuil invalide');
  return n;
};

export async function majObjectifs(repo, corps) {
  const resultats = [];
  for (const o of corps.objectifs || []) {
    if (!/^[a-z_]+$/.test(String(o.indicateur || ''))) throw new ErreurValidation('Indicateur invalide');
    resultats.push(await repo.updateWhere('crm_objectifs', { indicateur: o.indicateur },
      { seuil_bon: seuil(o.seuil_bon), seuil_moyen: seuil(o.seuil_moyen) }));
  }
  return resultats;
}
