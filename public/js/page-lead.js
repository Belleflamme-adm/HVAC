// Fiche d'un lead (ADR-056) : prise en charge, appel / courriel / texto, visite planifiée dans Pointage, journal.
// Chaque geste est horodaté par la base : c'est ce qui mesure la rapidité du vendeur.
import { initPage } from './bf-page.js?v=0.4.0';
import { api } from './bf-api.js?v=0.4.0';
import { remplir, h, message, param } from './bf-dom.js?v=0.4.0';
import { SOURCES_LEAD, ACTIVITES, RESULTATS, pastilleLead, delaiLead, heure, duree, voitBoard } from './bf-crm.js?v=0.4.0';

const URL_POINTAGE = 'https://belleflammetime.netlify.app';   // app de Mike : lien seulement

const user = await initPage();
if (user) {
  const zone = document.getElementById('contenu');
  const msg = h('p', { class: 'bf-message', role: 'alert' });
  const id = param('id');

  const noter = async (corps) => {
    try { await api.post('lead-activite', corps, { id }); await charger(); message(msg, 'Enregistré.', 'ok'); }
    catch (e) { message(msg, e.message); }
  };

  // Formulaire de geste : un seul à la fois, selon le bouton choisi
  const panneau = h('div');
  function ouvrir(type) {
    const resultats = type === 'appel' ? ['joint', 'message_laisse', 'pas_de_reponse'] : null;
    const form = h('form', { class: 'bf-form bf-form--compact' },
      h('h2', {}, ACTIVITES[type]),
      resultats ? h('label', {}, 'Résultat', h('select', { name: 'resultat' }, resultats.map((r) => h('option', { value: r }, RESULTATS[r])))) : null,
      type === 'visite_planifiee' ? h('p', { class: 'bf-muet' },
        'Planifie la visite dans ', h('a', { href: URL_POINTAGE, target: '_blank', rel: 'noopener' }, 'Pointage'), ', puis inscris la date ici.') : null,
      type === 'visite_planifiee' ? h('label', {}, 'Date et heure de la visite *', h('input', { type: 'datetime-local', name: 'visite_le', required: true })) : null,
      h('label', {}, type === 'perdu' ? 'Raison de la perte *' : 'Note', h('textarea', { name: 'note', rows: 2, required: type === 'perdu' })),
      h('div', { class: 'bf-actions' },
        h('button', { class: 'bf-bouton', type: 'submit' }, 'Enregistrer'),
        h('button', { class: 'bf-bouton bf-bouton--discret', type: 'button', onclick: () => panneau.replaceChildren() }, 'Annuler')));
    form.addEventListener('submit', async (ev) => {
      ev.preventDefault();
      const f = new FormData(form);
      const visite = f.get('visite_le');
      await noter({ type, resultat: f.get('resultat') || undefined, note: (f.get('note') || '').toString().trim() || undefined,
        visite_le: visite ? new Date(visite).toISOString() : undefined });
      panneau.replaceChildren();
    });
    panneau.replaceChildren(form);
  }

  async function charger() {
    let res;
    try { res = await api.get('lead', { id }); } catch (e) { remplir(zone, h('h1', {}, 'Lead'), h('p', { class: 'bf-message' }, e.message)); return; }
    const { lead: l, activites } = res;
    const ferme = ['perdu', 'converti'].includes(l.statut);
    const tel = l.contact_tel ? l.contact_tel.replace(/[^\d+]/g, '') : null;

    const boutons = ferme
      ? [h('button', { class: 'bf-bouton bf-bouton--discret', type: 'button', onclick: () => noter({ type: 'reouvert' }) }, 'Réouvrir')]
      : [
        !l.pris_en_charge_le ? h('button', { class: 'bf-bouton', type: 'button', onclick: () => noter({ type: 'prise_en_charge' }) }, 'Je prends en charge') : null,
        h('button', { class: 'bf-bouton', type: 'button', onclick: () => ouvrir('appel') }, 'Appel'),
        h('button', { class: 'bf-bouton', type: 'button', onclick: () => ouvrir('courriel') }, 'Courriel'),
        h('button', { class: 'bf-bouton', type: 'button', onclick: () => ouvrir('texto') }, 'Texto'),
        h('button', { class: 'bf-bouton', type: 'button', onclick: () => ouvrir('visite_planifiee') }, 'Visite planifiée'),
        h('button', { class: 'bf-bouton bf-bouton--discret', type: 'button', onclick: () => ouvrir('note') }, 'Note'),
        h('button', { class: 'bf-bouton bf-bouton--discret', type: 'button', onclick: () => ouvrir('perdu') }, 'Perdu'),
      ];

    // Réattribution : board principal seulement
    let reattribution = null;
    if (voitBoard(user)) {
      const choix = h('select', { 'aria-label': 'Vendeur' });
      api.get('crm-vendeurs').then(({ employes }) => choix.append(...employes.map((e) =>
        h('option', { value: e.id, selected: e.id === l.assigne_a }, `${e.prenom} ${e.nom}`)))).catch(() => {});
      reattribution = h('div', { class: 'bf-filtres' }, h('span', { class: 'bf-muet' }, 'Réattribuer à'), choix,
        h('button', { class: 'bf-bouton bf-bouton--discret', type: 'button', onclick: async () => {
          try { await api.patch('lead', { assigne_a: choix.value }, { id }); await charger(); message(msg, 'Lead réattribué.', 'ok'); }
          catch (e) { message(msg, e.message); }
        } }, 'Réattribuer'));
    }

    remplir(zone,
      h('p', {}, h('a', { href: '/leads' }, '← Leads')),
      h('div', { class: 'bf-titre' }, h('h1', {}, l.contact_nom || 'Lead'), pastilleLead(l.statut)),
      h('section', { class: 'bf-carte-section' },
        h('dl', { class: 'bf-fiche' },
          h('dt', {}, 'Téléphone'), h('dd', {}, tel ? h('a', { href: `tel:${tel}` }, l.contact_tel) : 'n/d'),
          h('dt', {}, 'Courriel'), h('dd', {}, l.contact_courriel ? h('a', { href: `mailto:${l.contact_courriel}` }, l.contact_courriel) : 'n/d'),
          h('dt', {}, 'Ville'), h('dd', {}, l.ville || 'n/d'),
          h('dt', {}, 'Source'), h('dd', {}, [SOURCES_LEAD[l.source], l.campagne].filter(Boolean).join(' | ')),
          h('dt', {}, 'Reçu'), h('dd', {}, heure(l.recu_le)),
          h('dt', {}, 'Vendeur'), h('dd', {}, l.vendeur_nom || 'Non attribué'),
          h('dt', {}, 'Rapidité'), h('dd', {}, delaiLead(l) || 'n/d'),
          l.visite_prevue_le ? h('dt', {}, 'Visite') : null, l.visite_prevue_le ? h('dd', {}, heure(l.visite_prevue_le)) : null),
        l.besoin ? h('p', {}, l.besoin) : null),
      msg,
      h('div', { class: 'bf-actions' }, boutons),
      panneau,
      reattribution,
      h('h2', {}, 'Journal'),
      h('ol', { class: 'bf-journal' }, [...activites].reverse().map((a) => h('li', {},
        h('strong', {}, ACTIVITES[a.type] || a.type),
        a.resultat ? ` (${RESULTATS[a.resultat] || a.resultat})` : '',
        h('span', { class: 'bf-muet' }, ` | ${heure(a.fait_le)} | ${duree((new Date(a.fait_le) - new Date(l.recu_le)) / 60000)} après l'arrivée`),
        a.visite_le ? h('div', {}, `Visite : ${heure(a.visite_le)}`) : null,
        a.note ? h('div', {}, a.note) : null))));
  }
  charger();
}
