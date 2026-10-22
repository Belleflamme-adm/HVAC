// Devis imprimable : le navigateur l'enregistre en PDF (aucune dépendance de génération PDF).
import { exigerSession } from './bf-session.js?v=0.4.0';
import { api } from './bf-api.js?v=0.4.0';
import { remplir, h, param, dateFr, pct, LIBELLES_STATUT } from './bf-dom.js?v=0.4.0';
import { formatCents } from './bf-money.js?v=0.4.0';
import { ENTREPRISE, MODE_DEMO } from './bf-entreprise.js?v=0.4.0';

document.getElementById('imprimer').addEventListener('click', () => window.print());
const doc = document.getElementById('doc');

if (await exigerSession()) {
  try {
    const { devis: dv, lignes, client: c, site } = await api.get('devis-get', { id: param('id') });
    const nomClient = [c.prenom, c.nom].filter(Boolean).join(' ') || c.entreprise;
    document.title = `Devis #${dv.numero} | ${ENTREPRISE.nomCommercial}`;
    remplir(doc, 
      MODE_DEMO ? h('p', { class: 'demo' }, 'DOCUMENT DE DÉMONSTRATION | données fictives, sans valeur') : null,
      dv.statut === 'brouillon' ? h('p', { class: 'demo' }, 'BROUILLON | non envoyé au client') : null,
      h('header', { class: 'tete' },
        h('div', {}, h('h1', {}, ENTREPRISE.nomCommercial), h('p', {}, ENTREPRISE.nomLegal), h('p', {}, ENTREPRISE.adresse), h('p', {}, ENTREPRISE.telephone)),
        h('div', { class: 'droite' }, h('h2', {}, `Devis #${dv.numero}`),
          h('p', {}, `Date : ${dateFr(dv.date_devis)}`),
          dv.statut !== 'brouillon' ? h('p', {}, `Valide jusqu'au : ${dateFr(dv.valide_jusqu)}`) : null,
          h('p', {}, `Statut : ${LIBELLES_STATUT[dv.statut_effectif] || dv.statut_effectif}`),
          h('p', {}, `Conseiller : ${dv.vendeur_nom || ''}`))),
      h('section', { class: 'client' }, h('h3', {}, 'Client'), h('p', {}, nomClient), h('p', {}, `Code projet : ${dv.code_projet}`),
        c.telephone ? h('p', {}, c.telephone) : null, c.courriel ? h('p', {}, c.courriel) : null,
        site ? h('p', {}, `Lieu des travaux : ${site.adresse}, ${site.ville} ${site.code_postal || ''}`) : null),
      h('table', {},
        h('thead', {}, h('tr', {}, ['Description', 'Qté', 'Prix unitaire', 'Rabais', 'Montant'].map((t) => h('th', {}, t)))),
        h('tbody', {}, lignes.map((l) => h('tr', {},
          h('td', {}, l.description), h('td', { class: 'num' }, Number(l.quantite).toLocaleString('fr-CA')),
          h('td', { class: 'num' }, formatCents(l.prix_unitaire_cents)), h('td', { class: 'num' }, l.rabais_bp ? pct(l.rabais_bp) : ''),
          h('td', { class: 'num' }, formatCents(l.montant_cents)))))),
      h('table', { class: 'totaux' }, h('tbody', {},
        [['Sous-total', dv.sous_total_cents], ['TPS 5 %', dv.tps_cents], ['TVQ 9,975 %', dv.tvq_cents], ['Total', dv.total_cents],
         [`Dépôt à l'acceptation (${pct(dv.depot_bp)})`, dv.depot_cents], ['Solde, payable 72 h avant l\'installation', dv.total_cents - dv.depot_cents]]
          .map(([t, v]) => h('tr', { class: t === 'Total' ? 'fort' : null }, h('td', {}, t), h('td', { class: 'num' }, formatCents(v)))))),
      dv.notes_client ? h('section', {}, h('h3', {}, 'Notes'), h('p', { class: 'pre' }, dv.notes_client)) : null,
      h('footer', { class: 'pied' },
        h('p', {}, `Licence RBQ ${ENTREPRISE.rbq} | TPS ${ENTREPRISE.tps} | TVQ ${ENTREPRISE.tvq}`),
        h('p', {}, 'Ce devis expire 30 jours après son envoi. Prix en dollars canadiens.'),
        h('p', { class: 'signature' }, 'Acceptation du client : ______________________________   Date : ______________')));
  } catch (e) {
    doc.textContent = e.message;
  }
}
