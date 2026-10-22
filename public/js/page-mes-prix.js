// « Ma liste de prix » (ADR-062) : le sous-traitant modifie ses prix quand il veut.
// - Le nouveau prix s'applique aux NOUVEAUX devis.
// - Avant d'enregistrer, il voit les devis actifs (soumissions envoyées non expirées, ou acceptées) qui utilisent
//   ces travaux, avec le prix qu'il avait donné : il doit les honorer jusqu'à leur échéance.
// Simon, Mike et la planification ouvrent la même page avec ?fournisseur=.
import { initPage } from './bf-page.js?v=0.4.0';
import { api } from './bf-api.js?v=0.4.0';
import { remplir, h, message, param, dateFr } from './bf-dom.js?v=0.4.0';
import { formatCents } from './bf-money.js?v=0.4.0';

const UNITES = { forfait: 'forfait', tete: 'par tête', pied: 'par pied', sortie: 'par sortie', heure: 'par heure', unite: 'par unité', livre: 'par livre' };

const user = await initPage();
if (user) {
  const zone = document.getElementById('contenu');
  const msg = h('p', { class: 'bf-message', role: 'alert' });
  const estSt = Boolean(user.sousTraitantId);
  const fournisseur = estSt ? null : param('fournisseur');
  const enCents = (t) => { const n = Number(String(t).replace(',', '.').replace(/[\s$]/g, '')); return Number.isFinite(n) && n > 0 ? Math.round(n * 100) : null; };
  let rapport = null;   // engagements touchés par le dernier enregistrement

  const tableEngagements = (lignes, nouveaux = {}) => h('div', { class: 'bf-table-zone' }, h('table', { class: 'bf-table' },
    h('thead', {}, h('tr', {}, ['Devis', 'Ville', 'Vendeur', 'Travail', 'Prix à honorer', ...(Object.keys(nouveaux).length ? ['Ton nouveau prix'] : []), 'À honorer jusqu\'au'].map((t) => h('th', {}, t)))),
    h('tbody', {}, lignes.map((e) => h('tr', {},
      h('td', {}, `#${e.numero}`, e.statut === 'accepte' ? h('div', { class: 'bf-muet' }, 'accepté, installation à venir') : null),
      h('td', {}, e.ville || ''), h('td', {}, e.vendeur_nom || ''),
      h('td', {}, h('strong', {}, e.code), h('div', { class: 'bf-muet' }, e.travail)),
      h('td', { class: 'num' }, h('strong', {}, formatCents(e.cout_cents))),
      Object.keys(nouveaux).length ? h('td', { class: 'num' }, nouveaux[e.type_travail_id] ? formatCents(nouveaux[e.type_travail_id]) : '') : null,
      h('td', {}, e.honorer_jusqu ? dateFr(e.honorer_jusqu) : 'jusqu\'à l\'installation'))))));

  async function charger() {
    if (!estSt && !fournisseur) { remplir(zone, h('h1', {}, 'Liste de prix'), h('p', {}, 'Choisis un sous-traitant dans « Listes de prix des sous-traitants ».')); return; }
    let d, nomSt = '';
    try {
      d = await api.get('mes-prix', { fournisseur });
      if (!estSt) nomSt = (await api.get('installation-options')).sousTraitants.find((f) => f.id === fournisseur)?.nom || '';
    } catch (e) { remplir(zone, h('h1', {}, 'Ma liste de prix'), h('p', { class: 'bf-message' }, e.message)); return; }
    const { travaux, categories, engagements } = d;
    const modifies = new Map();
    const impact = h('div');
    const bouton = h('button', { class: 'bf-bouton', type: 'button', disabled: true }, 'Enregistrer mes prix');

    const majImpact = () => {
      bouton.disabled = !modifies.size;
      bouton.textContent = modifies.size ? `Enregistrer ${modifies.size} prix` : (estSt ? 'Enregistrer mes prix' : 'Enregistrer les prix');
      const touches = engagements.filter((e) => modifies.has(e.type_travail_id));
      remplir(impact, touches.length ? h('section', { class: 'bf-carte-section bf-avis-engagement' },
        h('h2', {}, `${touches.length} soumission(s) active(s) utilisent ces prix`),
        h('p', {}, 'Ton nouveau prix s\'appliquera aux nouveaux devis. ', h('strong', {}, 'Tu dois honorer le prix déjà donné sur ces soumissions jusqu\'à leur échéance.'),
          ' Si une soumission est renouvelée après son échéance, elle prendra ton nouveau prix.'),
        tableEngagements(touches, Object.fromEntries(modifies))) : null);
    };

    const ligne = (t) => {
      const champ = h('input', { class: 'bf-prix__champ', inputmode: 'decimal', placeholder: 'Ton prix', value: t.cout_cents ? String(t.cout_cents / 100).replace('.', ',') : '', 'aria-label': `Prix : ${t.nom}` });
      const nb = engagements.filter((e) => e.type_travail_id === t.id).length;
      champ.addEventListener('input', () => {
        const c = enCents(champ.value);
        if (c && c !== t.cout_cents) modifies.set(t.id, c); else modifies.delete(t.id);
        champ.classList.toggle('bf-prix__champ--modifie', modifies.has(t.id));
        majImpact();
      });
      return h('div', { class: 'bf-prix bf-prix--public' },
        h('div', { class: 'bf-prix__texte' },
          h('div', {}, h('strong', {}, t.code), ` | ${t.nom}`),
          t.description ? h('div', { class: 'bf-prix__inclus' }, `Inclus : ${t.description}`) : null,
          h('div', { class: 'bf-prix__meta' }, t.cout_cents ? h('span', { class: 'bf-muet' }, `Prix actuel depuis le ${dateFr(t.en_vigueur_du)}`) : h('span', { class: 'bf-retard' }, 'Aucun prix : à remplir'),
            nb ? h('span', { class: 'bf-muet' }, ` · ${nb} soumission(s) active(s) à ce prix`) : null)),
        h('div', { class: 'bf-prix__droite' }, h('label', { class: 'bf-prix__saisie' }, champ, h('span', { class: 'bf-prix__unite' }, UNITES[t.unite] || t.unite))));
    };
    const parCat = new Map();
    for (const t of travaux) { if (!parCat.has(t.categorie)) parCat.set(t.categorie, []); parCat.get(t.categorie).push(t); }
    const nomCat = Object.fromEntries(categories.map((c) => [c.code, c.nom]));
    const ordreCat = Object.fromEntries(categories.map((c) => [c.code, c.ordre]));
    const sections = [...parCat.entries()].sort(([a], [b]) => (ordreCat[a] ?? 99) - (ordreCat[b] ?? 99))
      .map(([cat, ts]) => h('section', { class: 'bf-prix-section' }, h('h2', { class: 'bf-prix-section__titre' }, nomCat[cat] || 'Autres'), ts.map(ligne)));

    bouton.addEventListener('click', async () => {
      try {
        const r = await api.post('mes-prix', { fournisseur_id: fournisseur || undefined, prix: [...modifies].map(([type_travail_id, cout_cents]) => ({ type_travail_id, cout_cents })) });
        rapport = r;
        message(msg, `${r.changes} prix enregistré(s). Ils s'appliquent aux nouveaux devis dès maintenant. Belleflamme et les vendeurs concernés sont avisés.`, 'ok');
        charger();
      } catch (e) { message(msg, e.message); }
    });

    const aRemplir = travaux.filter((t) => !t.cout_cents).length;
    remplir(zone,
      !estSt ? h('p', {}, h('a', { href: `/installation-grille?fournisseur=${fournisseur}` }, '← Listes de prix des sous-traitants')) : null,
      h('h1', {}, estSt ? 'Ma liste de prix' : `Liste de prix | ${nomSt}`),
      h('p', { class: 'bf-muet' }, estSt
        ? 'Modifie tes prix quand tu veux : ils s\'appliquent aux nouveaux devis. Les soumissions déjà envoyées gardent le prix que tu avais donné, et tu dois l\'honorer jusqu\'à leur échéance. Prix avant taxes.'
        : 'Prix du sous-traitant pour les travaux qui lui sont confiés. Une modification s\'applique aux nouveaux devis ; les soumissions actives gardent leur prix.'),
      msg,
      rapport?.engagements?.length ? h('section', { class: 'bf-carte-section bf-avis-engagement' },
        h('h2', {}, 'Rapport : soumissions actives à honorer'),
        h('p', {}, 'Ces soumissions ont été faites avec ton ancien prix. Tu dois les honorer jusqu\'à leur échéance.'),
        tableEngagements(rapport.engagements)) : null,
      travaux.length ? null : h('p', { class: 'bf-message bf-message--alerte' }, 'Aucun travail ne t\'est encore confié. Belleflamme choisira les travaux pour lesquels tu donnes un prix.'),
      aRemplir ? h('p', { class: 'bf-message bf-message--alerte' }, `${aRemplir} travail(aux) sans prix : remplis-les pour recevoir ces jobs.`) : null,
      sections, impact,
      travaux.length ? h('div', { class: 'bf-prix-barre' }, bouton, h('span', { class: 'bf-muet' }, 'Ton prix s\'applique aux nouveaux devis dès l\'enregistrement.')) : null,
      h('section', { class: 'bf-carte-section' }, h('h2', {}, `Tes soumissions actives (${engagements.length})`),
        engagements.length ? tableEngagements(engagements) : h('p', { class: 'bf-muet' }, 'Aucune soumission active avec tes prix pour le moment.')));
  }
  charger();
}
