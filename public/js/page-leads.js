// Leads (ADR-056) : « Mes leads » pour le vendeur, board principal pour le responsable.
import { initPage } from './bf-page.js?v=0.4.0';
import { api } from './bf-api.js?v=0.4.0';
import { remplir, h, message, param } from './bf-dom.js?v=0.4.0';
import { SUCCURSALES } from './bf-project-code.js?v=0.4.0';
import { STATUTS_LEAD, SOURCES_LEAD, pastilleLead, delaiLead, heure, voitBoard } from './bf-crm.js?v=0.4.0';

const user = await initPage();
if (user) {
  const zone = document.getElementById('contenu');
  const msg = h('p', { class: 'bf-message', role: 'alert' });
  const liste = h('div', { class: 'bf-liste' });
  const board = voitBoard(user);
  let vue = param('vue') || (board ? 'board' : 'mes');

  const choixVue = h('select', { 'aria-label': 'Vue' },
    h('option', { value: 'mes', selected: vue === 'mes' }, 'Mes leads'),
    board ? h('option', { value: 'board', selected: vue === 'board' }, 'Board principal (tous les leads)') : null);
  const choixStatut = h('select', { 'aria-label': 'Statut' },
    h('option', { value: 'actifs' }, 'Leads actifs'), h('option', { value: '' }, 'Tous les statuts'),
    Object.entries(STATUTS_LEAD).map(([v, t]) => h('option', { value: v }, t)));
  const choixVendeur = h('select', { 'aria-label': 'Vendeur', hidden: !board }, h('option', { value: '' }, 'Tous les vendeurs'));

  async function charger() {
    try {
      let leads = await api.get('leads', { vue, statut: choixStatut.value, vendeur: vue === 'board' ? choixVendeur.value : undefined });
      // Recherche de la barre du bas : nom, ville ou téléphone
      const q = (param('q') || '').trim().toLowerCase();
      if (q) leads = leads.filter((l) => [l.contact_nom, l.ville, l.contact_tel, l.contact_courriel].some((v) => String(v || '').toLowerCase().includes(q)));
      // Les leads à traiter d'abord : en retard, puis nouveaux
      const rang = (l) => (l.en_retard ? 0 : l.statut === 'nouveau' ? 1 : 2);
      leads.sort((a, b) => rang(a) - rang(b));   // tri stable : les plus récents restent en tête de chaque groupe
      remplir(liste, leads.length ? leads.map((l) => h('a', { class: `bf-ligne${l.en_retard ? ' bf-ligne--retard' : ''}`, href: `/lead?id=${l.id}` },
        h('strong', {}, l.contact_nom || 'Sans nom'), pastilleLead(l.statut),
        h('span', { class: 'bf-muet' }, [SOURCES_LEAD[l.source], l.campagne, l.ville].filter(Boolean).join(' | ')),
        vue === 'board' ? h('span', {}, l.vendeur_nom || 'Non attribué') : null,
        h('span', { class: 'bf-muet' }, `reçu ${heure(l.recu_le)}`),
        delaiLead(l))) : [h('p', { class: 'bf-muet' }, vue === 'mes' ? 'Aucun lead pour toi en ce moment.' : 'Aucun lead.')]);
    } catch (e) { message(msg, e.message); }
  }

  choixVue.addEventListener('change', () => { vue = choixVue.value; choixVendeur.hidden = vue !== 'board'; charger(); });
  choixStatut.addEventListener('change', charger);
  choixVendeur.addEventListener('change', charger);
  if (board) {
    api.get('crm-vendeurs').then(({ employes }) => choixVendeur.append(...employes.map((e) => h('option', { value: e.id }, `${e.prenom} ${e.nom}`))))
      .catch(() => {});
  }

  // Saisie manuelle (lead téléphonique ou magasin). Les leads Google et Facebook arriveront de Monday.
  const champ = (label, nom, attrs = {}) => h('label', {}, label, h('input', { name: nom, ...attrs }));
  const form = h('form', { class: 'bf-form', hidden: true },
    h('h2', {}, 'Nouveau lead'),
    h('p', { class: 'bf-muet' }, 'Attribué automatiquement au prochain vendeur (tour de rôle).'),
    h('div', { class: 'bf-grille2' },
      champ('Nom du contact *', 'contact_nom', { required: true }), champ('Téléphone', 'contact_tel', { type: 'tel' }),
      champ('Courriel', 'contact_courriel', { type: 'email' }), champ('Ville', 'ville'),
      h('label', {}, 'Source', h('select', { name: 'source' }, Object.entries(SOURCES_LEAD).map(([v, t]) => h('option', { value: v, selected: v === 'telephone' }, t)))),
      h('label', {}, 'Succursale *', h('select', { name: 'succursale_code', required: true },
        Object.entries(SUCCURSALES).map(([code, nom]) => h('option', { value: code, selected: code === user.succursale }, `${code} | ${nom}`))))),
    h('label', {}, 'Besoin', h('textarea', { name: 'besoin', rows: 2 })),
    h('div', { class: 'bf-actions' },
      h('button', { class: 'bf-bouton', type: 'submit' }, 'Créer le lead'),
      h('button', { class: 'bf-bouton bf-bouton--discret', type: 'button', onclick: () => { form.hidden = true; } }, 'Annuler')));
  form.addEventListener('submit', async (ev) => {
    ev.preventDefault();
    const f = new FormData(form);
    const v = (k) => (f.get(k) || '').toString().trim() || undefined;
    try {
      const lead = await api.post('leads', { contact_nom: v('contact_nom'), contact_tel: v('contact_tel'), contact_courriel: v('contact_courriel'),
        ville: v('ville'), source: v('source'), succursale_code: v('succursale_code'), besoin: v('besoin') });
      location.href = `/lead?id=${lead.id}`;
    } catch (e) { message(msg, e.message); }
  });

  remplir(zone,
    h('div', { class: 'bf-titre' }, h('h1', {}, 'Leads'),
      h('div', { class: 'bf-actions' },
        board ? h('a', { class: 'bf-bouton bf-bouton--discret', href: '/crm-rapidite' }, 'Rapidité des vendeurs') : null,
        h('button', { class: 'bf-bouton', type: 'button', onclick: () => { form.hidden = false; } }, 'Nouveau lead'))),
    h('p', { class: 'bf-muet' }, 'Les leads de Google et Facebook entrent dans Monday, puis arrivent ici (branchement Monday à activer).'),
    h('div', { class: 'bf-filtres' }, choixVue, choixStatut, choixVendeur), msg, form, liste);
  charger();
}
