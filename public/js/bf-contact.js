// Contact du client (ADR-067) : boutons courriel, téléphone, texto et carte (en haut à droite, comme l'app de Mike)
// et historique des communications (appels avec enregistrement et transcription, textos, courriels).
import { api } from './bf-api.js?v=0.4.0';
import { h, remplir, message } from './bf-dom.js?v=0.4.0';
import { lienCarte } from './bf-contact-liens.js?v=0.4.0';

const NS = 'http://www.w3.org/2000/svg';
const ICONES = {
  courriel: 'M3 6h18v12H3zM3 7l9 6 9-6',
  appel: 'M5 4h4l2 5-2.5 1.5a11 11 0 005 5L15 13l5 2v4a2 2 0 01-2 2A16 16 0 013 6a2 2 0 012-2z',
  texto: 'M4 5h16v11H9l-5 4zM8 10h.01M12 10h.01M16 10h.01',
  carte: 'M12 21s-7-6.2-7-11.5a7 7 0 0114 0C19 14.8 12 21 12 21zM12 12a2.5 2.5 0 100-5 2.5 2.5 0 000 5z',
};
function icone(nom) {
  const svg = document.createElementNS(NS, 'svg');
  svg.setAttribute('viewBox', '0 0 24 24'); svg.setAttribute('aria-hidden', 'true');
  const p = document.createElementNS(NS, 'path'); p.setAttribute('d', ICONES[nom]);
  svg.append(p);
  return svg;
}

const LIBELLES = { courriel: 'Courriel', appel: 'Appeler', texto: 'Texto', carte: 'Carte' };

// { tel, courriel, site, client_id, lead_id, msg } -> rangée de 4 boutons ronds
export function barreContact({ tel, courriel, site, client_id, lead_id, msg }) {
  const bouton = (canal, coordonnee, manque) => {
    const b = h('button', { class: `bf-contact__bouton bf-contact__bouton--${canal}`, type: 'button',
      title: coordonnee ? `${LIBELLES[canal]} : ${coordonnee}` : manque, 'aria-label': coordonnee ? `${LIBELLES[canal]} ${coordonnee}` : manque,
      disabled: !coordonnee }, icone(canal));
    b.addEventListener('click', async () => {
      try {
        const r = await api.post('communication-lancer', { canal, coordonnee, client_id, lead_id });
        if (r.lien) window.location.assign(r.lien);
        else if (r.message && msg) message(msg, r.message, 'ok');
        // L'historique se recharge (la communication y apparaît une fois enregistrée)
        document.dispatchEvent(new CustomEvent('bf:communications'));
      } catch (e) { if (msg) message(msg, e.message); }
    });
    return b;
  };
  const carte = lienCarte(site);
  return h('div', { class: 'bf-contact', role: 'group', 'aria-label': 'Contacter le client' },
    bouton('courriel', courriel, 'Aucun courriel au dossier'),
    bouton('appel', tel, 'Aucun téléphone au dossier'),
    bouton('texto', tel, 'Aucun téléphone au dossier'),
    carte ? h('a', { class: 'bf-contact__bouton bf-contact__bouton--carte', href: carte, target: '_blank', rel: 'noopener noreferrer',
      title: `Carte : ${[site.adresse, site.ville].filter(Boolean).join(', ')}`, 'aria-label': 'Voir le client sur la carte' }, icone('carte'))
      : h('button', { class: 'bf-contact__bouton bf-contact__bouton--carte', type: 'button', disabled: true, title: 'Aucune adresse au dossier', 'aria-label': 'Aucune adresse au dossier' }, icone('carte')));
}

const quand = (d) => new Date(d).toLocaleString('fr-CA', { day: 'numeric', month: 'short', year: 'numeric', hour: '2-digit', minute: '2-digit' });
export const duree = (s) => {
  if (s === null || s === undefined) return '';
  const m = Math.floor(s / 60); const r = s % 60;
  return m ? `${m} min ${String(r).padStart(2, '0')} s` : `${r} s`;
};
const STATUTS = { manque: 'manqué', messagerie: 'message laissé', echec: 'échec' };
const TITRES = { appel: 'Appel', texto: 'Texto', courriel: 'Courriel' };

// { client_id } ou { lead_id } -> section « Communications » avec filtres et recherche
export function historiqueComms(cible) {
  const zone = h('section', { class: 'bf-carte-section bf-comms', 'aria-label': 'Communications' });
  let tout = []; let filtre = ''; let terme = '';
  const msg = h('p', { class: 'bf-message', role: 'alert' });
  const liste = h('ol', { class: 'bf-comms__liste' });
  const recherche = h('input', { type: 'search', placeholder: 'Chercher dans les appels, textos et courriels…', 'aria-label': 'Chercher dans les communications' });
  const puces = h('div', { class: 'bf-comms__filtres', role: 'group', 'aria-label': 'Type de communication' });

  const ecouter = async (c, zoneAudio, bouton) => {
    bouton.disabled = true;
    try {
      const r = await api.get('communication-audio', { id: c.id });
      if (r.url) {
        const audio = h('audio', { controls: true, preload: 'none', src: r.url });
        remplir(zoneAudio, audio);
        audio.play().catch(() => {});
      } else remplir(zoneAudio, h('p', { class: 'bf-muet' }, r.message));
    } catch (e) { remplir(zoneAudio, h('p', { class: 'bf-message' }, e.message)); bouton.disabled = false; }
  };

  const element = (c) => {
    const tete = h('div', { class: 'bf-comms__tete' },
      h('span', { class: `bf-comms__icone bf-comms__icone--${c.canal}` }, icone(c.canal)),
      h('strong', {}, `${TITRES[c.canal]} ${c.direction === 'sortant' ? 'sortant' : 'entrant'}`),
      h('span', {}, quand(c.debut)),
      c.canal === 'appel' && c.duree_s ? h('span', { class: 'bf-pastille' }, duree(c.duree_s)) : null,
      STATUTS[c.statut] ? h('span', { class: 'bf-pastille bf-pastille--attente' }, STATUTS[c.statut]) : null,
      h('span', { class: 'bf-muet' }, c.employe_nom || (c.direction === 'entrant' ? 'client' : '')));
    const corps = [];
    if (c.resume) corps.push(h('p', { class: 'bf-comms__resume' }, h('strong', {}, 'Résumé : '), c.resume));
    if (c.canal === 'texto' && c.contenu) corps.push(h('p', { class: `bf-comms__bulle bf-comms__bulle--${c.direction}` }, c.contenu));
    if (c.canal === 'courriel') {
      if (c.sujet) corps.push(h('p', {}, h('strong', {}, c.sujet)));
      if (c.contenu) corps.push(h('details', {}, h('summary', {}, 'Voir le courriel'), h('p', { class: 'bf-comms__texte' }, c.contenu)));
    }
    if (c.canal === 'appel') {
      const zoneAudio = h('div', { class: 'bf-comms__audio' });
      const actions = h('div', { class: 'bf-actions' });
      if (c.a_enregistrement) {
        const b = h('button', { class: 'bf-bouton bf-bouton--discret', type: 'button' },
          `▶ Écouter l'enregistrement${c.enregistrement_duree_s ? ` (${duree(c.enregistrement_duree_s)})` : ''}`);
        b.addEventListener('click', () => ecouter(c, zoneAudio, b));
        actions.append(b);
      } else if (c.enregistrement_efface_le) {
        actions.append(h('span', { class: 'bf-muet' }, 'Enregistrement effacé selon la règle de conservation'));
      }
      corps.push(actions, zoneAudio);
      if (c.transcription) corps.push(h('details', {}, h('summary', {}, 'Voir la transcription'), h('p', { class: 'bf-comms__texte' }, c.transcription)));
    }
    return h('li', { class: `bf-comms__item bf-comms__item--${c.canal}` }, tete, ...corps);
  };

  const afficher = () => {
    const t = terme.toLowerCase();
    const vus = tout.filter((c) => (!filtre || c.canal === filtre)
      && (!t || [c.transcription, c.resume, c.contenu, c.sujet, c.employe_nom].some((v) => String(v || '').toLowerCase().includes(t))));
    const n = (canal) => tout.filter((c) => c.canal === canal).length;
    remplir(puces, ...[['', `Tout (${tout.length})`], ['appel', `Appels (${n('appel')})`], ['texto', `Textos (${n('texto')})`], ['courriel', `Courriels (${n('courriel')})`]]
      .map(([v, l]) => h('button', { type: 'button', class: `bf-puce${filtre === v ? ' bf-puce--active' : ''}`, 'aria-pressed': String(filtre === v),
        onclick: () => { filtre = v; afficher(); } }, l)));
    remplir(liste, ...(vus.length ? vus.map(element) : [h('li', { class: 'bf-muet' }, tout.length ? 'Rien ne correspond.'
      : 'Aucune communication. Une fois l\'app branchée sur celle de Mike, chaque appel, texto et courriel s\'inscrira ici automatiquement, avec l\'heure, la durée, l\'enregistrement et la transcription.')]));
  };
  recherche.addEventListener('input', () => { terme = recherche.value.trim(); afficher(); });

  const charger = async () => {
    remplir(zone, h('h2', {}, 'Communications'), h('p', { class: 'bf-muet' }, 'Chargement…'));
    try { tout = await api.get('communications', cible); } catch (e) { remplir(zone, h('h2', {}, 'Communications'), msg); message(msg, e.message); return; }
    remplir(zone, h('h2', {}, 'Communications'),
      h('p', { class: 'bf-muet' }, 'Appels, textos et courriels avec ce client, les plus récents en premier. Chaque écoute d\'un enregistrement est journalisée (Loi 25).'),
      h('div', { class: 'bf-filtres' }, puces, recherche), liste);
    afficher();
  };
  charger();
  const surNouvelle = () => {
    if (!zone.isConnected) { document.removeEventListener('bf:communications', surNouvelle); return; }
    charger();
  };
  document.addEventListener('bf:communications', surNouvelle);
  return zone;
}
