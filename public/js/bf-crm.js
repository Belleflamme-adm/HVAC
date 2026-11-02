// Affichage commun du CRM (ADR-056) : libellés, délais, cotes du tableau de quantification.
import { h } from './bf-dom.js?v=0.4.0';

export const STATUTS_LEAD = {
  nouveau: 'Nouveau', pris_en_charge: 'Pris en charge', contacte: 'Contacté', qualifie: 'Qualifié',
  inspection_planifiee: 'Visite planifiée', converti: 'Vendu', perdu: 'Perdu',
};
export const SOURCES_LEAD = {
  google: 'Google', facebook: 'Facebook', instagram: 'Instagram', site_web: 'Site web', telephone: 'Téléphone',
  magasin: 'Magasin', reference: 'Référence', salon: 'Salon', autre: 'Autre', appel_manque: 'Appel manqué',
};
export const ACTIVITES = {
  attribution: 'Attribué', prise_en_charge: 'Pris en charge', appel: 'Appel', courriel: 'Courriel', texto: 'Texto',
  note: 'Note', visite_planifiee: 'Visite planifiée', perdu: 'Perdu', reouvert: 'Réouvert', vendu: 'Vendu (soumission signée)', visite_annulee: 'Visite annulée',
};
// Types de demande : chaque vendeur est qualifié pour certains types (ADR-058)
export const TYPES_DEMANDE = { mural_simple: 'Murale simple', mural_multi: 'Murale multi', central: 'Système central', bienergie: 'Biénergie' };

// Étampes (ADR-066) : icône + texte en majuscules, fond plein, à la manière du « ✓ PRÉPARÉ » de l'app de Mike.
// Icônes en SVG (traits), aucune librairie externe.
const ICONES = {
  nouveau: 'M12 3v4M12 17v4M3 12h4M17 12h4M6.3 6.3l2.5 2.5M15.2 15.2l2.5 2.5M6.3 17.7l2.5-2.5M15.2 8.8l2.5-2.5',
  pris_en_charge: 'M12 12a4 4 0 100-8 4 4 0 000 8zM4 21c0-4 3.6-6 8-6s8 2 8 6',
  contacte: 'M5 4h4l2 5-2.5 1.5a11 11 0 005 5L15 13l5 2v4a2 2 0 01-2 2A16 16 0 013 6a2 2 0 012-2z',
  qualifie: 'M12 3l2.6 5.6 6.1.6-4.6 4.1 1.3 6L12 16.3 6.6 19.3l1.3-6L3.3 9.2l6.1-.6z',
  inspection_planifiee: 'M4 6h16v14H4zM4 10h16M8 3v5M16 3v5',
  converti: 'M4 12.5l5 5L20 6.5',
  perdu: 'M6 6l12 12M18 6L6 18',
  mural_simple: 'M3 6h18v7H3zM7 17v3M12 17v3M17 17v3',
  mural_multi: 'M2 4h9v6H2zM13 4h9v6h-9zM4.5 13v2.5M8.5 13v2.5M15.5 13v2.5M19.5 13v2.5M7 19h10',
  central: 'M3 11l9-7 9 7v9H3zM9 20v-6h6v6',
  bienergie: 'M12 3c1.5 3.5 5.5 5.5 5.5 10.5a5.5 5.5 0 01-11 0c0-2.8 1.6-3.8 1.9-6.5 1.6 1 2.6 2.6 3 3.8.6-2.6.1-5.1.6-7.8z',
  a_preciser: 'M9 9a3 3 0 115 2.2c-1 .8-2 1.4-2 2.8M12 18v.5',
};
function icone(nom) {
  const NS = 'http://www.w3.org/2000/svg';
  const svg = document.createElementNS(NS, 'svg');
  svg.setAttribute('viewBox', '0 0 24 24');
  svg.setAttribute('aria-hidden', 'true');
  const p = document.createElementNS(NS, 'path');
  p.setAttribute('d', ICONES[nom] || ICONES.a_preciser);
  svg.append(p);
  return svg;
}
export const etampe = (cle, texte, classe = '') => h('span', { class: `bf-etampe bf-etampe--${cle} ${classe}`.trim(), title: texte }, icone(cle), h('span', {}, texte));

export const pastilleType = (t) => (t ? etampe(t, TYPES_DEMANDE[t] || t, 'bf-etampe--type') : etampe('a_preciser', 'Type à préciser', 'bf-etampe--type'));
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

export const pastilleLead = (s) => etampe(s, STATUTS_LEAD[s] || s);
// Grande étampe « PERDU » en diagonale sur la fiche (le contenu reste lisible et cliquable dessous)
export const filigranePerdu = () => h('div', { class: 'bf-filigrane-perdu', 'aria-hidden': 'true' }, h('span', {}, 'Perdu'));
export const pastilleCote = (c) => h('span', { class: `bf-pastille bf-pastille--cote-${c}` }, COTES[c] || c);

// Délai du lead : premier contact fait, ou attente en cours (en rouge si le seuil est dépassé)
export function delaiLead(l) {
  if (l.premier_contact_le) return h('span', { class: 'bf-muet' }, `contacté en ${duree(l.minutes_premier_contact)}`);
  if (['perdu', 'converti'].includes(l.statut)) return null;
  return h('span', { class: l.en_retard ? 'bf-retard' : 'bf-muet' }, `en attente depuis ${duree(l.minutes_en_attente)}`);
}

export const voitBoard = (user) => ['Admin tout', 'Direction', 'Gérant de succursale', 'Coordonnateur'].includes(user?.role);
