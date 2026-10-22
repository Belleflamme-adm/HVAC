// Petits outils DOM sans innerHTML (aucune injection possible depuis les données).
export function h(tag, attrs = {}, ...enfants) {
  const el = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs || {})) {
    if (v === undefined || v === null || v === false) continue;
    if (k.startsWith('on') && typeof v === 'function') el.addEventListener(k.slice(2), v);
    else if (k === 'class') el.className = v;
    else if (k === 'dataset') Object.assign(el.dataset, v);
    else el.setAttribute(k, v === true ? '' : String(v));
  }
  for (const e of enfants.flat()) if (e !== null && e !== undefined && e !== false) el.append(e instanceof Node ? e : String(e));
  return el;
}

export const $ = (sel, racine = document) => racine.querySelector(sel);
export const param = (nom) => new URLSearchParams(location.search).get(nom);

export function message(el, texte, type = 'erreur') {
  el.textContent = texte || '';
  el.className = `bf-message bf-message--${type}`;
}

export const pct = (bp) => `${(bp / 100).toLocaleString('fr-CA', { maximumFractionDigits: 2 })} %`;
export const dateFr = (d) => (d ? new Date(`${String(d).slice(0, 10)}T12:00:00`).toLocaleDateString('fr-CA', { dateStyle: 'medium' }) : '');

export const LIBELLES_STATUT = {
  brouillon: 'Brouillon', envoye: 'Envoyé', accepte: 'Accepté', refuse: 'Refusé', expire: 'Expiré', annule: 'Annulé',
};
export const pastilleStatut = (s) => h('span', { class: `bf-pastille bf-pastille--${s}` }, LIBELLES_STATUT[s] || s);

// Remplace le contenu en ignorant les éléments absents (null, false, undefined).
export function remplir(el, ...enfants) {
  el.replaceChildren(...enfants.flat().filter((e) => e !== null && e !== undefined && e !== false));
}
