// Révision d'une liste de prix reçue d'un sous-traitant (ADR-061) : prix donnés, prix client calculés,
// comparaison avec le prix en vigueur, signature et date, puis approbation (Simon, Mike) ou annulation.
import { initPage } from './bf-page.js?v=0.4.0';
import { api } from './bf-api.js?v=0.4.0';
import { remplir, h, message, param, dateFr } from './bf-dom.js?v=0.4.0';
import { formatCents } from './bf-money.js?v=0.4.0';

const UNITES = { forfait: 'forfait', tete: 'par tête', pied: 'par pied', sortie: 'par sortie', heure: 'par heure', unite: 'par unité', livre: 'par livre' };
const STATUTS = { envoyee: 'Envoyée, en attente du sous-traitant', recue: 'Reçue : à approuver', approuvee: 'Approuvée', annulee: 'Annulée' };

const user = await initPage();
if (user) {
  const zone = document.getElementById('contenu');
  const msg = h('p', { class: 'bf-message', role: 'alert' });
  const id = param('id');
  const admin = user.role === 'Admin tout' || user.role === 'Direction';

  async function charger() {
    let d, o;
    try { [d, o] = await Promise.all([api.get('prix-demande', { id }), api.get('installation-options')]); }
    catch (e) { remplir(zone, h('h1', {}, 'Demande de prix'), h('p', { class: 'bf-message' }, e.message)); return; }
    const { demande, lignes } = d;
    const nomSt = o.sousTraitants.find((f) => f.id === demande.fournisseur_id)?.nom || 'Sous-traitant';
    const prixClient = (c) => Math.round(c * 10000 / (10000 - o.margeBp));
    const enVigueur = (typeId) => o.grille.find((g) => g.fournisseur_id === demande.fournisseur_id && g.type_travail_id === typeId);
    const action = async (quoi, texte) => {
      try { const r = await api.post('prix-demande', {}, { id, action: quoi }); message(msg, quoi === 'approuver' ? `${r.tarifs} prix approuvés : ils servent maintenant aux prix clients.` : texte, 'ok'); charger(); }
      catch (e) { message(msg, e.message); }
    };
    remplir(zone,
      h('p', {}, h('a', { href: `/installation-grille?fournisseur=${demande.fournisseur_id}` }, '← Listes de prix')),
      h('div', { class: 'bf-titre' }, h('h1', {}, `Liste de prix | ${nomSt}`), h('span', { class: `bf-pastille bf-pastille--demande-${demande.statut}` }, STATUTS[demande.statut])),
      msg,
      h('section', { class: 'bf-carte-section' },
        h('dl', { class: 'bf-fiche' },
          h('dt', {}, 'Envoyée le'), h('dd', {}, dateFr(demande.created_at)),
          h('dt', {}, 'Lien valide jusqu\'au'), h('dd', {}, dateFr(demande.expire_le)),
          h('dt', {}, 'Ouverte le'), h('dd', {}, demande.ouverte_le ? dateFr(demande.ouverte_le) : 'pas encore'),
          demande.message ? h('dt', {}, 'Message') : null, demande.message ? h('dd', {}, demande.message) : null,
          demande.signe_le ? h('dt', {}, 'Signée par') : null, demande.signe_le ? h('dd', {}, `${demande.signataire_nom}, le ${new Date(demande.signe_le).toLocaleString('fr-CA', { dateStyle: 'long', timeStyle: 'short' })}`) : null,
          demande.valide_jusqu ? h('dt', {}, 'Prix valides jusqu\'au') : null, demande.valide_jusqu ? h('dd', {}, h('strong', {}, dateFr(demande.valide_jusqu))) : null),
        demande.signature_png ? h('figure', { class: 'bf-signature' }, h('img', { src: demande.signature_png, alt: `Signature de ${demande.signataire_nom}` }), h('figcaption', { class: 'bf-muet' }, 'Signature électronique')) : null),
      h('div', { class: 'bf-table-zone' }, h('table', { class: 'bf-table' },
        h('thead', {}, h('tr', {}, ['Travail', 'Unité', 'Prix donné', 'Prix client', 'Prix en vigueur', 'Note'].map((t) => h('th', {}, t)))),
        h('tbody', {}, lignes.map((l) => {
          const actuel = enVigueur(l.type_travail_id);
          const ecart = actuel && l.cout_cents ? Math.round((l.cout_cents - actuel.cout_cents) * 1000 / actuel.cout_cents) / 10 : null;
          return h('tr', {},
            h('td', {}, h('strong', {}, l.code), h('div', { class: 'bf-muet' }, l.nom)),
            h('td', {}, UNITES[l.unite] || l.unite),
            h('td', { class: 'num' }, l.non_offert ? h('span', { class: 'bf-muet' }, 'N\'offre pas ce service') : l.cout_cents ? formatCents(l.cout_cents) : '…'),
            h('td', { class: 'num' }, l.cout_cents ? formatCents(prixClient(l.cout_cents)) : ''),
            h('td', { class: 'num' }, actuel ? formatCents(actuel.cout_cents) : h('span', { class: 'bf-muet' }, 'aucun'),
              ecart !== null && ecart !== 0 ? h('div', { class: ecart > 0 ? 'bf-retard' : 'bf-message--ok' }, `${ecart > 0 ? '+' : ''}${ecart} %`) : null),
            h('td', {}, l.note || ''));
        })))),
      h('div', { class: 'bf-actions' },
        admin && demande.statut === 'recue' ? h('button', { class: 'bf-bouton', type: 'button', onclick: () => action('approuver') }, 'Approuver ces prix') : null,
        ['envoyee', 'recue'].includes(demande.statut) ? h('button', { class: 'bf-bouton bf-bouton--discret', type: 'button', onclick: () => action('annuler', 'Demande annulée : le lien ne fonctionne plus.') }, demande.statut === 'envoyee' ? 'Annuler la demande (désactive le lien)' : 'Refuser cette liste') : null),
      demande.statut === 'recue' ? h('p', { class: 'bf-muet' }, 'À l\'approbation, chaque prix devient un tarif daté du jour de la signature, valide un an. L\'ancien prix reste dans l\'historique.') : null);
  }
  charger();
}
