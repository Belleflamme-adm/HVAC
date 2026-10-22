// Territoire d'un sous-traitant : par municipalité, accepte / supplément / refuse.
// Sous-traitant : son propre territoire. Planification : choisit le sous-traitant, et désigne les principaux.
import { initPage } from './bf-page.js?v=0.4.0';
import { api } from './bf-api.js?v=0.4.0';
import { remplir, h, message, param } from './bf-dom.js?v=0.4.0';
import { formatCents } from './bf-money.js?v=0.4.0';
import { creerCarte, chargerMunicipalites, chargerReperes } from './bf-carte.js?v=0.4.0';

const COULEURS = { accepte: '#2e9d63', supplement: '#e2a01b', refuse: '#c9483f', aucun: '#d9dee6',
  principal: '#1d47c2', sans_principal: '#e2a01b' };
// Sud du Québec habité, de l'Outaouais à Québec et à l'Estrie : là où Belleflamme installe.
const SUD_QUEBEC = { ouest: -77.0, sud: 45.0, est: -70.6, nord: 47.4 };
const LIBELLES = { accepte: 'Accepte', supplement: 'Supplément', refuse: 'Refuse', aucun: 'Non indiqué' };

const user = await initPage();
if (user) {
  const zone = document.getElementById('contenu');
  const msg = h('p', { class: 'bf-message', role: 'alert' });
  const estSt = Boolean(user.sousTraitantId);
  const planif = ['Admin tout', 'Direction', 'Coordonnateur'].includes(user.role);
  let fournisseur = estSt ? user.sousTraitantId : param('fournisseur');
  let mode = 'territoire';
  let territoire = new Map();      // code -> { statut, supplement_cents }
  let principaux = new Map();      // code -> fournisseur_id
  const selection = new Set();
  let dejaCadre = false;

  const [geo, reperes] = await Promise.all([chargerMunicipalites(), chargerReperes()]);
  if (!geo) {
    remplir(zone, h('h1', {}, 'Territoire'), h('p', { class: 'bf-message bf-message--alerte' },
      'Les limites municipales ne sont pas encore installées. Il faut charger le jeu officiel « Découpages administratifs » '
      + '(MRNF, Données Québec) avec scripts/municipalites/convertir.mjs.'));
  } else {
    const carteZone = h('div', { class: 'bf-carte-zone' });
    const panneau = h('div', { class: 'bf-carte-panneau' });
    const legende = h('p', { class: 'bf-legende' });
    const nomDe = (code) => geo.features.find((f) => f.properties.code === code)?.properties.nom || code;

    const couleur = (code) => {
      if (mode === 'principaux') return principaux.get(code) ? COULEURS.principal : COULEURS.aucun;
      return COULEURS[territoire.get(code)?.statut || 'aucun'];
    };
    const titre = (f) => {
      const t = territoire.get(f.properties.code);
      const lieu = [f.properties.mrc, f.properties.region].filter(Boolean).join(', ');
      return `${f.properties.nom}${lieu ? ` (${lieu})` : ''} | ${LIBELLES[t?.statut || 'aucun']}${t?.supplement_cents ? ` (+${formatCents(t.supplement_cents)})` : ''}`;
    };
    const carte = creerCarte(carteZone, geo, {
      couleur, titre, reperes, vueDepart: SUD_QUEBEC,
      onClic: (f) => {
        const code = f.properties.code;
        if (mode === 'principaux') { selection.clear(); selection.add(code); }
        else if (selection.has(code)) selection.delete(code); else selection.add(code);
        carte.redessiner(selection);
        rendrePanneau();
      },
    });

    async function charger() {
      try {
        if (fournisseur) {
          const t = await api.get('territoire', { fournisseur_id: estSt ? undefined : fournisseur });
          territoire = new Map(t.map((x) => [x.municipalite_code, x]));
        } else territoire = new Map();
        if (planif) principaux = new Map((await api.get('principaux')).map((p) => [p.municipalite_code, p.fournisseur_id]));
        const c = { accepte: 0, supplement: 0, refuse: 0 };
        for (const t of territoire.values()) c[t.statut] += 1;
        remplir(legende,
          ...['accepte', 'supplement', 'refuse', 'aucun'].map((s) => h('span', { class: 'bf-legende__item' },
            h('span', { class: `bf-pastille-couleur bf-c-${s}` }), `${LIBELLES[s]}${c[s] !== undefined ? ` (${c[s]})` : ''}`)));
        carte.redessiner(selection);
        // Au premier affichage, on cadre sur le territoire déjà choisi (surtout utile sur téléphone)
        if (!dejaCadre && territoire.size) dejaCadre = carte.cadrer(territoire.keys());
        rendrePanneau();
      } catch (e) { message(msg, e.message); }
    }

    const appliquer = (statut) => async () => {
      const corps = { fournisseur_id: estSt ? undefined : fournisseur, municipalites: [...selection], statut };
      if (statut === 'supplement') {
        const montant = prompt('Supplément pour ces municipalités, en dollars (ajouté à ton prix) :');
        if (!montant) return;
        corps.supplement_cents = Math.round(Number(montant.replace(',', '.').replace(/\s/g, '')) * 100);
      }
      try { await api.post('territoire', corps); selection.clear(); await charger(); message(msg, 'Territoire enregistré.', 'ok'); }
      catch (e) { message(msg, e.message); }
    };

    async function rendrePanneau() {
      if (mode === 'principaux') {
        const code = [...selection][0];
        if (!code) { remplir(panneau, h('p', { class: 'bf-muet' }, 'Clique une municipalité pour choisir son sous-traitant principal.')); return; }
        let liste = [];
        try { liste = await api.get('municipalites', { pour: code }); } catch (e) { message(msg, e.message); }
        remplir(panneau, h('h2', {}, nomDe(code)),
          liste.length ? h('div', { class: 'bf-liste' }, liste.map((st) => h('button', { class: 'bf-ligne', type: 'button',
            onclick: async () => { try { await api.post('principaux', { municipalite_code: code, fournisseur_id: st.fournisseur_id }); await charger(); } catch (e) { message(msg, e.message); } } },
            h('strong', {}, st.nom), st.principal ? h('span', { class: 'bf-pastille bf-pastille--accepte' }, 'Principal') : null,
            st.supplement_cents ? h('span', { class: 'bf-muet' }, `+${formatCents(st.supplement_cents)}`) : h('span', { class: 'bf-muet' }, 'sans supplément'))))
            : h('p', { class: 'bf-message bf-message--alerte' }, 'Aucun sous-traitant ne dessert cette municipalité.'));
        return;
      }
      if (!fournisseur) { remplir(panneau, h('p', { class: 'bf-muet' }, 'Choisis un sous-traitant.')); return; }
      const noms = [...selection].map(nomDe);
      remplir(panneau,
        h('h2', {}, selection.size ? `${selection.size} municipalité(s) sélectionnée(s)` : 'Clique les municipalités'),
        selection.size ? h('p', { class: 'bf-muet' }, noms.slice(0, 8).join(', ') + (noms.length > 8 ? '…' : '')) : null,
        h('div', { class: 'bf-actions' },
          h('button', { class: 'bf-bouton', type: 'button', disabled: !selection.size, onclick: appliquer('accepte') }, 'J\'accepte'),
          h('button', { class: 'bf-bouton', type: 'button', disabled: !selection.size, onclick: appliquer('supplement') }, 'Avec supplément'),
          h('button', { class: 'bf-bouton bf-bouton--discret', type: 'button', disabled: !selection.size, onclick: appliquer('refuse') }, 'Je refuse'),
          h('button', { class: 'bf-bouton bf-bouton--discret', type: 'button', disabled: !selection.size, onclick: appliquer('aucun') }, 'Effacer'),
          h('button', { class: 'bf-lien', type: 'button', disabled: !selection.size, onclick: () => { selection.clear(); carte.redessiner(selection); rendrePanneau(); } }, 'Désélectionner')));
    }

    // Recherche d'une municipalité
    const recherche = h('input', { type: 'search', placeholder: 'Trouver une municipalité…', 'aria-label': 'Trouver une municipalité', list: 'liste-muni' });
    // « Nom (MRC) » : plusieurs municipalités portent le même nom (ex. village nordique et terres réservées)
    const etiquette = (f) => (f.properties.mrc ? `${f.properties.nom} (${f.properties.mrc})` : f.properties.nom);
    const liste = h('datalist', { id: 'liste-muni' }, geo.features.map((f) => h('option', { value: etiquette(f) })));
    recherche.addEventListener('change', () => {
      const v = recherche.value.trim().toLowerCase();
      const f = geo.features.find((x) => etiquette(x).toLowerCase() === v) || geo.features.find((x) => x.properties.nom.toLowerCase() === v);
      if (!f) return;
      carte.zoomSur(f.properties.code);
      if (mode === 'principaux') selection.clear();
      selection.add(f.properties.code);
      carte.redessiner(selection);
      rendrePanneau();
    });

    const outils = h('div', { class: 'bf-filtres' }, recherche, liste,
      h('button', { class: 'bf-bouton bf-bouton--discret', type: 'button', onclick: () => carte.vueDepart() }, 'Sud du Québec'),
      h('button', { class: 'bf-bouton bf-bouton--discret', type: 'button', onclick: () => carte.toutVoir() }, 'Tout le Québec'));
    if (planif && !estSt) {
      const sts = await api.get('sous-traitants').catch(() => []);
      const choix = h('select', { 'aria-label': 'Sous-traitant' }, h('option', { value: '' }, 'Sous-traitant…'),
        sts.map((s) => h('option', { value: s.id, selected: s.id === fournisseur }, s.nom)));
      choix.addEventListener('change', () => { fournisseur = choix.value || null; selection.clear(); dejaCadre = false; charger(); });
      const modeSel = h('select', { 'aria-label': 'Mode' },
        h('option', { value: 'territoire' }, 'Territoire d\'un sous-traitant'), h('option', { value: 'principaux' }, 'Sous-traitants principaux'));
      modeSel.addEventListener('change', () => { mode = modeSel.value; selection.clear(); charger(); });
      outils.prepend(modeSel, choix);
    }

    remplir(zone,
      h('h1', {}, estSt ? 'Mon territoire' : 'Territoires des sous-traitants'),
      h('p', { class: 'bf-muet' }, estSt
        ? 'Clique les municipalités où tu acceptes de travailler pour Belleflamme, celles où tu demandes un supplément, et celles que tu refuses.'
        : 'Vert : accepte | Orange : avec supplément | Rouge : refuse. En mode « principaux », bleu = principal désigné.'),
      msg, outils, legende,
      h('div', { class: 'bf-carte-mise' }, carteZone, panneau),
      h('p', { class: 'bf-muet bf-attribution' }, 'Limites municipales : Découpages administratifs, MRNF, Données Québec (CC-BY 4.0). Sans valeur légale.'));
    charger();
  }
}
