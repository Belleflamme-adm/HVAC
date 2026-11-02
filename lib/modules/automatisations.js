// Moteur de règles (ADR-090) : lecture du suivi, modification des règles (Simon, Mike), relance des échecs,
// heures ouvrables et liens d'avis Google par succursale. La validation finale des étapes est en base (app.regle_valider).
import { uuid, ErreurValidation } from '../handler.js';

export const TYPES_ETAPES = ['attendre', 'attendre_avant_visite', 'si', 'sms', 'courriel', 'tache', 'notifier', 'noter_avis'];

export async function lireAutomatisations(repo) {
  const [regles, echecs, journal, messages, heures, succursales] = await Promise.all([
    repo.list('regles_suivi_v', { ordre: { colonne: 'nom' }, limite: 100 }),
    repo.list('executions', { select: 'id,regle_id,lead_id,projet_id,etape,derniere_erreur,essais,updated_at', filtre: { statut: 'echec' }, ordre: { colonne: 'updated_at', asc: false }, limite: 50 }),
    repo.list('execution_journal', { select: 'id,execution_id,etape,action,resultat,detail,le', ordre: { colonne: 'id', asc: false }, limite: 60 }),
    repo.list('communications_v', { select: 'id,lead_id,client_id,canal,statut,coordonnee_client,debut,sujet,contenu', filtre: { automatique: true }, ordre: { colonne: 'debut', asc: false }, limite: 40 }),
    repo.list('heures_succursales', { ordre: { colonne: 'jour' }, limite: 100 }),
    repo.list('succursales', { select: 'code,nom,lien_avis_google', filtre: { actif: true }, ordre: { colonne: 'code' } }),
  ]);
  return { regles, echecs, journal, messages, heures, succursales };
}

function verifierEtapes(etapes) {
  if (!Array.isArray(etapes) || !etapes.length || etapes.length > 30) throw new ErreurValidation('Étapes invalides');
  for (const e of etapes) {
    if (!TYPES_ETAPES.includes(e?.type)) throw new ErreurValidation(`Étape inconnue : ${e?.type}`);
    if (['sms', 'courriel'].includes(e.type) && !String(e.texte || '').trim()) throw new ErreurValidation('Texte du message requis');
    if (e.type === 'sms' && String(e.texte).length > 320) throw new ErreurValidation('Texto trop long (320 caractères au plus)');
  }
  return etapes;
}

export async function modifierAutomatisations(repo, corps = {}) {
  switch (corps.action) {
    case 'regle': {
      const patch = {};
      if (typeof corps.actif === 'boolean') patch.actif = corps.actif;
      if (corps.etapes !== undefined) patch.etapes = verifierEtapes(corps.etapes);
      if (!Object.keys(patch).length) throw new ErreurValidation('Rien à modifier');
      return repo.update('regles', uuid(corps.id), patch);
    }
    case 'relancer': await repo.rpc('hvac_execution_relancer', { p_id: uuid(corps.id) }); return { ok: true };
    case 'heures': {
      const heures = (corps.heures || []).map((h) => {
        if (!Number.isInteger(h.jour) || h.jour < 0 || h.jour > 6 || !/^\d{2}:\d{2}$/.test(h.ouvre) || !/^\d{2}:\d{2}$/.test(h.ferme)) throw new ErreurValidation('Heures invalides');
        return { jour: h.jour, ouvre: h.ouvre, ferme: h.ferme };
      });
      await repo.rpc('hvac_heures', { p_succ: String(corps.succursale_code), p_heures: heures }); return { ok: true };
    }
    case 'lien_avis': await repo.rpc('hvac_lien_avis', { p_succ: String(corps.succursale_code), p_lien: String(corps.lien || '') }); return { ok: true };
    default: throw new ErreurValidation('Action inconnue');
  }
}

// Cloche : mes avis et mes tâches ouvertes
export async function lireAvis(repo) {
  const [notifications, taches] = await Promise.all([
    repo.list('notifications', { select: 'id,type,titre,message,lien,lu_le,created_at', ordre: { colonne: 'created_at', asc: false }, limite: 60 }),
    repo.list('taches', { select: 'id,titre,details,lead_id,projet_id,echeance,created_at', filtre: { faite_le: { op: 'is', val: null } }, ordre: { colonne: 'echeance' }, limite: 100 }),
  ]);
  return { notifications, taches };
}

export async function modifierAvis(repo, corps = {}) {
  if (corps.action === 'lu') {
    if (corps.id) return repo.update('notifications', uuid(corps.id), { lu_le: new Date().toISOString() });
    throw new ErreurValidation('Avis requis');
  }
  if (corps.action === 'tache_faite') { await repo.rpc('hvac_tache_faite', { p_id: uuid(corps.id) }); return { ok: true }; }
  throw new ErreurValidation('Action inconnue');
}
