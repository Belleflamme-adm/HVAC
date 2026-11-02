// Territoire d'un sous-traitant : par municipalité, accepte / supplément / refuse.
// Sous-traitant : son propre territoire. Planification : choisit le sous-traitant, et désigne les principaux.
// Mode « principaux » (ADR-063) : chaque sous-traitant a sa couleur ; une municipalité desservie par plusieurs
// est rayée en bandes égales, une par sous-traitant ; pâle = avec supplément ; contour foncé = principal désigné.
import { initPage } from './bf-page.js?v=0.4.0';
import { api } from './bf-api.js?v=0.4.0';
import { remplir, h, message, param } from './bf-dom.js?v=0.4.0';
import { formatCents } from './bf-money.js?v=0.4.0';
import { creerCarte, chargerMunicipalites, chargerReperes, couleurSt, nuancer } from './bf-carte.js?v=0.4.0';

const COULEURS = { accepte: '#2e9d63', supplement: '#e2a01b', refuse: '#c9483f', aucun: '#d9dee6',
  principal: '#1d47c2', sans_principal: '#e2a01b' };
// Sud du Québec habité et Est ontarien, de Pembroke à Québec et à l'Estrie : là où Belleflamme installe.
const VUE_DEPART = { ouest: -77.7, sud: 44.2, est: -70.6, nord: 47.4 };
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
  let tous = new Map();            // code -> [{ fournisseur_id, statut, supplement_cents }] (mode principaux)
  let sts = [];                    // sous-traitants, dans l'ordre (leur couleur suit cet ordre)
  const couleurDe = new Map();     // fournisseur_id -> couleur
  const nomSt = (id) => sts.find((s) => s.id === id)?.nom || 'Sous-traitant';
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

    // Sous-traitants qui desservent une municipalité (tous, ou celui choisi)
    const desservants = (code) => (tous.get(code) || []).filter((t) => !fournisseur || t.fournisseur_id === fournisseur);
    const couleur = (code) => {
      if (mode === 'principaux') {
        const d = desservants(code);
        if (!d.length) return COULEURS.aucun;
        return d.map((t) => (t.statut === 'supplement' ? nuancer(couleurDe.get(t.fournisseur_id), 0.55) : couleurDe.get(t.fournisseur_id)));
      }
      return COULEURS[territoire.get(code)?.statut || 'aucun'];
    };
    const contour = (code) => {
      if (mode !== 'principaux') return null;
      const p = principaux.get(code);
      return p && (!fournisseur || p === fournisseur) ? nuancer(couleurDe.get(p) || COULEURS.principal, -0.45) : null;
    };
    const titre = (f) => {
      if (mode === 'principaux') {
        const d = desservants(f.properties.code);
        const p = principaux.get(f.properties.code);
        return `${f.properties.nom} | ${d.length ? d.map((t) => `${nomSt(t.fournisseur_id)}${t.statut === 'supplement' ? ` (+${formatCents(t.supplement_cents)})` : ''}${p === t.fournisseur_id ? ' [principal]' : ''}`).join(', ') : 'Aucun sous-traitant'}`;
      }
      const t = territoire.get(f.properties.code);
      const lieu = [f.properties.mrc, f.properties.region].filter(Boolean).join(', ');
      return `${f.properties.nom}${lieu ? ` (${lieu})` : ''} | ${LIBELLES[t?.statut || 'aucun']}${t?.supplement_cents ? ` (+${formatCents(t.supplement_cents)})` : ''}`;
    };
    const carte = creerCarte(carteZone, geo, {
      couleur, contour, titre, reperes, vueDepart: VUE_DEPART,
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
        if (mode === 'principaux') {
          tous = new Map();
          for (const t of await api.get('territoire', { tous: 1 })) {
            if (!tous.has(t.municipalite_code)) tous.set(t.municipalite_code, []);
            tous.get(t.municipalite_code).push(t);
          }
          // Toujours le même ordre de bandes : celui de la liste des sous-traitants
          const rang = new Map(sts.map((x, i) => [x.id, i]));
          for (const l of tous.values()) l.sort((a, b) => (rang.get(a.fournisseur_id) ?? 99) - (rang.get(b.fournisseur_id) ?? 99));
        }
        if (fournisseur && mode !== 'principaux') {
          const t = await api.get('territoire', { fournisseur_id: estSt ? undefined : fournisseur });
          territoire = new Map(t.map((x) => [x.municipalite_code, x]));
        } else territoire = new Map();
        if (planif) principaux = new Map((await api.get('principaux')).map((p) => [p.municipalite_code, p.fournisseur_id]));
        if (mode === 'principaux') rendreLegendePrincipaux();
        else {
          const c = { accepte: 0, supplement: 0, refuse: 0 };
          for (const t of territoire.values()) c[t.statut] += 1;
          remplir(legende,
            ...['accepte', 'supplement', 'refuse', 'aucun'].map((s) => h('span', { class: 'bf-legende__item' },
              h('span', { class: `bf-pastille-couleur bf-c-${s}` }), `${LIBELLES[s]}${c[s] !== undefined ? ` (${c[s]})` : ''}`)));
        }
        carte.redessiner(selection);
        // Au premier affichage, on cadre sur le territoire déjà choisi (surtout utile sur téléphone)
        const codes = mode === 'principaux' ? [...tous.keys()].filter((c) => desservants(c).length) : [...territoire.keys()];
        if (!dejaCadre && codes.length) dejaCadre = carte.cadrer(codes);
        rendrePanneau();
      } catch (e) { message(msg, e.message); }
    }

    const pastille = (c) => h('span', { class: 'bf-pastille-couleur', style: `background:${c}` });
    function rendreLegendePrincipaux() {
      const compte = new Map();
      let plusieurs = 0;
      for (const [code, l] of tous) {
        const d = desservants(code);
        if (d.length > 1) plusieurs += 1;
        for (const t of d) compte.set(t.fournisseur_id, (compte.get(t.fournisseur_id) || 0) + 1);
      }
      const visibles = sts.filter((x) => !fournisseur || x.id === fournisseur);
      remplir(legende,
        ...visibles.map((x) => h('span', { class: 'bf-legende__item' }, pastille(couleurDe.get(x.id)), `${x.nom} (${compte.get(x.id) || 0})`)),
        h('span', { class: 'bf-legende__item bf-muet' }, 'Pâle : avec supplément'),
        h('span', { class: 'bf-legende__item bf-muet' }, h('span', { class: 'bf-pastille-couleur bf-pastille-contour' }), 'Contour foncé : principal'),
        fournisseur ? null : h('span', { class: 'bf-legende__item' }, h('strong', {}, `${plusieurs} municipalité(s) avec 2 sous-traitants ou plus (rayées)`)));
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
          liste.length ? h('p', { class: 'bf-muet' }, `${liste.length} sous-traitant(s) desservent cette municipalité. Clique pour choisir le principal.`) : null,
          liste.length ? h('div', { class: 'bf-liste' }, liste.map((st) => h('button', { class: 'bf-ligne', type: 'button',
            onclick: async () => { try { await api.post('principaux', { municipalite_code: code, fournisseur_id: st.fournisseur_id }); await charger(); } catch (e) { message(msg, e.message); } } },
            h('span', { class: 'bf-legende__item' }, pastille(couleurDe.get(st.fournisseur_id) || COULEURS.aucun), h('strong', {}, st.nom)), st.principal ? h('span', { class: 'bf-pastille bf-pastille--accepte' }, 'Principal') : null,
            st.supplement_cents ? h('span', { class: 'bf-muet' }, `+${formatCents(st.supplement_cents)}`) : h('span', { class: 'bf-muet' }, 'sans supplément'))))
            : h('p', { class: 'bf-message bf-message--alerte' }, 'Aucun sous-traitant ne dessert cette municipalité.'));
        return;
      }
      if (!fournisseur) { remplir(panneau, h('p', { class: 'bf-muet' }, 'Choisis un sous-traitant.')); return; }
      const noms = [...selection].map(nomDe);
      remplir(panneau,
        h('h2', {}, selection.size ? `${selection.size} municipalité(s) sélectionnée(s)` : 'Clique les municipalités'),
        selection.size ? h('p', { class: 'bf-muet' }, noms.slice(0, 8).join(', ') + (noms.length > 8 ? '…' : '')) : null,
        selection.size ? h('p', { class: 'bf-muet' }, 'Astuce : clique de nouveau sur une ville pour la retirer de la sélection.') : null,
        h('div', { class: 'bf-actions' },
          h('button', { class: 'bf-bouton', type: 'button', disabled: !selection.size, onclick: appliquer('accepte') }, 'J\'accepte'),
          h('button', { class: 'bf-bouton', type: 'button', disabled: !selection.size, onclick: appliquer('supplement') }, 'Avec supplément'),
          h('button', { class: 'bf-bouton bf-bouton--discret', type: 'button', disabled: !selection.size, onclick: appliquer('refuse') }, 'Je refuse'),
          h('button', { class: 'bf-bouton bf-bouton--discret', type: 'button', disabled: !selection.size, onclick: appliquer('aucun') }, 'Effacer'),
          h('button', { class: 'bf-bouton bf-bouton--discret', type: 'button', disabled: !selection.size, onclick: () => {
            const n = selection.size;
            selection.clear(); carte.redessiner(selection); rendrePanneau();
            message(msg, `${n} municipalité(s) désélectionnée(s).`, 'ok');
          } }, 'Tout désélectionner')));
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
      h('button', { class: 'bf-bouton bf-bouton--discret', type: 'button', onclick: () => carte.vueDepart() }, 'Sud du Québec et Est ontarien'),
      h('button', { class: 'bf-bouton bf-bouton--discret', type: 'button', onclick: () => carte.toutVoir() }, 'Tout le Québec'));
    if (planif && !estSt) {
      sts = await api.get('sous-traitants').catch(() => []);
      sts.forEach((x, i) => couleurDe.set(x.id, couleurSt(i)));
      const premier = h('option', { value: '' }, 'Sous-traitant…');
      const choix = h('select', { 'aria-label': 'Sous-traitant' }, premier,
        sts.map((s) => h('option', { value: s.id, selected: s.id === fournisseur }, s.nom)));
      choix.addEventListener('change', () => { fournisseur = choix.value || null; selection.clear(); dejaCadre = false; charger(); });
      const modeSel = h('select', { 'aria-label': 'Mode' },
        h('option', { value: 'territoire' }, 'Territoire d\'un sous-traitant'), h('option', { value: 'principaux' }, 'Sous-traitants principaux'));
      modeSel.addEventListener('change', () => {
        mode = modeSel.value; selection.clear(); dejaCadre = false;
        // Mode principaux : « Tous » par défaut, chacun dans sa couleur
        if (mode === 'principaux') { premier.textContent = 'Tous'; fournisseur = null; choix.value = ''; }
        else premier.textContent = 'Sous-traitant…';
        charger();
      });
      outils.prepend(modeSel, choix);
    }

    remplir(zone,
      h('h1', {}, estSt ? 'Mon territoire' : 'Territoires des sous-traitants'),
      h('p', { class: 'bf-muet' }, estSt
        ? 'Clique les municipalités où tu acceptes de travailler pour Belleflamme, celles où tu demandes un supplément, et celles que tu refuses.'
        : 'Vert : accepte | Orange : avec supplément | Rouge : refuse. En mode « principaux », chaque sous-traitant a sa couleur ; '
          + 'une municipalité desservie par plusieurs est rayée, une bande par sous-traitant.'),
      msg, outils, legende,
      h('div', { class: 'bf-carte-mise' }, carteZone, panneau),
      h('p', { class: 'bf-muet bf-attribution' }, 'Limites municipales : Découpages administratifs, MRNF, Données Québec (CC-BY 4.0) ; Municipal Boundary, ministère des Richesses naturelles de l\'Ontario (Licence du gouvernement ouvert de l\'Ontario). Sans valeur légale.'));
    charger();
  }
}
