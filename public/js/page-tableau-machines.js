// Tableau exécutif des machines HVAC (ADR-068, ADR-069) : d'où viennent les machines, où elles sont vendues,
// quels modèles se vendent le plus, dans quel territoire, par quel vendeur ; marge brute (avec et avant installation) et stock. Données FICTIVES tant que l'app de Mike n'est pas branchée.
// Graphiques en SVG maison (aucune librairie) ; couleurs validées sur le fond sombre (outil de validation dataviz).
import { initPage } from './bf-page.js?v=0.4.0';
import { h, remplir } from './bf-dom.js?v=0.4.0';
import { voitBoard } from './bf-crm.js?v=0.4.0';
import { creerCarte, chargerMunicipalites, chargerReperes } from './bf-carte.js?v=0.4.0';
import { TYPES, SUCCURSALES, FOURNISSEURS, MODELES, VENDEURS, LIEUX_STOCK, ventesFictives, stockFictif, moisJusqua } from './bf-ventes-fictives.js?v=0.4.0';

const NS = 'http://www.w3.org/2000/svg';
const FIN = '2026-10';
const COULEUR_TYPE = { mural_simple: 'var(--d-s1)', mural_multi: 'var(--d-s2)', central: 'var(--d-s3)', bienergie: 'var(--d-s4)' };
const SEQ = ['#256abf', '#3987e5', '#6da7ec', '#9ec5f4', '#cde2fb'];   // une teinte, du plus bas au plus haut
const MOIS_COURT = ['janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin', 'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.'];
const nomMois = (m) => `${MOIS_COURT[Number(m.slice(5)) - 1]} ${m.slice(2, 4)}`;
const REGIONS = { HO: ['Laurentides', 'Lanaudière'], RO: ['Laurentides', 'Laval', 'Lanaudière'], ST: ['Laurentides'], GA: ['Outaouais'], DR: ['Centre-du-Québec', 'Montérégie'] };
const PERIODES = {
  '12m': { libelle: '12 derniers mois', mois: moisJusqua(FIN, 12), avant: moisJusqua('2025-10', 12), compare: 'vs 12 mois précédents' },
  '3m': { libelle: '3 derniers mois', mois: moisJusqua(FIN, 3), avant: moisJusqua('2026-07', 3), compare: 'vs 3 mois précédents' },
  mois: { libelle: 'Octobre 2026', mois: [FIN], avant: ['2026-09'], compare: 'vs septembre' },
  annee: { libelle: 'Année 2026 (à ce jour)', mois: moisJusqua(FIN, 10), avant: moisJusqua('2025-10', 10), compare: 'vs même période 2025' },
};

const compact = (n) => (n >= 1e6 ? `${(n / 1e6).toLocaleString('fr-CA', { maximumFractionDigits: 2 })} M$` : n >= 1e3 ? `${Math.round(n / 1e3).toLocaleString('fr-CA')} k$` : `${Math.round(n)} $`);
const entier = (n) => Math.round(n).toLocaleString('fr-CA');
const pctTxt = (x) => `${(x * 100).toLocaleString('fr-CA', { maximumFractionDigits: 0 })} %`;
const svg = (tag, attrs = {}) => { const e = document.createElementNS(NS, tag); for (const [k, v] of Object.entries(attrs)) e.setAttribute(k, v); return e; };

// Une seule infobulle, contenu en textContent (les libellés sont des données)
const bulle = h('div', { class: 'bf-dash__bulle', role: 'status', hidden: true });
function montrerBulle(ev, lignes) {
  bulle.replaceChildren(...lignes.map(([v, l, c]) => h('div', { class: 'bf-dash__bulle-ligne' },
    c ? h('span', { class: 'bf-dash__cle', style: `background:${c}` }) : null, h('strong', {}, v), l ? h('span', {}, ` ${l}`) : null)));
  bulle.hidden = false;
  const x = ev.clientX ?? (ev.target.getBoundingClientRect().left + 10);
  const y = ev.clientY ?? ev.target.getBoundingClientRect().top;
  const l = Math.min(x + 14, window.innerWidth - bulle.offsetWidth - 8);
  bulle.style.left = `${Math.max(8, l)}px`; bulle.style.top = `${Math.max(8, y - bulle.offsetHeight - 10)}px`;
}
const cacherBulle = () => { bulle.hidden = true; };
function survol(el, lignes) {
  el.setAttribute('tabindex', '0');
  el.addEventListener('pointermove', (e) => montrerBulle(e, lignes()));
  el.addEventListener('focus', (e) => montrerBulle(e, lignes()));
  el.addEventListener('pointerleave', cacherBulle);
  el.addEventListener('blur', cacherBulle);
}

const carteGraph = (titre, sousTitre, ...contenu) => h('section', { class: 'bf-dash__carte' },
  h('div', { class: 'bf-dash__carte-tete' }, h('h2', {}, titre), sousTitre ? h('p', {}, sousTitre) : null), ...contenu);

const ICONES = {
  machines: 'M3 6h18v7H3zM7 17v3M12 17v3M17 17v3',
  argent: 'M12 3v18M16.5 7.5C16 6 14.3 5 12 5c-2.8 0-4.5 1.4-4.5 3.3 0 4.7 9 2.4 9 7.2 0 2-1.9 3.5-4.5 3.5-2.4 0-4.2-1-4.8-2.7',
  moyenne: 'M4 20V10M10 20V4M16 20v-7M22 20H2',
  carte: 'M12 21s-7-6.2-7-11.5a7 7 0 0114 0C19 14.8 12 21 12 21zM12 12a2.5 2.5 0 100-5 2.5 2.5 0 000 5z',
  entrepot: 'M3 10l9-6 9 6v10H3zM7 20v-6h10v6M7 17h10',
  marge: 'M19 5L5 19M7.5 9a1.5 1.5 0 100-3 1.5 1.5 0 000 3zM16.5 18a1.5 1.5 0 100-3 1.5 1.5 0 000 3z',
  stock: 'M3 8l9-4 9 4-9 4zM3 8v8l9 4 9-4V8M12 12v8',
};
const icone = (nom) => { const s = svg('svg', { viewBox: '0 0 24 24', 'aria-hidden': 'true' }); s.append(svg('path', { d: ICONES[nom] })); return s; };

// delta : variation relative (0,12 = +12 %) ; avec points: true, écart en points de pourcentage (marge)
function tuile(ic, libelle, valeur, delta, compare, { hausseBonne = true, points = false, note = null } = {}) {
  let d = null;
  if (delta !== null && Number.isFinite(delta)) {
    const bon = delta === 0 ? null : (delta > 0) === hausseBonne;
    const n = (delta * 100).toLocaleString('fr-CA', { maximumFractionDigits: 1 });
    d = h('p', { class: `bf-dash__delta${bon === true ? ' bf-dash__delta--bon' : bon === false ? ' bf-dash__delta--mauvais' : ''}` },
      `${delta > 0 ? '▲ +' : delta < 0 ? '▼ ' : ''}${n}${points ? ' pt' : ' %'}`, h('span', {}, ` ${compare}`));
  }
  return h('div', { class: 'bf-dash__tuile' }, h('span', { class: 'bf-dash__tuile-icone' }, icone(ic)),
    h('div', {}, h('p', { class: 'bf-dash__tuile-libelle' }, libelle), h('p', { class: 'bf-dash__tuile-valeur' }, valeur),
      note ? h('p', { class: 'bf-dash__delta' }, h('span', {}, note)) : null, d));
}

// Barres empilées par type, une ligne par élément : [{ libelle, sous, parType: {type: n}, total, bulle }]
function barresEmpilees(lignes, typesVisibles) {
  const max = Math.max(1, ...lignes.map((l) => l.total));
  return h('ol', { class: 'bf-dash__barres' }, lignes.map((l, i) => {
    const piste = h('span', { class: 'bf-dash__barre-piste bf-dash__barre-piste--empilee' },
      ...typesVisibles.filter((t) => l.parType[t]).map((t) => h('span', { class: 'bf-dash__seg-h', style: `width:${(l.parType[t] / max) * 100}%;background:${COULEUR_TYPE[t]}` })));
    const li = h('li', {}, h('span', { class: 'bf-dash__rang' }, String(i + 1)),
      h('span', { class: 'bf-dash__barre-libelle' }, h('span', {}, l.libelle), l.sous ? h('span', { class: 'bf-dash__muet' }, l.sous) : null),
      piste, h('strong', { class: 'num' }, entier(l.total)));
    survol(li, () => [[`${entier(l.total)}`, l.libelle], ...typesVisibles.map((t) => [String(l.parType[t] || 0), TYPES[t], COULEUR_TYPE[t]]), ...(l.bulle || [])]);
    return li;
  }));
}

// Colonnes empilées par type, un mois par colonne ; mois de la période en plein, les autres atténués
function colonnesMensuelles(ventes, moisPeriode, typesVisibles) {
  const mois = moisJusqua(FIN, 12);
  const parMois = mois.map((m) => {
    const v = ventes.filter((x) => x.mois === m);
    return { m, total: v.length, parType: Object.fromEntries(typesVisibles.map((t) => [t, v.filter((x) => x.type === t).length])) };
  });
  const max = Math.max(1, ...parMois.map((x) => x.total));
  const pas = max > 150 ? 50 : max > 60 ? 20 : max > 25 ? 10 : 5;
  const haut = Math.ceil(max / pas) * pas;
  const W = window.innerWidth < 640 ? 360 : 640; const H = window.innerWidth < 640 ? 220 : 240; const g = 34; const b = 22; const largeur = W - g - 8; const hauteur = H - b - 10;
  const s = svg('svg', { viewBox: `0 0 ${W} ${H}`, class: 'bf-dash__svg', role: 'img', 'aria-label': 'Machines vendues par mois, par type de système' });
  for (let v = 0; v <= haut; v += pas) {
    const y = 10 + hauteur - (v / haut) * hauteur;
    s.append(svg('line', { x1: g, x2: W - 8, y1: y, y2: y, class: v ? 'bf-dash__grille' : 'bf-dash__axe' }));
    const t = svg('text', { x: g - 6, y: y + 4, class: 'bf-dash__tick', 'text-anchor': 'end' }); t.textContent = v; s.append(t);
  }
  const bande = largeur / mois.length; const bw = Math.min(24, bande * 0.6);
  parMois.forEach((p, i) => {
    const x = g + i * bande + (bande - bw) / 2;
    const groupe = svg('g', { class: `bf-dash__col${moisPeriode.includes(p.m) ? '' : ' bf-dash__col--hors'}` });
    let y = 10 + hauteur;
    const segs = typesVisibles.filter((t) => p.parType[t] > 0);
    segs.forEach((t, k) => {
      const hseg = (p.parType[t] / haut) * hauteur;
      const dernier = k === segs.length - 1;
      const yh = y - hseg + (k ? 0 : 0);
      // 2 px de fond entre les segments ; extrémité arrondie seulement en haut
      const hd = Math.max(0, hseg - (dernier ? 0 : 2));
      groupe.append(dernier
        ? svg('path', { d: `M${x},${yh + hd}V${yh + Math.min(4, hd)}q0,-4 4,-4h${bw - 8}q4,0 4,4V${yh + hd}z`, fill: COULEUR_TYPE[t] })
        : svg('rect', { x, y: yh, width: bw, height: hd, fill: COULEUR_TYPE[t] }));
      y -= hseg;
    });
    const zone = svg('rect', { x: g + i * bande, y: 10, width: bande, height: hauteur, fill: 'transparent', class: 'bf-dash__cible' });
    survol(zone, () => [[`${p.total} machines`, nomMois(p.m)], ...typesVisibles.map((t) => [String(p.parType[t]), TYPES[t], COULEUR_TYPE[t]])]);
    groupe.append(zone);
    const t = svg('text', { x: g + i * bande + bande / 2, y: H - 6, class: 'bf-dash__tick', 'text-anchor': 'middle' }); t.textContent = W < 640 ? nomMois(p.m)[0].toUpperCase() : nomMois(p.m).split(' ')[0];
    s.append(groupe, t);
  });
  const legende = h('div', { class: 'bf-dash__legende' }, typesVisibles.map((t) => h('span', {}, h('span', { class: 'bf-dash__cle', style: `background:${COULEUR_TYPE[t]}` }), TYPES[t])));
  const table = h('details', { class: 'bf-dash__donnees' }, h('summary', {}, 'Voir les données'), h('div', { class: 'bf-dash__defile' }, h('table', {},
    h('thead', {}, h('tr', {}, h('th', {}, 'Mois'), ...typesVisibles.map((t) => h('th', {}, TYPES[t])), h('th', {}, 'Total'))),
    h('tbody', {}, parMois.map((p) => h('tr', {}, h('td', {}, nomMois(p.m)), ...typesVisibles.map((t) => h('td', { class: 'num' }, p.parType[t])), h('td', { class: 'num' }, p.total)))))));
  return [legende, s, table];
}

// Anneau : part de chaque type
function anneau(ventes, typesVisibles) {
  const total = ventes.length || 1;
  const parts = typesVisibles.map((t) => ({ t, n: ventes.filter((x) => x.type === t).length })).filter((p) => p.n);
  const s = svg('svg', { viewBox: '0 0 200 200', class: 'bf-dash__anneau', role: 'img', 'aria-label': 'Répartition des machines par type de système' });
  const R = 80; const r = 56; const C = 100;
  let a0 = -Math.PI / 2;
  const ecart = parts.length > 1 ? 0.025 : 0;
  for (const p of parts) {
    const a1 = a0 + (p.n / total) * Math.PI * 2;
    const d0 = a0 + ecart / 2; const d1 = Math.max(d0 + 0.001, a1 - ecart / 2);
    const grand = d1 - d0 > Math.PI ? 1 : 0;
    const pt = (rad, a) => `${C + rad * Math.cos(a)},${C + rad * Math.sin(a)}`;
    const chemin = parts.length === 1
      ? `M${C},${C - R}a${R},${R} 0 1,1 -0.01,0zM${C},${C - r}a${r},${r} 0 1,0 0.01,0z`
      : `M${pt(R, d0)}A${R},${R} 0 ${grand},1 ${pt(R, d1)}L${pt(r, d1)}A${r},${r} 0 ${grand},0 ${pt(r, d0)}z`;
    const seg = svg('path', { d: chemin, fill: COULEUR_TYPE[p.t], class: 'bf-dash__seg', 'fill-rule': 'evenodd' });
    survol(seg, () => [[`${p.n} machines`, `${TYPES[p.t]} (${pctTxt(p.n / total)})`, COULEUR_TYPE[p.t]]]);
    s.append(seg);
    a0 = a1;
  }
  const t1 = svg('text', { x: C, y: C - 2, class: 'bf-dash__anneau-total', 'text-anchor': 'middle' }); t1.textContent = entier(ventes.length);
  const t2 = svg('text', { x: C, y: C + 20, class: 'bf-dash__tick', 'text-anchor': 'middle' }); t2.textContent = 'machines';
  s.append(t1, t2);
  const liste = h('ul', { class: 'bf-dash__parts' }, parts.map((p) => h('li', {},
    h('span', { class: 'bf-dash__cle', style: `background:${COULEUR_TYPE[p.t]}` }), h('span', {}, TYPES[p.t]),
    h('strong', {}, entier(p.n)), h('span', { class: 'bf-dash__muet' }, pctTxt(p.n / total)))));
  return h('div', { class: 'bf-dash__anneau-zone' }, s, liste);
}

// Barres horizontales : [{ libelle, sous, valeur, texte, couleur }]
function barres(lignes, { couleur = 'var(--d-s1)' } = {}) {
  const max = Math.max(1, ...lignes.map((l) => l.valeur));
  return h('ol', { class: 'bf-dash__barres' }, lignes.map((l, i) => {
    const barre = h('span', { class: 'bf-dash__barre', style: `width:${Math.max(1.5, (l.valeur / max) * 100)}%;background:${l.couleur || couleur}` });
    const li = h('li', {}, h('span', { class: 'bf-dash__rang' }, String(i + 1)),
      h('span', { class: 'bf-dash__barre-libelle' }, h('span', {}, l.libelle), l.sous ? h('span', { class: 'bf-dash__muet' }, l.sous) : null),
      h('span', { class: 'bf-dash__barre-piste' }, barre), h('strong', { class: 'num' }, l.texte));
    survol(li, () => [[l.texte, l.libelle], ...(l.bulle || [])]);
    return li;
  }));
}

const user = await initPage();
if (user) {
  const zone = document.getElementById('contenu');
  if (!voitBoard(user)) {
    remplir(zone, h('h1', {}, 'Tableau des machines'), h('p', { class: 'bf-message' }, 'Réservé à la direction et aux gérants.'));
  } else {
    const toutes = ventesFictives(FIN);
    const [geo, reperes] = await Promise.all([chargerMunicipalites(), chargerReperes()]);
    // Nom de municipalité -> codes, limités aux régions de la succursale (plusieurs municipalités portent le même nom)
    const codesDe = new Map();
    const codeVille = (succ, nom) => {
      const cle = `${succ}|${nom}`;
      if (!codesDe.has(cle)) {
        const fs = (geo?.features || []).filter((f) => f.properties.nom === nom && REGIONS[succ].includes(f.properties.region));
        codesDe.set(cle, fs.map((f) => f.properties.code));
      }
      return codesDe.get(cle);
    };

    const stock = stockFictif();
    const filtres = { periode: '12m', succursale: '', type: '', marque: '', vendeur: '' };
    const choix = (nom, libelle, options) => {
      const sel = h('select', { 'aria-label': libelle }, options.map(([v, t]) => h('option', { value: v, selected: filtres[nom] === v }, t)));
      sel.addEventListener('change', () => { filtres[nom] = sel.value; rendre(); });
      return sel;
    };
    const barreFiltres = h('div', { class: 'bf-dash__filtres' },
      choix('periode', 'Période', Object.entries(PERIODES).map(([k, p]) => [k, p.libelle])),
      choix('succursale', 'Succursale', [['', 'Toutes les succursales'], ...Object.entries(SUCCURSALES).map(([k, s]) => [k, s.nom])]),
      choix('type', 'Type de système', [['', 'Tous les types'], ...Object.entries(TYPES)]),
      choix('marque', 'Marque', [['', 'Toutes les marques'], ...[...new Set(MODELES.map((m) => m.marque))].map((m) => [m, m])]),
      choix('vendeur', 'Vendeur', [['', 'Tous les vendeurs'], ...Object.entries(VENDEURS).map(([k, v]) => [k, v.nom])]));

    const corps = h('div', { class: 'bf-dash__corps' });
    const panneau = h('div', { class: 'bf-dash' },
      h('div', { class: 'bf-dash__entete' },
        h('div', {}, h('h1', {}, 'Vue exécutive | Machines HVAC'),
          h('p', {}, 'D\'où viennent les machines, où elles sont vendues, quels modèles se vendent le plus et dans quel territoire.')),
        h('div', { class: 'bf-dash__entete-droite' }, h('span', { class: 'bf-dash__fictif' }, 'Données fictives'),
          h('button', { class: 'bf-dash__bouton', type: 'button', onclick: () => (document.fullscreenElement ? document.exitFullscreen() : panneau.requestFullscreen?.()) }, 'Plein écran'))),
      barreFiltres, corps, bulle);
    remplir(zone, panneau);

    let carte = null;
    const zoneCarte = h('div', { class: 'bf-dash__carte-geo' });
    let densite = new Map();

    function rendre() {
      cacherBulle();
      const P = PERIODES[filtres.periode];
      const garder = (v) => (!filtres.succursale || v.succursale === filtres.succursale) && (!filtres.type || v.type === filtres.type)
        && (!filtres.marque || v.marque === filtres.marque) && (!filtres.vendeur || v.vendeur === filtres.vendeur);
      const base = toutes.filter(garder);
      const ventes = base.filter((v) => P.mois.includes(v.mois));
      const avant = base.filter((v) => P.avant.includes(v.mois));
      const somme = (l) => l.reduce((s, v) => s + v.prix_cents, 0);
      const delta = (a, b) => (b ? (a - b) / b : null);
      // Marge totale : machine + installation (la marge de référence). Marge avant installation : la machine seule.
      const marge = (l) => { const p = somme(l); return p ? (p - l.reduce((s, v) => s + v.cout_cents, 0)) / p : 0; };
      const margeMachine = (l) => {
        const p = l.reduce((s, v) => s + v.prix_cents - v.prix_installation_cents, 0);
        return p ? (p - l.reduce((s, v) => s + v.cout_cents - v.cout_installation_cents, 0)) / p : 0;
      };
      const margeMachine$ = (l) => l.reduce((s, v) => s + (v.prix_cents - v.prix_installation_cents) - (v.cout_cents - v.cout_installation_cents), 0);
      // Stock au dernier jour : selon la succursale (son stock, plus l'entrepôt central qui la sert), le type et la marque
      const stockVu = stock.filter((x) => (!filtres.type || x.type === filtres.type) && (!filtres.marque || x.marque === filtres.marque)
        && (!filtres.succursale || x.lieu === filtres.succursale || x.lieu === 'entrepot'));
      const enStock = stockVu.reduce((s, x) => s + x.qte, 0);
      const ventes3m = base.filter((v) => moisJusqua(FIN, 3).includes(v.mois)).length;
      const semaines = ventes3m ? enStock / (ventes3m / 13) : null;
      // Vendeurs
      const parVendeur = Object.entries(VENDEURS).map(([id, vd]) => ({ id, vd, v: ventes.filter((x) => x.vendeur === id) }))
        .filter((x) => x.v.length).sort((a, b) => b.v.length - a.v.length);
      const compte = (l, t) => l.filter((x) => x.type === t).length;
      const parLieu = Object.entries(LIEUX_STOCK).map(([k, nom]) => ({ k, nom, l: stockVu.filter((x) => x.lieu === k) })).filter((x) => x.l.length);
      const typesVisibles = filtres.type ? [filtres.type] : Object.keys(TYPES);
      const munis = new Set(ventes.map((v) => `${v.succursale}|${v.municipalite}`));
      const partEntrepot = ventes.length ? ventes.filter((v) => v.provenance === 'entrepot').length / ventes.length : 0;
      const partAvant = avant.length ? avant.filter((v) => v.provenance === 'entrepot').length / avant.length : 0;

      // Modèles les plus vendus
      const parModele = MODELES.map((m) => ({ m, n: ventes.filter((v) => v.modele === m.code).length, $: somme(ventes.filter((v) => v.modele === m.code)) }))
        .filter((x) => x.n).sort((a, b) => b.n - a.n).slice(0, 8);
      // Territoires (succursales)
      const parSucc = Object.entries(SUCCURSALES).map(([k, s]) => ({ k, s, v: ventes.filter((x) => x.succursale === k) }))
        .filter((x) => x.v.length).sort((a, b) => b.v.length - a.v.length);
      // Provenance
      const parFour = Object.entries(FOURNISSEURS).map(([k, nom]) => {
        const v = ventes.filter((x) => x.fournisseur === k);
        return { nom, n: v.length, delai: v.length ? v.reduce((s, x) => s + x.delai_jours, 0) / v.length : 0, direct: v.filter((x) => x.provenance === 'direct').length };
      }).filter((x) => x.n).sort((a, b) => b.n - a.n);
      // Densité par municipalité pour la carte
      densite = new Map();
      for (const v of ventes) for (const c of codeVille(v.succursale, v.municipalite)) densite.set(c, (densite.get(c) || 0) + 1);
      const maxD = Math.max(1, ...densite.values());
      const bornes = [0.2, 0.4, 0.6, 0.8].map((q) => Math.max(1, Math.round(maxD * q)));
      const classe = (n) => bornes.filter((b) => n > b).length;

      // Matrice modèles x territoires
      const topMatrice = parModele.slice(0, 6);
      const succMat = Object.entries(SUCCURSALES).filter(([k]) => !filtres.succursale || k === filtres.succursale);
      const cellules = topMatrice.map(({ m }) => succMat.map(([k]) => ventes.filter((v) => v.modele === m.code && v.succursale === k).length));
      const maxCell = Math.max(1, ...cellules.flat());

      remplir(corps,
        h('div', { class: 'bf-dash__tuiles' },
          tuile('machines', 'Machines vendues', entier(ventes.length), delta(ventes.length, avant.length), P.compare),
          tuile('argent', 'Ventes avant taxes', compact(somme(ventes) / 100), delta(somme(ventes), somme(avant)), P.compare),
          tuile('marge', 'Marge brute (avec installation)', pctTxt(marge(ventes)), avant.length ? marge(ventes) - marge(avant) : null, P.compare,
            { points: true, note: `${compact((somme(ventes) - ventes.reduce((s, v) => s + v.cout_cents, 0)) / 100)} de marge` }),
          tuile('marge', 'Marge avant installation', pctTxt(margeMachine(ventes)), avant.length ? margeMachine(ventes) - margeMachine(avant) : null, P.compare,
            { points: true, note: `${compact(margeMachine$(ventes) / 100)} sur les machines seules` }),
          tuile('moyenne', 'Prix moyen par machine', ventes.length ? `${entier(somme(ventes) / ventes.length / 100)} $` : 'n/d',
            delta(ventes.length ? somme(ventes) / ventes.length : 0, avant.length ? somme(avant) / avant.length : 0), P.compare),
          tuile('stock', 'Machines en stock', entier(enStock), null, '',
            { note: semaines ? `≈ ${semaines.toLocaleString('fr-CA', { maximumFractionDigits: 1 })} semaines de ventes | ${compact(stockVu.reduce((s, x) => s + x.valeur_cents, 0) / 100)} au coût` : 'au dernier jour du mois' }),
          tuile('entrepot', 'Livrées de l\'entrepôt', pctTxt(partEntrepot), partAvant ? (partEntrepot - partAvant) / partAvant : null, P.compare),
          tuile('carte', 'Municipalités desservies', entier(munis.size), null, '')),
        h('div', { class: 'bf-dash__rangee bf-dash__rangee--2-1' },
          carteGraph('Machines vendues par mois', filtres.periode === '12m' ? '12 derniers mois' : `12 derniers mois | ${P.libelle} en plein`, ...colonnesMensuelles(base, P.mois, typesVisibles)),
          carteGraph('Répartition par type de système', P.libelle, anneau(ventes, typesVisibles))),
        h('div', { class: 'bf-dash__rangee' },
          carteGraph('Modèles les plus vendus', `${P.libelle} | unités`, parModele.length ? barres(parModele.map(({ m, n, $ }) => ({
            libelle: m.nom, sous: `${TYPES[m.type]} | ${FOURNISSEURS[m.fournisseur]}`, valeur: n, texte: entier(n), couleur: COULEUR_TYPE[m.type],
            bulle: [[compact($ / 100), 'avant taxes']] }))) : h('p', { class: 'bf-dash__muet' }, 'Aucune vente.')),
          carteGraph('Ventes par territoire', `${P.libelle} | unités et ventes avant taxes`, parSucc.length ? barres(parSucc.map(({ s, v }) => ({
            libelle: s.nom, sous: `${compact(somme(v) / 100)} | ${new Set(v.map((x) => x.municipalite)).size} municipalités`, valeur: v.length, texte: entier(v.length),
            bulle: typesVisibles.map((t) => [String(v.filter((x) => x.type === t).length), TYPES[t], COULEUR_TYPE[t]]) }))) : h('p', { class: 'bf-dash__muet' }, 'Aucune vente.'))),
        h('div', { class: 'bf-dash__rangee bf-dash__rangee--2-1' },
          carteGraph('Où sont vendues les machines', `${P.libelle} | machines par municipalité`, zoneCarte,
            h('div', { class: 'bf-dash__legende bf-dash__legende--seq' }, h('span', {}, 'Moins'),
              ...SEQ.map((c, i) => h('span', { class: 'bf-dash__cle bf-dash__cle--large', style: `background:${c}`,
                title: i === 0 ? `1 à ${bornes[0]}` : i < 4 ? `${bornes[i - 1] + 1} à ${bornes[i]}` : `plus de ${bornes[3]}` })),
              h('span', {}, 'Plus'), h('span', { class: 'bf-dash__muet' }, `| max ${entier(maxD)} machines`))),
          carteGraph('D\'où viennent les machines', `${P.libelle} | par fournisseur`,
            h('div', { class: 'bf-dash__jauge', role: 'img', 'aria-label': `${pctTxt(partEntrepot)} livrées de l'entrepôt central` },
              h('div', { class: 'bf-dash__jauge-plein', style: `width:${partEntrepot * 100}%` })),
            h('p', { class: 'bf-dash__muet' }, `${pctTxt(partEntrepot)} passent par l'entrepôt central de Saint-Jérôme, ${pctTxt(1 - partEntrepot)} livrées directement au chantier.`),
            h('div', { class: 'bf-dash__defile' }, h('table', { class: 'bf-dash__table' },
              h('thead', {}, h('tr', {}, h('th', {}, 'Fournisseur'), h('th', { class: 'num' }, 'Machines'), h('th', { class: 'num' }, 'Part'), h('th', { class: 'num' }, 'Délai moyen'))),
              h('tbody', {}, parFour.map((f) => h('tr', {}, h('td', {}, f.nom), h('td', { class: 'num' }, entier(f.n)),
                h('td', { class: 'num' }, pctTxt(f.n / (ventes.length || 1))), h('td', { class: 'num' }, `${f.delai.toLocaleString('fr-CA', { maximumFractionDigits: 1 })} j`)))))))),
        h('div', { class: 'bf-dash__rangee bf-dash__rangee--2-1' },
          carteGraph('Ventes par vendeur', `${P.libelle} | unités par type de système`,
            h('div', { class: 'bf-dash__legende' }, typesVisibles.map((t) => h('span', {}, h('span', { class: 'bf-dash__cle', style: `background:${COULEUR_TYPE[t]}` }), TYPES[t]))),
            parVendeur.length ? barresEmpilees(parVendeur.map(({ vd, v }) => ({
              libelle: vd.nom, sous: `${compact(somme(v) / 100)} | marge ${pctTxt(marge(v))} | avant inst. ${pctTxt(margeMachine(v))}`, total: v.length,
              parType: Object.fromEntries(typesVisibles.map((t) => [t, compte(v, t)])), bulle: [[compact(somme(v) / 100), 'avant taxes'], [pctTxt(marge(v)), 'marge avec installation'], [pctTxt(margeMachine(v)), 'marge avant installation']] })), typesVisibles)
              : h('p', { class: 'bf-dash__muet' }, 'Aucune vente.')),
          carteGraph('Machines en stock', 'Au 31 octobre 2026 | par lieu et par type',
            parLieu.length ? barresEmpilees(parLieu.map(({ nom, l }) => ({ libelle: nom, total: l.reduce((s, x) => s + x.qte, 0),
              sous: `${compact(l.reduce((s, x) => s + x.valeur_cents, 0) / 100)} au coût`,
              parType: Object.fromEntries(typesVisibles.map((t) => [t, l.filter((x) => x.type === t).reduce((s, x) => s + x.qte, 0)])) })), typesVisibles)
              : h('p', { class: 'bf-dash__muet' }, 'Aucune machine en stock.'))),
        carteGraph('Vendeurs par territoire et type de machine', `${P.libelle} | unités vendues par chaque vendeur, dans chaque territoire`,
          parVendeur.length ? h('div', { class: 'bf-dash__defile' }, h('table', { class: 'bf-dash__table bf-dash__vendeurs' },
            h('thead', {}, h('tr', {}, h('th', {}, 'Vendeur | territoire'),
              ...typesVisibles.map((t) => h('th', { class: 'num' }, h('span', { class: 'bf-dash__cle', style: `background:${COULEUR_TYPE[t]}` }), TYPES[t])),
              h('th', { class: 'num' }, 'Total'), h('th', { class: 'num' }, 'Ventes'), h('th', { class: 'num', title: 'Machine et installation' }, 'Marge totale'),
              h('th', { class: 'num', title: 'Machine seule, sans l\'installation' }, 'Marge avant inst.'))),
            h('tbody', {}, parVendeur.flatMap(({ vd, v }) => {
              const territoires = Object.entries(SUCCURSALES).map(([k, sc]) => ({ sc, l: v.filter((x) => x.succursale === k) })).filter((x) => x.l.length);
              const ligne = (libelle, l, classe) => h('tr', { class: classe }, h('td', {}, libelle),
                ...typesVisibles.map((t) => h('td', { class: 'num' }, compte(l, t) ? entier(compte(l, t)) : '')),
                h('td', { class: 'num' }, h('strong', {}, entier(l.length))), h('td', { class: 'num' }, compact(somme(l) / 100)), h('td', { class: 'num' }, pctTxt(marge(l))), h('td', { class: 'num' }, pctTxt(margeMachine(l))));
              return [ligne(vd.nom, v, 'bf-dash__vendeur'), ...(territoires.length > 1 || filtres.succursale === '' ? territoires.map(({ sc, l }) => ligne(`↳ ${sc.nom}`, l, 'bf-dash__territoire')) : [])];
            })))) : h('p', { class: 'bf-dash__muet' }, 'Aucune vente.')),
        carteGraph('Modèles par territoire', `${P.libelle} | les 6 modèles les plus vendus, en unités`,
          topMatrice.length ? h('div', { class: 'bf-dash__defile' }, h('table', { class: 'bf-dash__table bf-dash__matrice' },
            h('thead', {}, h('tr', {}, h('th', {}, 'Modèle'), ...succMat.map(([, s]) => h('th', { class: 'num' }, s.nom)), h('th', { class: 'num' }, 'Total'))),
            h('tbody', {}, topMatrice.map(({ m, n }, i) => h('tr', {}, h('td', {}, h('span', { class: 'bf-dash__cle', style: `background:${COULEUR_TYPE[m.type]}` }), m.nom),
              ...cellules[i].map((v) => {
                const k = v ? Math.min(4, Math.floor((v / maxCell) * 5 - 0.0001)) : -1;
                return h('td', { class: `num bf-dash__cellule${k >= 3 ? ' bf-dash__cellule--claire' : ''}`, style: k >= 0 ? `background:${SEQ[k]}` : '' }, v ? entier(v) : '');
              }),
              h('td', { class: 'num' }, h('strong', {}, entier(n)))))))) : h('p', { class: 'bf-dash__muet' }, 'Aucune vente.')));

      // Carte (créée une fois, recoloriée ensuite)
      if (geo) {
        if (!carte) {
          carte = creerCarte(zoneCarte, geo, {
            reperes, vueDepart: { ouest: -76.3, sud: 45.25, est: -71.6, nord: 46.35 },
            couleur: (code) => { const n = densite.get(code); return n ? SEQ[classe(n)] : 'var(--d-vide)'; },
            titre: (f) => f.properties.nom,
            onClic: (f) => { const n = densite.get(f.properties.code) || 0; montrerBulle({ clientX: innerWidth / 2, clientY: innerHeight / 2 }, [[`${n} machines`, f.properties.nom]]); },
          });
        }
        carte.redessiner();
      } else remplir(zoneCarte, h('p', { class: 'bf-dash__muet' }, 'Carte non disponible (limites municipales absentes).'));
    }
    rendre();
    // Le graphique mensuel change de format entre téléphone et écran large
    let etroit = window.innerWidth < 640;
    window.addEventListener('resize', () => { const e = window.innerWidth < 640; if (e !== etroit) { etroit = e; rendre(); } });
  }
}
