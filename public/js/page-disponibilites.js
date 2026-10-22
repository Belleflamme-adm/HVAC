// Disponibilités : le sous-traitant coche lui-même ses journées (ADR-037).
// Clic : non indiqué -> disponible -> indisponible -> non indiqué. La planification consulte.
import { initPage } from './bf-page.js?v=0.4.0';
import { api } from './bf-api.js?v=0.4.0';
import { remplir, h, message, param } from './bf-dom.js?v=0.4.0';
import { grilleMois, iso } from './bf-calendrier.js?v=0.4.0';

const SUIVANT = { aucun: 'disponible', disponible: 'indisponible', indisponible: 'aucun' };
const LIBELLE = { aucun: '', disponible: 'Dispo', indisponible: 'Non' };
const JOURS = ['lun', 'mar', 'mer', 'jeu', 'ven', 'sam', 'dim'];

const user = await initPage();
if (user) {
  const zone = document.getElementById('contenu');
  const msg = h('p', { class: 'bf-message', role: 'alert' });
  const estSt = Boolean(user.sousTraitantId);
  let fournisseur = estSt ? user.sousTraitantId : param('fournisseur');
  const auj = new Date();
  let annee = auj.getFullYear(); let mois = auj.getMonth();
  let etat = new Map();
  const calendrier = h('div', { class: 'bf-calendrier' });
  const titreMois = h('h2', {});

  async function charger() {
    if (!fournisseur) { remplir(calendrier, h('p', { class: 'bf-muet' }, 'Choisis un sous-traitant.')); return; }
    const de = iso(new Date(annee, mois, 1)); const a = iso(new Date(annee, mois + 1, 0));
    try {
      const lignes = await api.get('disponibilites', { fournisseur_id: estSt ? undefined : fournisseur, de, a });
      etat = new Map(lignes.map((l) => [l.jour, l.statut]));
      rendre();
    } catch (e) { message(msg, e.message); }
  }

  function rendre() {
    titreMois.textContent = new Date(annee, mois, 1).toLocaleDateString('fr-CA', { month: 'long', year: 'numeric' });
    const aujourdhui = iso(auj);
    remplir(calendrier,
      h('div', { class: 'bf-cal-entete' }, JOURS.map((j) => h('span', {}, j))),
      ...grilleMois(annee, mois).map((semaine) => h('div', { class: 'bf-cal-semaine' }, semaine.map((d) => {
        if (!d) return h('span', { class: 'bf-cal-vide' });
        const jour = iso(d); const s = etat.get(jour) || 'aucun'; const passe = jour < aujourdhui;
        return h('button', {
          type: 'button', class: `bf-cal-jour bf-cal-${s}${passe ? ' bf-cal-passe' : ''}`,
          disabled: !estSt || passe, 'aria-label': `${d.toLocaleDateString('fr-CA', { dateStyle: 'full' })} : ${s}`,
          onclick: async () => {
            const nouveau = SUIVANT[s];
            etat.set(jour, nouveau); rendre();
            try { await api.post('disponibilites', { jours: [{ jour, statut: nouveau }] }); }
            catch (e) { etat.set(jour, s); rendre(); message(msg, e.message); }
          },
        }, h('strong', {}, String(d.getDate())), h('small', {}, LIBELLE[s]));
      }))));
  }

  // Remplir rapidement un mois : toutes les semaines (lun-ven) disponibles
  const toutesSemaines = h('button', { class: 'bf-bouton bf-bouton--discret', type: 'button', hidden: !estSt, onclick: async () => {
    const aujourdhui = iso(auj);
    const jours = grilleMois(annee, mois).flat().filter((d) => d && iso(d) >= aujourdhui && d.getDay() >= 1 && d.getDay() <= 5 && !etat.has(iso(d)))
      .map((d) => ({ jour: iso(d), statut: 'disponible' }));
    if (!jours.length) return;
    try { await api.post('disponibilites', { jours }); await charger(); } catch (e) { message(msg, e.message); }
  } }, 'Lundi au vendredi disponibles (jours non indiqués)');

  const nav = h('div', { class: 'bf-filtres' },
    h('button', { class: 'bf-bouton bf-bouton--discret', type: 'button', onclick: () => { mois -= 1; if (mois < 0) { mois = 11; annee -= 1; } charger(); } }, '← Mois précédent'),
    titreMois,
    h('button', { class: 'bf-bouton bf-bouton--discret', type: 'button', onclick: () => { mois += 1; if (mois > 11) { mois = 0; annee += 1; } charger(); } }, 'Mois suivant →'));
  if (!estSt) {
    const sts = await api.get('sous-traitants').catch(() => []);
    const choix = h('select', { 'aria-label': 'Sous-traitant' }, h('option', { value: '' }, 'Sous-traitant…'),
      sts.map((s) => h('option', { value: s.id, selected: s.id === fournisseur }, s.nom)));
    choix.addEventListener('change', () => { fournisseur = choix.value || null; charger(); });
    nav.prepend(choix);
  }

  remplir(zone,
    h('h1', {}, estSt ? 'Mes disponibilités' : 'Disponibilités des sous-traitants'),
    h('p', { class: 'bf-muet' }, estSt
      ? 'Touche une journée : disponible (vert), puis non disponible (rouge), puis non indiquée. Belleflamme planifie seulement dans tes journées disponibles.'
      : 'Lecture seule : chaque sous-traitant inscrit lui-même ses disponibilités.'),
    msg, nav, toutesSemaines, calendrier,
    h('p', { class: 'bf-legende' },
      h('span', { class: 'bf-legende__item' }, h('span', { class: 'bf-pastille-couleur bf-c-accepte' }), 'Disponible'),
      h('span', { class: 'bf-legende__item' }, h('span', { class: 'bf-pastille-couleur bf-c-refuse' }), 'Non disponible'),
      h('span', { class: 'bf-legende__item' }, h('span', { class: 'bf-pastille-couleur bf-c-aucun' }), 'Non indiqué')));
  charger();
}
