import { initPage, estApprobateur } from './bf-page.js?v=0.4.0';
import { api } from './bf-api.js?v=0.4.0';
import { remplir, h, message, dateFr, pct, pastilleStatut, LIBELLES_STATUT } from './bf-dom.js?v=0.4.0';
import { formatCents } from './bf-money.js?v=0.4.0';

const user = await initPage();
if (user) {
  const zone = document.getElementById('contenu');
  const msg = h('p', { class: 'bf-message', role: 'alert' });
  const liste = h('div', { class: 'bf-liste' });
  const filtre = h('select', { 'aria-label': 'Filtrer par statut' },
    h('option', { value: '' }, 'Tous les statuts'),
    Object.entries(LIBELLES_STATUT).map(([v, t]) => h('option', { value: v }, t)));
  const miens = h('input', { type: 'checkbox' });
  const approbations = h('section', { class: 'bf-carte-section', hidden: true });

  async function chargerDevis() {
    try {
      const devis = await api.get('devis-list', { statut: filtre.value, vendeur_id: miens.checked ? user.id : undefined });
      liste.replaceChildren(...(devis.length ? devis.map((d) => h('a', { class: 'bf-ligne', href: `/devis-edition?id=${d.id}` },
        h('strong', {}, `#${d.numero}`), h('span', { class: 'bf-muet' }, d.code_projet), pastilleStatut(d.statut_effectif),
        h('span', {}, [d.client_prenom, d.client_nom].filter(Boolean).join(' ') || d.client_entreprise),
        h('span', {}, formatCents(d.total_cents)),
        d.bloque_par_rabais ? h('span', { class: 'bf-pastille bf-pastille--attente' }, 'Rabais à approuver') : null,
        h('span', { class: 'bf-muet' }, `${d.succursale_code} | ${d.vendeur_nom || ''} | ${dateFr(d.date_devis)}`)))
        : [h('p', { class: 'bf-muet' }, 'Aucun devis.')]));
    } catch (e) { message(msg, e.message); }
  }

  async function chargerApprobations() {
    if (!estApprobateur(user)) return;
    try {
      const demandes = await api.get('approbations');
      approbations.hidden = demandes.length === 0;
      const decider = async (id, decision) => {
        const commentaire = decision === 'refusee' ? prompt('Raison du refus (optionnel)') : null;
        try { await api.patch('approbations', { id, decision, commentaire }); chargerApprobations(); chargerDevis(); }
        catch (e) { message(msg, e.message); }
      };
      approbations.replaceChildren(h('h2', {}, `Rabais à approuver (${demandes.length})`),
        ...demandes.map((a) => h('div', { class: 'bf-ligne' },
          h('a', { href: `/devis-edition?id=${a.devis_id}` }, h('strong', {}, a.devis?.numero ? `#${a.devis.numero}` : 'Devis')),
          h('span', {}, a.devis_lignes?.description || ''),
          h('span', {}, a.rabais_mode ? `Rabais global de ${a.rabais_mode === 'pourcentage' ? pct(a.rabais_valeur) : formatCents(a.rabais_valeur)}`
            : `${pct(a.rabais_bp)} demandé, plafond ${pct(a.plafond_bp)}`),
          h('span', { class: 'bf-muet' }, `${a.demandeur ? `${a.demandeur.prenom} ${a.demandeur.nom}` : ''} : ${a.motif || ''}`),
          h('span', { class: 'bf-actions' },
            h('button', { class: 'bf-bouton', type: 'button', onclick: () => decider(a.id, 'approuvee') }, 'Approuver'),
            h('button', { class: 'bf-bouton bf-bouton--discret', type: 'button', onclick: () => decider(a.id, 'refusee') }, 'Refuser')))));
    } catch (e) { message(msg, e.message); }
  }

  filtre.addEventListener('change', chargerDevis);
  miens.addEventListener('change', chargerDevis);
  remplir(zone, 
    h('div', { class: 'bf-titre' }, h('h1', {}, 'Devis'), h('a', { class: 'bf-bouton', href: '/clients' }, 'Nouveau devis (choisir un client)')),
    msg, approbations,
    h('div', { class: 'bf-filtres' }, filtre, h('label', { class: 'bf-case' }, miens, 'Mes devis seulement')),
    liste);
  chargerApprobations();
  chargerDevis();
}
