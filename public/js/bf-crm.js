// Affichage commun du CRM (ADR-056) : libellés, délais, cotes du tableau de quantification.
import { h } from './bf-dom.js?v=0.4.0';

export const STATUTS_LEAD = {
  nouveau: 'Nouveau', pris_en_charge: 'Pris en charge', contacte: 'Contacté', qualifie: 'Qualifié',
  inspection_planifiee: 'Visite planifiée', converti: 'Vendu', perdu: 'Perdu',
};
export const SOURCES_LEAD = {
  google: 'Google', facebook: 'Facebook', instagram: 'Instagram', site_web: 'Site web', telephone: 'Téléphone',
  magasin: 'Magasin', reference: 'Référence', salon: 'Salon', autre: 'Autre',
};
export const ACTIVITES = {
  attribution: 'Attribué', prise_en_charge: 'Pris en charge', appel: 'Appel', courriel: 'Courriel', texto: 'Texto',
  note: 'Note', visite_planifiee: 'Visite planifiée', perdu: 'Perdu', reouvert: 'Réouvert',
};
export const RESULTATS = { joint: 'joint', message_laisse: 'message laissé', pas_de_reponse: 'pas de réponse', envoye: 'envoyé' };
export const COTES = { bon: 'Bon', moyen: 'Moyen', a_ameliorer: 'À améliorer', non_evalue: 'Non évalué' };

// 75 -> « 1 h 15 », 2900 -> « 2 j 0 h »
export function duree(minutes) {
  if (minutes === null || minutes === undefined) return '';
  const m = Math.max(0, Math.round(Number(minutes)));
  if (m < 60) return `${m} min`;
  if (m < 60 * 24) return `${Math.floor(m / 60)} h ${String(m % 60).padStart(2, '0')}`;
  return `${Math.floor(m / 1440)} j ${Math.floor((m % 1440) / 60)} h`;
}

export const heure = (d) => (d ? new Date(d).toLocaleString('fr-CA', { dateStyle: 'medium', timeStyle: 'short' }) : '');

export const pastilleLead = (s) => h('span', { class: `bf-pastille bf-pastille--lead-${s}` }, STATUTS_LEAD[s] || s);
export const pastilleCote = (c) => h('span', { class: `bf-pastille bf-pastille--cote-${c}` }, COTES[c] || c);

// Délai du lead : premier contact fait, ou attente en cours (en rouge si le seuil est dépassé)
export function delaiLead(l) {
  if (l.premier_contact_le) return h('span', { class: 'bf-muet' }, `contacté en ${duree(l.minutes_premier_contact)}`);
  if (['perdu', 'converti'].includes(l.statut)) return null;
  return h('span', { class: l.en_retard ? 'bf-retard' : 'bf-muet' }, `en attente depuis ${duree(l.minutes_en_attente)}`);
}

export const voitBoard = (user) => ['Admin tout', 'Direction', 'Gérant de succursale', 'Coordonnateur'].includes(user?.role);
