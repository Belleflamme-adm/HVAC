// Extras à approuver (ADR-081) : feuilles d'extra envoyées par les sous-traitants.
// Simon, Mike et la planification approuvent ou refusent ligne par ligne (raison obligatoire au refus).
// Un oubli du vendeur approuvé avise le vendeur ; le sous-traitant est avisé de chaque décision.
import { initPage } from './bf-page.js?v=0.4.0';
import { api } from './bf-api.js?v=0.4.0';
import { remplir, h, message } from './bf-dom.js?v=0.4.0';
import { formatCents } from './bf-money.js?v=0.4.0';
import { CAUSES, pastilleExtra, marqueHorsListe } from './bf-extras.js?v=0.4.0';

const PLANIF = ['Admin tout', 'Direction', 'Coordonnateur'];
const qte = (n) => String(Number(n)).replace('.', ',');
const jour = (d) => (d ? new Date(d).toLocaleDateString('fr-CA', { day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' }) : '');

const user = await initPage();
if (user) {
  const zone = document.getElementById('contenu');
  const msg = h('p', { class: 'bf-message', role: 'alert' });
  const liste = h('div', { class: 'bf-jobs' });
  const filtre = h('select', { 'aria-label': 'Afficher' }, h('option', { value: 'soumis' }, 'À approuver'), h('option', { value: 'tous' }, 'Tous les extras décidés et en attente'));
  filtre.addEventListener('change', () => charger());

  async function decider(x, approuve, raison) {
    try {
      await api.patch('extras', { action: 'decider', id: x.id, approuve, raison });
      message(msg, `${x.code_projet} | ${x.description} : ${approuve ? 'approuvé' : 'refusé'}.`, 'ok');
      await charger();
    } catch (e) { message(msg, e.message); }
  }

  function ligne(x) {
    const zoneRefus = h('div');
    const refuser = () => {
      const champ = h('input', { 'aria-label': 'Raison du refus', placeholder: 'Raison du refus (le sous-traitant la verra)', maxlength: 500 });
      zoneRefus.replaceChildren(h('form', { class: 'bf-jobs__refus', onsubmit: (e) => { e.preventDefault(); decider(x, false, champ.value.trim()); } },
        champ, h('button', { class: 'bf-bouton bf-bouton--danger', type: 'submit' }, 'Refuser'),
        h('button', { class: 'bf-bouton bf-bouton--discret', type: 'button', onclick: () => zoneRefus.replaceChildren() }, 'Annuler')));
      champ.focus();
    };
    return h('div', { class: `bf-extra-ligne${x.hors_liste ? ' bf-extra-ligne--hors' : ''}` },
      h('div', { class: 'bf-extra-ligne__desc' },
        h('strong', {}, x.description), ' ', x.hors_liste ? marqueHorsListe() : null, ' ', pastilleExtra(x.statut),
        h('div', { class: 'bf-muet' }, [CAUSES[x.cause], x.soumis_le ? `envoyé le ${jour(x.soumis_le)}` : null].filter(Boolean).join(' | ')),
        x.justification ? h('div', {}, h('em', {}, 'Justification : '), x.justification) : null,
        x.note ? h('div', { class: 'bf-muet' }, `Note : ${x.note}`) : null,
        x.raison_refus ? h('div', { class: 'bf-jobs__raison' }, `Refusé : ${x.raison_refus}`) : null,
        x.decide_par_nom ? h('div', { class: 'bf-muet' }, `Décidé par ${x.decide_par_nom} le ${jour(x.decide_le)}`) : null),
      h('div', { class: 'bf-extra-ligne__montant' }, `${qte(x.quantite)} × ${formatCents(x.cout_cents)}`, h('strong', {}, formatCents(x.total_cents))),
      x.statut === 'soumis' ? h('div', { class: 'bf-extra-ligne__actions' },
        h('button', { type: 'button', class: 'bf-bouton', onclick: () => decider(x, true) }, '✓ Approuver'),
        h('button', { type: 'button', class: 'bf-bouton bf-bouton--discret', onclick: refuser }, 'Refuser'), zoneRefus) : null);
  }

  async function charger() {
    try {
      const extras = await api.get('extras', { statut: filtre.value });
      const parProjet = new Map();
      for (const x of extras) { if (!parProjet.has(x.projet_id)) parProjet.set(x.projet_id, []); parProjet.get(x.projet_id).push(x); }
      const attente = extras.filter((x) => x.statut === 'soumis');
      remplir(liste,
        h('div', { class: 'bf-jobs__resume' },
          h('span', {}, h('strong', {}, String(attente.length)), ' extra(s) à approuver'),
          h('span', {}, h('strong', {}, formatCents(attente.reduce((s, x) => s + x.total_cents, 0))), ' en attente'),
          h('span', {}, h('strong', {}, String(attente.filter((x) => x.cause === 'oubli_vendeur').length)), ' oubli(s) de vendeur'),
          h('span', {}, h('strong', {}, String(attente.filter((x) => x.hors_liste).length)), ' hors liste')),
        ...[...parProjet.values()].map((l) => h('article', { class: 'bf-jobs__carte' },
          h('div', { class: 'bf-jobs__tete' },
            h('div', {}, h('h2', {}, l[0].code_projet || 'Projet'), h('p', { class: 'bf-muet' }, [l[0].ville, l[0].sous_traitant_nom, l[0].vendeur_nom ? `vendeur : ${l[0].vendeur_nom}` : null].filter(Boolean).join(' | '))),
            h('a', { href: `/jobs?fournisseur=${l[0].fournisseur_id}`, class: 'bf-macro__lien' }, 'Voir ce que voit le sous-traitant')),
          ...l.map(ligne))),
        extras.length ? null : h('p', { class: 'bf-muet' }, filtre.value === 'soumis' ? 'Aucun extra à approuver. 👍' : 'Aucun extra.'));
    } catch (e) { message(msg, e.message); }
  }

  remplir(zone,
    h('div', { class: 'bf-titre' }, h('h1', {}, 'Extras à approuver'),
      h('span', { class: 'bf-muet' }, 'Les feuilles d\'extra des sous-traitants. Un extra de leur liste garde le prix de leur liste ; un extra hors liste porte un prix proposé et une justification.')),
    PLANIF.includes(user.role) ? [h('div', { class: 'bf-filtres' }, filtre), msg, liste] : h('p', { class: 'bf-message' }, 'Réservé à Simon, Mike et la planification.'));
  if (PLANIF.includes(user.role)) charger();
}
