// Composants des tableaux exécutifs (ADR-068, ADR-072) : tuiles, infobulle, barres, colonnes empilées, anneau, lignes.
// SVG maison, aucune librairie. Les couleurs sont passées par les pages (palettes validées sur le fond sombre #182036).
// Les libellés sont des données : toujours insérés en textContent (via h()), jamais en HTML.
import { h } from './bf-dom.js?v=0.4.0';

const NS = 'http://www.w3.org/2000/svg';
export const SEQ = ['#256abf', '#3987e5', '#6da7ec', '#9ec5f4', '#cde2fb'];   // une teinte bleue, du plus bas au plus haut
const MOIS_COURT = ['janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin', 'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.'];
export const nomMois = (m) => `${MOIS_COURT[Number(m.slice(5)) - 1]} ${m.slice(2, 4)}`;
export const compact = (n) => (n >= 1e6 ? `${(n / 1e6).toLocaleString('fr-CA', { maximumFractionDigits: 2 })} M$`
  : n >= 1e3 ? `${Math.round(n / 1e3).toLocaleString('fr-CA')} k$` : `${Math.round(n)} $`);
export const entier = (n) => Math.round(n).toLocaleString('fr-CA');
export const pctTxt = (x, decimales = 0) => `${(x * 100).toLocaleString('fr-CA', { maximumFractionDigits: decimales })} %`;
export const dollars = (n) => `${Math.round(n).toLocaleString('fr-CA')} $`;
export const svg = (tag, attrs = {}) => { const e = document.createElementNS(NS, tag); for (const [k, v] of Object.entries(attrs)) e.setAttribute(k, v); return e; };
const etroit = () => window.innerWidth < 640;
const libelleMois = (m) => (etroit() ? nomMois(m)[0].toUpperCase() : nomMois(m).split(' ')[0]);

// Une seule infobulle par page. lignes : [[valeur, libellé, couleur?]]
export const bulle = h('div', { class: 'bf-dash__bulle', role: 'status', hidden: true });
export function montrerBulle(ev, lignes) {
  bulle.replaceChildren(...lignes.map(([v, l, c]) => h('div', { class: 'bf-dash__bulle-ligne' },
    c ? h('span', { class: 'bf-dash__cle', style: `background:${c}` }) : null, h('strong', {}, v), l ? h('span', {}, ` ${l}`) : null)));
  bulle.hidden = false;
  const x = ev.clientX ?? (ev.target.getBoundingClientRect().left + 10);
  const y = ev.clientY ?? ev.target.getBoundingClientRect().top;
  const l = Math.min(x + 14, window.innerWidth - bulle.offsetWidth - 8);
  bulle.style.left = `${Math.max(8, l)}px`; bulle.style.top = `${Math.max(8, y - bulle.offsetHeight - 10)}px`;
}
export const cacherBulle = () => { bulle.hidden = true; };
export function survol(el, lignes) {
  el.setAttribute('tabindex', '0');
  el.addEventListener('pointermove', (e) => montrerBulle(e, lignes()));
  el.addEventListener('focus', (e) => montrerBulle(e, lignes()));
  el.addEventListener('pointerleave', cacherBulle);
  el.addEventListener('blur', cacherBulle);
}

export const carteGraph = (titre, sousTitre, ...contenu) => h('section', { class: 'bf-dash__carte' },
  h('div', { class: 'bf-dash__carte-tete' }, h('h2', {}, titre), sousTitre ? h('p', {}, sousTitre) : null), ...contenu);
export const vide = (texte = 'Aucune donnée.') => h('p', { class: 'bf-dash__muet' }, texte);

const ICONES = {
  machines: 'M3 6h18v7H3zM7 17v3M12 17v3M17 17v3',
  argent: 'M12 3v18M16.5 7.5C16 6 14.3 5 12 5c-2.8 0-4.5 1.4-4.5 3.3 0 4.7 9 2.4 9 7.2 0 2-1.9 3.5-4.5 3.5-2.4 0-4.2-1-4.8-2.7',
  moyenne: 'M4 20V10M10 20V4M16 20v-7M22 20H2',
  carte: 'M12 21s-7-6.2-7-11.5a7 7 0 0114 0C19 14.8 12 21 12 21zM12 12a2.5 2.5 0 100-5 2.5 2.5 0 000 5z',
  entrepot: 'M3 10l9-6 9 6v10H3zM7 20v-6h10v6M7 17h10',
  marge: 'M19 5L5 19M7.5 9a1.5 1.5 0 100-3 1.5 1.5 0 000 3zM16.5 18a1.5 1.5 0 100-3 1.5 1.5 0 000 3z',
  stock: 'M3 8l9-4 9 4-9 4zM3 8v8l9 4 9-4V8M12 12v8',
  leads: 'M4 4h16v4l-6 6v6l-4-2v-4L4 8z',
  cible: 'M12 21a9 9 0 100-18 9 9 0 000 18zM12 16a4 4 0 100-8 4 4 0 000 8zM12 12h.01',
  vente: 'M4 12.5l5 5L20 6.5',
  porte_voix: 'M3 10v4h3l7 4V6L6 10zM16 9a4 4 0 010 6M19 6a8 8 0 010 12',
  rendement: 'M3 17l6-6 4 4 8-8M15 7h6v6',
};
export const icone = (nom) => { const s = svg('svg', { viewBox: '0 0 24 24', 'aria-hidden': 'true' }); s.append(svg('path', { d: ICONES[nom] || ICONES.moyenne })); return s; };

// Tuile de chiffre clé. delta : variation relative (0,12 = +12 %) ; points: true = écart en points de pourcentage
export function tuile(ic, libelle, valeur, delta, compare, { hausseBonne = true, points = false, note = null } = {}) {
  let d = null;
  if (delta !== null && delta !== undefined && Number.isFinite(delta)) {
    const bon = delta === 0 ? null : (delta > 0) === hausseBonne;
    const n = (delta * 100).toLocaleString('fr-CA', { maximumFractionDigits: 1 });
    d = h('p', { class: `bf-dash__delta${bon === true ? ' bf-dash__delta--bon' : bon === false ? ' bf-dash__delta--mauvais' : ''}` },
      `${delta > 0 ? '▲ +' : delta < 0 ? '▼ ' : ''}${n}${points ? ' pt' : ' %'}`, h('span', {}, ` ${compare}`));
  }
  return h('div', { class: 'bf-dash__tuile' }, h('span', { class: 'bf-dash__tuile-icone' }, icone(ic)),
    h('div', {}, h('p', { class: 'bf-dash__tuile-libelle' }, libelle), h('p', { class: 'bf-dash__tuile-valeur' }, valeur),
      note ? h('p', { class: 'bf-dash__delta' }, h('span', {}, note)) : null, d));
}

// séries : [{ cle, libelle, couleur }]
export const legende = (series, { ligne = false } = {}) => h('div', { class: 'bf-dash__legende' }, series.map((s) => h('span', {},
  h('span', { class: `bf-dash__cle${ligne ? ' bf-dash__cle--ligne' : ''}`, style: `background:${s.couleur}` }), s.libelle)));

export const tableDonnees = (entetes, rangees) => h('details', { class: 'bf-dash__donnees' }, h('summary', {}, 'Voir les données'),
  h('div', { class: 'bf-dash__defile' }, h('table', {},
    h('thead', {}, h('tr', {}, entetes.map((t, i) => h('th', { class: i ? 'num' : '' }, t)))),
    h('tbody', {}, rangees.map((r) => h('tr', {}, r.map((v, i) => h('td', { class: i ? 'num' : '' }, v))))))));

// Barres horizontales : [{ libelle, sous, valeur, texte, couleur, bulle }]
export function barres(lignes, { couleur = 'var(--d-s1)' } = {}) {
  const max = Math.max(1e-9, ...lignes.map((l) => l.valeur));
  return h('ol', { class: 'bf-dash__barres' }, lignes.map((l, i) => {
    const barre = h('span', { class: 'bf-dash__barre', style: `width:${Math.max(1.5, (Math.max(0, l.valeur) / max) * 100)}%;background:${l.couleur || couleur}` });
    const li = h('li', {}, h('span', { class: 'bf-dash__rang' }, String(i + 1)),
      h('span', { class: 'bf-dash__barre-libelle' }, h('span', {}, l.libelle), l.sous ? h('span', { class: 'bf-dash__muet' }, l.sous) : null),
      h('span', { class: 'bf-dash__barre-piste' }, barre), h('strong', { class: 'num' }, l.texte));
    survol(li, () => [[l.texte, l.libelle], ...(l.bulle || [])]);
    return li;
  }));
}

// Barres empilées : [{ libelle, sous, parts: { cle: n }, total, bulle }], séries dans l'ordre fixe ; format des nombres
export function barresEmpilees(lignes, series, { format = entier } = {}) {
  const max = Math.max(1, ...lignes.map((l) => l.total));
  return h('ol', { class: 'bf-dash__barres' }, lignes.map((l, i) => {
    const piste = h('span', { class: 'bf-dash__barre-piste bf-dash__barre-piste--empilee' },
      ...series.filter((s) => l.parts[s.cle]).map((s) => h('span', { class: 'bf-dash__seg-h', style: `width:${(l.parts[s.cle] / max) * 100}%;background:${s.couleur}` })));
    const li = h('li', {}, h('span', { class: 'bf-dash__rang' }, String(i + 1)),
      h('span', { class: 'bf-dash__barre-libelle' }, h('span', {}, l.libelle), l.sous ? h('span', { class: 'bf-dash__muet' }, l.sous) : null),
      piste, h('strong', { class: 'num' }, format(l.total)));
    survol(li, () => [[format(l.total), l.libelle], ...series.map((s) => [format(l.parts[s.cle] || 0), s.libelle, s.couleur]), ...(l.bulle || [])]);
    return li;
  }));
}

// Colonnes empilées par mois. valeurs[i] = { cle: n } ; enPlein(m) = mois de la période (les autres atténués)
export function colonnesEmpilees({ mois, series, valeurs, enPlein = () => true, unite = '', aria = '' }) {
  const totaux = valeurs.map((v) => series.reduce((s, x) => s + (v[x.cle] || 0), 0));
  const max = Math.max(1, ...totaux);
  const pas = [5, 10, 20, 50, 100, 200, 500, 1000].find((p) => max / p <= 6) || 2000;
  const haut = Math.ceil(max / pas) * pas;
  const W = etroit() ? 360 : 640; const H = etroit() ? 220 : 240; const g = 38; const b = 22; const largeur = W - g - 8; const hauteur = H - b - 10;
  const s = svg('svg', { viewBox: `0 0 ${W} ${H}`, class: 'bf-dash__svg', role: 'img', 'aria-label': aria });
  for (let v = 0; v <= haut; v += pas) {
    const y = 10 + hauteur - (v / haut) * hauteur;
    s.append(svg('line', { x1: g, x2: W - 8, y1: y, y2: y, class: v ? 'bf-dash__grille' : 'bf-dash__axe' }));
    const t = svg('text', { x: g - 6, y: y + 4, class: 'bf-dash__tick', 'text-anchor': 'end' }); t.textContent = entier(v); s.append(t);
  }
  const bande = largeur / mois.length; const bw = Math.min(24, bande * 0.6);
  mois.forEach((m, i) => {
    const x = g + i * bande + (bande - bw) / 2;
    const groupe = svg('g', { class: `bf-dash__col${enPlein(m) ? '' : ' bf-dash__col--hors'}` });
    let y = 10 + hauteur;
    const segs = series.filter((x2) => valeurs[i][x2.cle] > 0);
    segs.forEach((se, k) => {
      const hseg = (valeurs[i][se.cle] / haut) * hauteur;
      const dernier = k === segs.length - 1;
      const yh = y - hseg;
      // 2 px de fond entre les segments ; extrémité arrondie seulement en haut
      const hd = Math.max(0, hseg - (dernier ? 0 : 2));
      groupe.append(dernier
        ? svg('path', { d: `M${x},${yh + hd}V${yh + Math.min(4, hd)}q0,-4 4,-4h${bw - 8}q4,0 4,4V${yh + hd}z`, fill: se.couleur })
        : svg('rect', { x, y: yh, width: bw, height: hd, fill: se.couleur }));
      y -= hseg;
    });
    const zone = svg('rect', { x: g + i * bande, y: 10, width: bande, height: hauteur, fill: 'transparent', class: 'bf-dash__cible' });
    survol(zone, () => [[`${entier(totaux[i])}${unite ? ` ${unite}` : ''}`, nomMois(m)], ...series.map((se) => [entier(valeurs[i][se.cle] || 0), se.libelle, se.couleur])]);
    groupe.append(zone);
    const t = svg('text', { x: g + i * bande + bande / 2, y: H - 6, class: 'bf-dash__tick', 'text-anchor': 'middle' }); t.textContent = libelleMois(m);
    s.append(groupe, t);
  });
  return [legende(series), s, tableDonnees(['Mois', ...series.map((x) => x.libelle), 'Total'],
    mois.map((m, i) => [nomMois(m), ...series.map((se) => entier(valeurs[i][se.cle] || 0)), entier(totaux[i])]))];
}

// Anneau : parts [{ cle, libelle, couleur, n }], centre = texte du milieu
export function anneau(parts, { centre, unite = '', aria = '' }) {
  const vus = parts.filter((p) => p.n > 0);
  const total = vus.reduce((s, p) => s + p.n, 0) || 1;
  const s = svg('svg', { viewBox: '0 0 200 200', class: 'bf-dash__anneau', role: 'img', 'aria-label': aria });
  const R = 80; const r = 56; const C = 100;
  let a0 = -Math.PI / 2;
  const ecart = vus.length > 1 ? 0.025 : 0;
  for (const p of vus) {
    const a1 = a0 + (p.n / total) * Math.PI * 2;
    const d0 = a0 + ecart / 2; const d1 = Math.max(d0 + 0.001, a1 - ecart / 2);
    const grand = d1 - d0 > Math.PI ? 1 : 0;
    const pt = (rad, a) => `${C + rad * Math.cos(a)},${C + rad * Math.sin(a)}`;
    const chemin = vus.length === 1
      ? `M${C},${C - R}a${R},${R} 0 1,1 -0.01,0zM${C},${C - r}a${r},${r} 0 1,0 0.01,0z`
      : `M${pt(R, d0)}A${R},${R} 0 ${grand},1 ${pt(R, d1)}L${pt(r, d1)}A${r},${r} 0 ${grand},0 ${pt(r, d0)}z`;
    const seg = svg('path', { d: chemin, fill: p.couleur, class: 'bf-dash__seg', 'fill-rule': 'evenodd' });
    survol(seg, () => [[`${entier(p.n)}${unite ? ` ${unite}` : ''}`, `${p.libelle} (${pctTxt(p.n / total)})`, p.couleur]]);
    s.append(seg);
    a0 = a1;
  }
  const t1 = svg('text', { x: C, y: C - 2, class: 'bf-dash__anneau-total', 'text-anchor': 'middle' }); t1.textContent = centre ?? entier(total);
  const t2 = svg('text', { x: C, y: C + 20, class: 'bf-dash__tick', 'text-anchor': 'middle' }); t2.textContent = unite;
  s.append(t1, t2);
  const liste = h('ul', { class: 'bf-dash__parts' }, vus.map((p) => h('li', {},
    h('span', { class: 'bf-dash__cle', style: `background:${p.couleur}` }), h('span', {}, p.libelle),
    h('strong', {}, entier(p.n)), h('span', { class: 'bf-dash__muet' }, pctTxt(p.n / total)))));
  return h('div', { class: 'bf-dash__anneau-zone' }, s, liste);
}

// Lignes sur un seul axe : valeurs[cle][i] (null = pas de donnée). format(v) pour les axes et étiquettes.
// bulleTete(i) -> [valeur, libellé] en tête de l'infobulle ; bulleFin(i) -> lignes ajoutées à la fin.
export function lignes({ mois, series, valeurs, format, pasAxe, enPlein = () => true, bulleTete, bulleFin, aria = '' }) {
  const vals = series.flatMap((se) => valeurs[se.cle]).filter((x) => x !== null && x !== undefined);
  if (!vals.length) return [vide()];
  const bas = Math.floor((Math.min(...vals) - pasAxe * 0.4) / pasAxe) * pasAxe;
  const haut = Math.ceil((Math.max(...vals) + pasAxe * 0.4) / pasAxe) * pasAxe;
  const W = etroit() ? 360 : 900; const H = etroit() ? 220 : 240; const g = 46; const d = etroit() ? 50 : 76; const b = 22;
  const larg = W - g - d; const hau = H - b - 12;
  const X = (i) => g + (i / (mois.length - 1)) * larg;
  const Y = (v) => 12 + hau - ((v - bas) / (haut - bas || 1)) * hau;
  const s = svg('svg', { viewBox: `0 0 ${W} ${H}`, class: 'bf-dash__svg', role: 'img', 'aria-label': aria });
  const iP = mois.map((m, i) => (enPlein(m) ? i : -1)).filter((i) => i >= 0);
  if (iP.length && iP.length < mois.length) {
    const x0 = Math.max(g, X(iP[0]) - larg / 22); const x1 = Math.min(g + larg, X(iP[iP.length - 1]) + larg / 22);
    s.append(svg('rect', { x: x0, y: 12, width: x1 - x0, height: hau, class: 'bf-dash__bande' }));
  }
  for (let v = bas; v <= haut + 1e-9; v += pasAxe) {
    s.append(svg('line', { x1: g, x2: g + larg, y1: Y(v), y2: Y(v), class: v === bas ? 'bf-dash__axe' : 'bf-dash__grille' }));
    const t = svg('text', { x: g - 6, y: Y(v) + 4, class: 'bf-dash__tick', 'text-anchor': 'end' }); t.textContent = format(v); s.append(t);
  }
  mois.forEach((m, i) => { const t = svg('text', { x: X(i), y: H - 6, class: 'bf-dash__tick', 'text-anchor': 'middle' }); t.textContent = libelleMois(m); s.append(t); });
  const dernier = mois.length - 1;
  for (const se of [...series].reverse()) {
    const pts = valeurs[se.cle].map((v, i) => (v === null || v === undefined ? null : `${X(i)},${Y(v)}`)).filter(Boolean);
    s.append(svg('polyline', { points: pts.join(' '), fill: 'none', stroke: se.couleur, 'stroke-width': 2, 'stroke-linejoin': 'round', 'stroke-linecap': 'round' }));
    const v = valeurs[se.cle][dernier];
    if (v !== null && v !== undefined) {
      s.append(svg('circle', { cx: X(dernier), cy: Y(v), r: 4.5, fill: se.couleur, stroke: '#182036', 'stroke-width': 2 }));
      if (series.length <= 4) { const t = svg('text', { x: X(dernier) + 9, y: Y(v) + 4, class: 'bf-dash__etiquette-fin' }); t.textContent = format(v); s.append(t); }
    }
  }
  // Réticule : une ligne verticale suit le pointeur (ou les flèches) et s'accroche au mois le plus proche
  const reticule = svg('line', { y1: 12, y2: 12 + hau, class: 'bf-dash__reticule', visibility: 'hidden' });
  const points = series.map((se) => svg('circle', { r: 4.5, fill: se.couleur, stroke: '#182036', 'stroke-width': 2, visibility: 'hidden' }));
  const cible = svg('rect', { x: g, y: 12, width: larg, height: hau, fill: 'transparent', class: 'bf-dash__cible bf-dash__cible--ligne', tabindex: '0', 'aria-label': 'Survoler ou utiliser les flèches pour lire chaque mois' });
  let iFocus = dernier;
  const montrer = (i, ev) => {
    iFocus = i;
    reticule.setAttribute('x1', X(i)); reticule.setAttribute('x2', X(i)); reticule.setAttribute('visibility', 'visible');
    series.forEach((se, k) => {
      const v = valeurs[se.cle][i];
      points[k].setAttribute('visibility', v === null || v === undefined ? 'hidden' : 'visible');
      if (v !== null && v !== undefined) { points[k].setAttribute('cx', X(i)); points[k].setAttribute('cy', Y(v)); }
    });
    montrerBulle(ev, [bulleTete ? bulleTete(i) : [nomMois(mois[i]), ''],
      ...series.map((se) => [valeurs[se.cle][i] === null || valeurs[se.cle][i] === undefined ? 'n/d' : format(valeurs[se.cle][i]), se.libelle, se.couleur]),
      ...(bulleFin ? bulleFin(i) : [])]);
  };
  const cacher = () => { reticule.setAttribute('visibility', 'hidden'); points.forEach((c) => c.setAttribute('visibility', 'hidden')); cacherBulle(); };
  cible.addEventListener('pointermove', (e) => {
    const r = s.getBoundingClientRect(); const x = ((e.clientX - r.left) / r.width) * W;
    montrer(Math.max(0, Math.min(dernier, Math.round(((x - g) / larg) * dernier))), e);
  });
  cible.addEventListener('pointerleave', cacher);
  cible.addEventListener('blur', cacher);
  cible.addEventListener('focus', (e) => montrer(iFocus, e));
  cible.addEventListener('keydown', (e) => {
    if (e.key === 'ArrowLeft' || e.key === 'ArrowRight') { e.preventDefault(); montrer(Math.max(0, Math.min(dernier, iFocus + (e.key === 'ArrowRight' ? 1 : -1))), e); }
  });
  s.append(reticule, ...points, cible);
  return [legende(series, { ligne: true }), s, tableDonnees(['Mois', ...series.map((se) => se.libelle)],
    mois.map((m, i) => [nomMois(m), ...series.map((se) => (valeurs[se.cle][i] === null || valeurs[se.cle][i] === undefined ? '' : format(valeurs[se.cle][i])))]))];
}

// Couleur d'une cellule de matrice (échelle bleue) : { fond, claire } ou null si vide
export function celluleSeq(v, max) {
  if (!v) return null;
  const k = Math.min(SEQ.length - 1, Math.floor((v / max) * SEQ.length - 1e-4));
  return { fond: SEQ[Math.max(0, k)], claire: k >= 3 };
}

// Panneau sombre commun : titre, sous-titre, badge « Données fictives », bouton plein écran
export function panneauDash(titre, sousTitre, filtres, corps) {
  const p = h('div', { class: 'bf-dash' },
    h('div', { class: 'bf-dash__entete' },
      h('div', {}, h('h1', {}, titre), h('p', {}, sousTitre)),
      h('div', { class: 'bf-dash__entete-droite' }, h('span', { class: 'bf-dash__fictif' }, 'Données fictives'),
        h('button', { class: 'bf-dash__bouton', type: 'button', onclick: () => (document.fullscreenElement ? document.exitFullscreen() : p.requestFullscreen?.()) }, 'Plein écran'))),
    filtres, corps, bulle);
  return p;
}
