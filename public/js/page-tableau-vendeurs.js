// Performance et rémunération des vendeurs (ADR-074) : ce que chaque vendeur a rentré, sa commission (pourcentage
// ajustable par vendeur, 10 % par défaut), son salaire par rapport au travail fourni et son taux de closing.
// Pour le directeur des ventes et la comptabilité. SIMULATION : la paie officielle reste dans le module Commissions de Mike.
// Données FICTIVES tant que les devis, factures et le Pointage de Mike ne sont pas branchés.
import { initPage } from './bf-page.js?v=0.4.0';
import { h, remplir } from './bf-dom.js?v=0.4.0';
import { VENDEURS, SUCCURSALES, ventesFictives, activiteVendeurs, moisJusqua } from './bf-ventes-fictives.js?v=0.4.0';
import { compact, entier, pctTxt, dollars, svg, survol, cacherBulle, carteGraph, vide, tuile, barres, barresEmpilees,
  colonnesEmpilees, panneauDash } from './bf-dash.js?v=0.4.0';

const FIN = '2026-10';
const PERIODES = {
  '12m': { libelle: '12 derniers mois', mois: moisJusqua(FIN, 12), avant: moisJusqua('2025-10', 12), compare: 'vs 12 mois précédents' },
  '3m': { libelle: '3 derniers mois', mois: moisJusqua(FIN, 3), avant: moisJusqua('2026-07', 3), compare: 'vs 3 mois précédents' },
  mois: { libelle: 'Octobre 2026', mois: [FIN], avant: ['2026-09'], compare: 'vs septembre' },
  annee: { libelle: 'Année 2026 (à ce jour)', mois: moisJusqua(FIN, 10), avant: moisJusqua('2025-10', 10), compare: 'vs même période 2025' },
};
const PCT_DEFAUT = 10;            // % de commission par défaut (demande de Simon)
const ROLES = ['Admin tout', 'Direction', 'Comptabilité'];
const SERIES_PAIE = [{ cle: 'commission', libelle: 'Commission', couleur: 'var(--d-s1)' }, { cle: 'base', libelle: 'Salaire de base', couleur: 'var(--d-s6)' }];
const prenom = (nom) => nom.split(' ')[0];

const user = await initPage();
if (user) {
  const zone = document.getElementById('contenu');
  if (!ROLES.includes(user.role)) {
    remplir(zone, h('h1', {}, 'Vendeurs : performance et rémunération'), h('p', { class: 'bf-message' }, 'Réservé au directeur des ventes, à la direction et à la comptabilité.'));
  } else {
    const ventesTout = ventesFictives(FIN);
    const activite = activiteVendeurs(ventesTout);
    // Réglages par vendeur : % de commission et salaire de base annuel. Maquette : gardés dans ce navigateur ; app branchée : en base, avec historique.
    const CLE = 'bf_remuneration_vendeurs';
    const defaut = () => ({ base: 'ventes', vendeurs: Object.fromEntries(Object.keys(VENDEURS).map((id) => [id, { pct: PCT_DEFAUT, salaire: 0 }])) });
    let reglages = defaut();
    try { const r = JSON.parse(localStorage.getItem(CLE) || 'null'); if (r?.vendeurs) reglages = { ...reglages, ...r, vendeurs: { ...reglages.vendeurs, ...r.vendeurs } }; } catch { /* stockage indisponible */ }
    const sauver = () => { try { localStorage.setItem(CLE, JSON.stringify(reglages)); } catch { /* stockage indisponible */ } };
    let edition = false;

    const filtres = { periode: '12m', vendeur: '' };
    const choix = (nom, libelle, options, surChange) => {
      const sel = h('select', { 'aria-label': libelle }, options.map(([v, t]) => h('option', { value: v, selected: (nom === 'base' ? reglages.base : filtres[nom]) === v }, t)));
      sel.addEventListener('change', () => { surChange(sel.value); rendre(); });
      return sel;
    };
    const barreFiltres = h('div', { class: 'bf-dash__filtres' },
      choix('periode', 'Période', Object.entries(PERIODES).map(([k, p]) => [k, p.libelle]), (v) => { filtres.periode = v; }),
      choix('vendeur', 'Vendeur', [['', 'Tous les vendeurs'], ...Object.entries(VENDEURS).map(([k, v]) => [k, v.nom])], (v) => { filtres.vendeur = v; }),
      choix('base', 'Commission calculée sur', [['ventes', 'Commission sur les ventes'], ['marge', 'Commission sur la marge brute']], (v) => { reglages.base = v; sauver(); }));
    const corps = h('div', { class: 'bf-dash__corps' });
    remplir(zone, panneauDash('Vendeurs | Performance et rémunération',
      'Ce que chaque vendeur a rentré, ce qu\'il gagne, le travail fourni et son taux de closing. Simulation : la paie officielle reste dans le module Commissions de l\'app de Mike.',
      barreFiltres, corps));

    // Indicateurs d'un vendeur sur une liste de mois
    function stats(id, mois) {
      const v = ventesTout.filter((x) => x.vendeur === id && mois.includes(x.mois));
      const a = activite.filter((x) => x.vendeur === id && mois.includes(x.mois));
      const somme = (l, f) => l.reduce((t, x) => t + f(x), 0);
      const ventes = somme(v, (x) => x.prix_cents) / 100; const marge = ventes - somme(v, (x) => x.cout_cents) / 100;
      const r = reglages.vendeurs[id] || { pct: PCT_DEFAUT, salaire: 0 };
      const commission = (reglages.base === 'marge' ? marge : ventes) * (Number(r.pct) || 0) / 100;
      const base = (Number(r.salaire) || 0) * mois.length / 12;
      const heures = somme(a, (x) => x.heures); const soumissions = somme(a, (x) => x.soumissions); const leads = somme(a, (x) => x.leads);
      const remuneration = commission + base;
      return {
        id, nom: VENDEURS[id].nom, nb: v.length, ventes, marge, pctMarge: ventes ? marge / ventes : 0, pct: Number(r.pct) || 0, salaire: Number(r.salaire) || 0,
        commission, base, remuneration, heures, parHeure: heures ? remuneration / heures : 0, ventesHeure: heures ? ventes / heures : 0,
        leads, contacts: somme(a, (x) => x.contacts), visites: somme(a, (x) => x.visites), soumissions,
        closing: soumissions ? v.length / soumissions : 0, leadVente: leads ? v.length / leads : 0, panier: v.length ? ventes / v.length : 0,
        coutVente: ventes ? remuneration / ventes : 0, margeApres: marge - remuneration,
        succursales: [...new Set(v.map((x) => SUCCURSALES[x.succursale].nom))],
        // Équivalence pour comparer les deux façons de payer
        pctEquivalentMarge: marge ? commission / marge : 0, pctEquivalentVentes: ventes ? commission / ventes : 0,
      };
    }

    function rendre() {
      cacherBulle();
      const P = PERIODES[filtres.periode];
      const ids = Object.keys(VENDEURS).filter((id) => !filtres.vendeur || id === filtres.vendeur);
      const S = ids.map((id) => stats(id, P.mois)).filter((x) => x.nb || x.heures).sort((a, b) => b.remuneration - a.remuneration);
      const Sa = ids.map((id) => stats(id, P.avant));
      const tot = (l, k) => l.reduce((t, x) => t + x[k], 0);
      const T = { ventes: tot(S, 'ventes'), marge: tot(S, 'marge'), commission: tot(S, 'commission'), remuneration: tot(S, 'remuneration'), heures: tot(S, 'heures'), nb: tot(S, 'nb'), soumissions: tot(S, 'soumissions') };
      const Ta = { ventes: tot(Sa, 'ventes'), marge: tot(Sa, 'marge'), remuneration: tot(Sa, 'remuneration'), heures: tot(Sa, 'heures'), nb: tot(Sa, 'nb'), soumissions: tot(Sa, 'soumissions') };
      const delta = (a, b) => (b ? (a - b) / b : null);
      const closingEquipe = T.soumissions ? T.nb / T.soumissions : 0; const closingAvant = Ta.soumissions ? Ta.nb / Ta.soumissions : 0;
      const surMarge = reglages.base === 'marge';
      const mois12 = moisJusqua(FIN, 12);

      remplir(corps,
        h('div', { class: 'bf-dash__tuiles' },
          tuile('argent', 'Ventes rentrées', compact(T.ventes), delta(T.ventes, Ta.ventes), P.compare, { note: `${entier(T.nb)} ventes, avant taxes` }),
          tuile('vente', `Commissions (${surMarge ? 'sur la marge' : 'sur les ventes'})`, compact(T.commission), null, '',
            { note: `${pctTxt(T.ventes ? T.commission / T.ventes : 0, 1)} des ventes | ${pctTxt(T.marge ? T.commission / T.marge : 0, 1)} de la marge` }),
          tuile('machines', 'Rémunération totale', compact(T.remuneration), delta(T.remuneration, Ta.remuneration), P.compare, { hausseBonne: false, note: 'commissions + salaires de base' }),
          tuile('marge', 'Coût de la force de vente', pctTxt(T.ventes ? T.remuneration / T.ventes : 0, 1), null, '', { note: 'rémunération / ventes' }),
          tuile('moyenne', 'Rémunération moyenne par heure', T.heures ? dollars(T.remuneration / T.heures) : 'n/d', null, '', { note: `${entier(T.heures)} heures travaillées (Pointage)` }),
          tuile('rendement', 'Ventes par heure travaillée', T.heures ? dollars(T.ventes / T.heures) : 'n/d', delta(T.heures ? T.ventes / T.heures : 0, Ta.heures ? Ta.ventes / Ta.heures : 0), P.compare),
          tuile('cible', 'Taux de closing', pctTxt(closingEquipe, 1), closingAvant ? closingEquipe - closingAvant : null, P.compare, { points: true, note: 'ventes / soumissions envoyées' }),
          tuile('stock', 'Marge après rémunération', compact(T.marge - T.remuneration), delta(T.marge - T.remuneration, Ta.marge - Ta.remuneration), P.compare,
            { note: `${pctTxt(T.ventes ? (T.marge - T.remuneration) / T.ventes : 0, 1)} des ventes` })),

        carteGraph('Ce que chaque vendeur a rentré et ce qu\'il gagne', `${P.libelle} | commission ${surMarge ? 'sur la marge brute' : 'sur les ventes avant taxes'}, salaire de base au prorata`,
          h('div', { class: 'bf-dash__actions' },
            h('button', { class: 'bf-dash__bouton', type: 'button', onclick: () => { edition = !edition; rendre(); } }, edition ? 'Terminer' : 'Modifier les pourcentages et salaires de base'),
            edition ? h('button', { class: 'bf-dash__bouton', type: 'button', onclick: () => { reglages = defaut(); sauver(); rendre(); } }, `Remettre ${PCT_DEFAUT} % et 0 $ pour tous`) : null),
          S.length ? h('div', { class: 'bf-dash__defile' }, h('table', { class: 'bf-dash__table bf-dash__vendeurs bf-dash__paie' },
            h('thead', {}, h('tr', {}, ['Vendeur', 'Ventes', 'Nb', 'Marge', '% comm.', 'Base / an', 'Commission', 'Rémunération', 'Heures', '$ / heure', 'Leads', 'Visites', 'Soumissions', 'Closing', 'Lead → vente', 'Coût de vente']
              .map((t, i) => h('th', { class: i ? 'num' : '' }, t)))),
            h('tbody', {}, [...S.map((x) => h('tr', {},
              h('td', {}, h('strong', {}, x.nom), h('div', { class: 'bf-dash__muet' }, x.succursales.join(', '))),
              h('td', { class: 'num' }, compact(x.ventes)), h('td', { class: 'num' }, entier(x.nb)), h('td', { class: 'num' }, pctTxt(x.pctMarge)),
              h('td', { class: 'num' }, edition ? h('input', { type: 'number', min: 0, max: 100, step: 0.5, value: x.pct, class: 'bf-dash__champ', 'aria-label': `Pourcentage de commission de ${x.nom}`,
                onchange: (ev) => { reglages.vendeurs[x.id].pct = Math.min(100, Math.max(0, Number(ev.target.value) || 0)); sauver(); setTimeout(rendre, 0); } }) : `${x.pct.toLocaleString('fr-CA')} %`),
              h('td', { class: 'num' }, edition ? h('input', { type: 'number', min: 0, step: 1000, value: x.salaire, class: 'bf-dash__champ', 'aria-label': `Salaire de base annuel de ${x.nom}`,
                onchange: (ev) => { reglages.vendeurs[x.id].salaire = Math.max(0, Math.round(Number(ev.target.value) || 0)); sauver(); setTimeout(rendre, 0); } }) : compact(x.salaire)),
              h('td', { class: 'num' }, dollars(x.commission)), h('td', { class: 'num' }, h('strong', {}, dollars(x.remuneration))),
              h('td', { class: 'num' }, entier(x.heures)), h('td', { class: 'num' }, x.heures ? dollars(x.parHeure) : 'n/d'),
              h('td', { class: 'num' }, entier(x.leads)), h('td', { class: 'num' }, entier(x.visites)), h('td', { class: 'num' }, entier(x.soumissions)),
              h('td', { class: 'num' }, pctTxt(x.closing, 1)), h('td', { class: 'num' }, pctTxt(x.leadVente, 1)), h('td', { class: 'num' }, pctTxt(x.coutVente, 1)))),
            h('tr', { class: 'bf-dash__vendeur' }, h('td', {}, 'Équipe'), h('td', { class: 'num' }, compact(T.ventes)), h('td', { class: 'num' }, entier(T.nb)),
              h('td', { class: 'num' }, pctTxt(T.ventes ? T.marge / T.ventes : 0)), h('td', { class: 'num' }, ''), h('td', { class: 'num' }, ''),
              h('td', { class: 'num' }, dollars(T.commission)), h('td', { class: 'num' }, dollars(T.remuneration)), h('td', { class: 'num' }, entier(T.heures)),
              h('td', { class: 'num' }, T.heures ? dollars(T.remuneration / T.heures) : ''), h('td', { class: 'num' }, entier(tot(S, 'leads'))), h('td', { class: 'num' }, entier(tot(S, 'visites'))),
              h('td', { class: 'num' }, entier(T.soumissions)), h('td', { class: 'num' }, pctTxt(closingEquipe, 1)), h('td', { class: 'num' }, pctTxt(tot(S, 'leads') ? T.nb / tot(S, 'leads') : 0, 1)),
              h('td', { class: 'num' }, pctTxt(T.ventes ? T.remuneration / T.ventes : 0, 1)))]))) : vide('Aucun vendeur.'),
          h('p', { class: 'bf-dash__muet' }, `Closing = ventes / soumissions envoyées. Lead → vente = ventes / leads reçus. Coût de vente = rémunération / ventes. `
            + (surMarge ? 'Commission sur la marge : le vendeur gagne moins s\'il donne des rabais.' : 'Commission sur les ventes : à surveiller avec la marge, un rabais ne coûte rien au vendeur.'))),

        h('div', { class: 'bf-dash__rangee' },
          carteGraph('Rémunération par vendeur', `${P.libelle} | commission et salaire de base`,
            S.length ? barresEmpilees(S.map((x) => ({ libelle: x.nom, sous: `${compact(x.ventes)} rentrés | ${x.pct.toLocaleString('fr-CA')} % ${surMarge ? 'de la marge' : 'des ventes'}`,
              total: x.remuneration, parts: { commission: x.commission, base: x.base },
              bulle: [[x.heures ? dollars(x.parHeure) : 'n/d', 'par heure travaillée'], [pctTxt(x.coutVente, 1), 'des ventes']] })), SERIES_PAIE, { format: dollars }) : vide()),
          carteGraph('Taux de closing par vendeur', `${P.libelle} | ventes / soumissions | équipe : ${pctTxt(closingEquipe, 1)}`,
            S.length ? barres([...S].sort((a, b) => b.closing - a.closing).map((x) => ({ libelle: x.nom,
              sous: `${entier(x.nb)} ventes sur ${entier(x.soumissions)} soumissions | ${x.closing >= closingEquipe ? 'au-dessus' : 'sous'} la moyenne`,
              valeur: x.closing, texte: pctTxt(x.closing, 1), couleur: x.closing >= closingEquipe ? 'var(--d-s3)' : 'var(--d-s2)',
              bulle: [[pctTxt(x.leadVente, 1), 'des leads deviennent des ventes'], [entier(x.visites), 'visites']] }))) : vide(),
            h('div', { class: 'bf-dash__legende' }, h('span', {}, h('span', { class: 'bf-dash__cle', style: 'background:var(--d-s3)' }), 'Au-dessus de la moyenne de l\'équipe'),
              h('span', {}, h('span', { class: 'bf-dash__cle', style: 'background:var(--d-s2)' }), 'Sous la moyenne')))),

        h('div', { class: 'bf-dash__rangee bf-dash__rangee--2-1' },
          carteGraph('Travail fourni et ventes rentrées', `${P.libelle} | chaque point = un vendeur ; plus haut et plus à gauche = plus productif`, nuage(S)),
          carteGraph('À surveiller', 'Calculé à partir des chiffres affichés', h('ul', { class: 'bf-dash__pistes' }, constats(S, closingEquipe, T)))),

        carteGraph('Rémunération par mois', `12 derniers mois | ${filtres.vendeur ? VENDEURS[filtres.vendeur].nom : 'toute l\'équipe'}`,
          ...colonnesEmpilees({ mois: mois12, series: SERIES_PAIE, unite: '$', enPlein: (m) => P.mois.includes(m), aria: 'Rémunération par mois, commission et salaire de base',
            valeurs: mois12.map((m) => { const l = ids.map((id) => stats(id, [m])); return { commission: tot(l, 'commission'), base: tot(l, 'base') }; }) })));
    }

    // Nuage de points : heures travaillées (x) et ventes rentrées (y), un point par vendeur, nommé
    function nuage(S) {
      if (!S.length) return vide();
      const W = window.innerWidth < 640 ? 360 : 640; const H = 300; const g = 56; const d = 20; const b = 34; const t = 14;
      const maxX = Math.max(...S.map((x) => x.heures)) * 1.1; const maxY = Math.max(...S.map((x) => x.ventes)) * 1.15;
      const pasY = [100000, 250000, 500000, 1000000, 2000000].find((p) => maxY / p <= 6) || 5000000;
      const pasX = [50, 100, 250, 500].find((p) => maxX / p <= 6) || 1000;
      const X = (v) => g + (v / maxX) * (W - g - d); const Y = (v) => t + (H - t - b) - (v / maxY) * (H - t - b);
      const s = svg('svg', { viewBox: `0 0 ${W} ${H}`, class: 'bf-dash__svg', role: 'img', 'aria-label': 'Heures travaillées et ventes rentrées par vendeur' });
      for (let v = 0; v <= maxY; v += pasY) {
        s.append(svg('line', { x1: g, x2: W - d, y1: Y(v), y2: Y(v), class: v ? 'bf-dash__grille' : 'bf-dash__axe' }));
        const tx = svg('text', { x: g - 6, y: Y(v) + 4, class: 'bf-dash__tick', 'text-anchor': 'end' }); tx.textContent = compact(v); s.append(tx);
      }
      for (let v = 0; v <= maxX; v += pasX) {
        const tx = svg('text', { x: X(v), y: H - b + 16, class: 'bf-dash__tick', 'text-anchor': 'middle' }); tx.textContent = entier(v); s.append(tx);
      }
      const titreX = svg('text', { x: (g + W - d) / 2, y: H - 4, class: 'bf-dash__tick', 'text-anchor': 'middle' }); titreX.textContent = 'heures travaillées'; s.append(titreX);
      // Moyenne de l'équipe : ventes par heure (droite depuis l'origine)
      const vh = S.reduce((a, x) => a + x.ventes, 0) / (S.reduce((a, x) => a + x.heures, 0) || 1);
      const xFin = Math.min(maxX, maxY / vh);
      s.append(svg('line', { x1: X(0), y1: Y(0), x2: X(xFin), y2: Y(xFin * vh), class: 'bf-dash__reticule', 'stroke-dasharray': '4 4' }));
      const xm = xFin * 0.3;
      const tm = svg('text', { x: X(xm) + 6, y: Y(xm * vh) + 16, class: 'bf-dash__tick' }); tm.textContent = `moyenne de l'équipe : ${dollars(vh)} de ventes par heure`; s.append(tm);
      // Étiquettes : à droite du point, sinon à gauche, sinon dessous, pour ne pas se chevaucher
      const boites = [];
      const libre = (bx) => !boites.some((o) => bx.x < o.x + o.l && bx.x + bx.l > o.x && bx.y < o.y + o.h && bx.y + bx.h > o.y);
      for (const x of [...S].sort((a, b) => b.ventes - a.ventes)) {
        const l = prenom(x.nom).length * 7 + 4; const px = X(x.heures); const py = Y(x.ventes);
        const essais = [{ x: px + 9, y: py - 18, ancre: 'start' }, { x: px - 9 - l, y: py - 18, ancre: 'end' }, { x: px - l / 2, y: py + 8, ancre: 'middle' }, { x: px + 9, y: py + 2, ancre: 'start' }];
        const ok = essais.find((e) => libre({ x: e.x, y: e.y, l, h: 14 })) || essais[0];
        boites.push({ x: ok.x, y: ok.y, l, h: 14 });
        x.etiquette = { x: ok.ancre === 'end' ? ok.x + l : ok.ancre === 'middle' ? ok.x + l / 2 : ok.x, y: ok.y + 11, ancre: ok.ancre };
      }
      for (const x of S) {
        const gr = svg('g', { class: 'bf-dash__point' });
        gr.append(svg('circle', { cx: X(x.heures), cy: Y(x.ventes), r: 12, fill: 'transparent' }),
          svg('circle', { cx: X(x.heures), cy: Y(x.ventes), r: 5.5, fill: x.ventesHeure >= vh ? 'var(--d-s3)' : 'var(--d-s2)', stroke: '#182036', 'stroke-width': 2 }));
        const lab = svg('text', { x: x.etiquette.x, y: x.etiquette.y, 'text-anchor': x.etiquette.ancre, class: 'bf-dash__etiquette-point' }); lab.textContent = prenom(x.nom);
        gr.append(lab);
        survol(gr, () => [[x.nom, ''], [compact(x.ventes), 'rentrés'], [entier(x.heures), 'heures'], [dollars(x.ventesHeure), 'de ventes par heure'], [dollars(x.parHeure), 'gagnés par heure']]);
        s.append(gr);
      }
      return h('div', {}, s, h('div', { class: 'bf-dash__legende' },
        h('span', {}, h('span', { class: 'bf-dash__cle', style: 'background:var(--d-s3)' }), 'Au-dessus de la moyenne de ventes par heure'),
        h('span', {}, h('span', { class: 'bf-dash__cle', style: 'background:var(--d-s2)' }), 'Sous la moyenne')));
    }

    function constats(S, closingEquipe, T) {
      if (!S.length) return [h('li', {}, 'Aucun vendeur dans ce filtre.')];
      const l = [];
      const parH = [...S].filter((x) => x.heures).sort((a, b) => b.ventesHeure - a.ventesHeure);
      if (parH.length > 1) l.push(`Plus productif : ${parH[0].nom}, ${dollars(parH[0].ventesHeure)} de ventes par heure. Le moins : ${parH[parH.length - 1].nom}, ${dollars(parH[parH.length - 1].ventesHeure)}.`);
      for (const x of S) if (x.soumissions >= 20 && x.closing < closingEquipe - 0.06) l.push(`${x.nom} ferme ${pctTxt(x.closing, 1)} de ses soumissions, contre ${pctTxt(closingEquipe, 1)} pour l'équipe : coaching sur le suivi des soumissions ?`);
      const margeEquipe = T.ventes ? T.marge / T.ventes : 0;
      for (const x of S) if (x.ventes > 0 && x.pctMarge < margeEquipe - 0.008) l.push(`${x.nom} vend avec une marge de ${pctTxt(x.pctMarge, 1)} (équipe : ${pctTxt(margeEquipe, 1)}) : rabais plus généreux ?${reglages.base === 'ventes' ? ' Avec une commission sur les ventes, ces rabais ne lui coûtent rien.' : ''}`);
      const cout = [...S].sort((a, b) => b.coutVente - a.coutVente)[0];
      if (cout && S.length > 1) l.push(`Coût de vente le plus élevé : ${cout.nom}, ${pctTxt(cout.coutVente, 1)} de ses ventes vont à sa rémunération.`);
      if (reglages.base === 'ventes' && T.marge) l.push(`Info : payer ${pctTxt(T.ventes ? T.commission / T.ventes : 0, 1)} des ventes équivaut ici à ${pctTxt(T.commission / T.marge, 1)} de la marge brute. Change « Commission calculée sur » en haut pour comparer.`);
      return l.map((t) => h('li', {}, t));
    }

    rendre();
    let etroitAvant = window.innerWidth < 640;
    window.addEventListener('resize', () => { const e = window.innerWidth < 640; if (e !== etroitAvant) { etroitAvant = e; rendre(); } });
  }
}
