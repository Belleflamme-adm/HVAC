// Carte des municipalités en SVG (aucune tuile externe, aucune librairie : rien ne sort vers un tiers).
// Données : public/data/municipalites.geojson, généré par scripts/municipalites/convertir.mjs
// (« Découpages administratifs », MRNF, CC-BY 4.0). Propriétés : code, nom, mrc, region.
// Repères : public/data/villes-reperes.json (grandes villes toujours nommées, tenu à la main).

const NS = 'http://www.w3.org/2000/svg';
const ECHELLE = 100;          // degrés -> unités SVG
const LAT0 = 48;              // latitude de référence (centre du Québec habité)
const COS0 = Math.cos((LAT0 * Math.PI) / 180);

// Projection équirectangulaire corrigée : suffisante pour cliquer des municipalités.
export const projeter = ([lon, lat]) => [lon * COS0 * ECHELLE, -lat * ECHELLE];

function anneaux(geometrie) {
  if (!geometrie) return [];
  if (geometrie.type === 'Polygon') return geometrie.coordinates;
  if (geometrie.type === 'MultiPolygon') return geometrie.coordinates.flat();
  return [];
}

// Anneaux extérieurs seulement (sans les trous)
function exterieurs(geometrie) {
  if (!geometrie) return [];
  if (geometrie.type === 'Polygon') return [geometrie.coordinates[0]];
  if (geometrie.type === 'MultiPolygon') return geometrie.coordinates.map((p) => p[0]);
  return [];
}

export function cheminSvg(geometrie) {
  return anneaux(geometrie).map((anneau) => anneau.map((pt, i) => {
    const [x, y] = projeter(pt);
    return `${i ? 'L' : 'M'}${x.toFixed(2)} ${y.toFixed(2)}`;
  }).join('') + 'Z').join('');
}

export function boite(features) {
  let [x0, y0, x1, y1] = [Infinity, Infinity, -Infinity, -Infinity];
  for (const f of features) for (const anneau of anneaux(f.geometry)) for (const pt of anneau) {
    const [x, y] = projeter(pt);
    if (x < x0) x0 = x; if (y < y0) y0 = y; if (x > x1) x1 = x; if (y > y1) y1 = y;
  }
  return { x: x0, y: y0, l: x1 - x0, h: y1 - y0 };
}

// Centre de gravité de la plus grande partie (coordonnées SVG) et aire totale.
export function centroide(geometrie) {
  let meilleur = null; let total = 0;
  for (const anneau of exterieurs(geometrie)) {
    let a = 0; let cx = 0; let cy = 0;
    const pts = anneau.map(projeter);
    for (let i = 0; i < pts.length - 1; i++) {
      const [x0, y0] = pts[i]; const [x1, y1] = pts[i + 1];
      const c = x0 * y1 - x1 * y0;
      a += c; cx += (x0 + x1) * c; cy += (y0 + y1) * c;
    }
    a /= 2;
    if (!a) continue;
    total += Math.abs(a);
    if (!meilleur || Math.abs(a) > Math.abs(meilleur.a)) meilleur = { a, x: cx / (6 * a), y: cy / (6 * a) };
  }
  return meilleur ? { x: meilleur.x, y: meilleur.y, aire: total } : null;
}

// Regroupe les municipalités par MRC ou par région : centre pondéré par l'aire et boîte.
export function regrouper(features, cle) {
  const groupes = new Map();
  for (const f of features) {
    const nom = f.properties[cle];
    const c = centroide(f.geometry);
    if (!nom || !c) continue;
    const g = groupes.get(nom) || { nom, x: 0, y: 0, aire: 0, membres: [] };
    g.x += c.x * c.aire; g.y += c.y * c.aire; g.aire += c.aire; g.membres.push(f);
    groupes.set(nom, g);
  }
  return [...groupes.values()].map((g) => ({ nom: g.nom, x: g.x / g.aire, y: g.y / g.aire, boite: boite(g.membres) }));
}

// Tracé des frontières entre groupes (ex. régions) : les arêtes partagées par deux municipalités
// de groupes différents, plus le contour extérieur. Les limites officielles partagent leurs sommets.
export function frontieres(features, cle) {
  const aretes = new Map();
  const k = (p) => `${p[0].toFixed(4)},${p[1].toFixed(4)}`;
  for (const f of features) {
    const groupe = f.properties[cle] ?? '';
    for (const anneau of anneaux(f.geometry)) {
      for (let i = 0; i < anneau.length - 1; i++) {
        const a = k(anneau[i]); const b = k(anneau[i + 1]);
        if (a === b) continue;
        const id = a < b ? `${a}|${b}` : `${b}|${a}`;
        const e = aretes.get(id);
        if (e) e.groupes.push(groupe); else aretes.set(id, { p: [anneau[i], anneau[i + 1]], groupes: [groupe] });
      }
    }
  }
  let d = '';
  for (const { p, groupes } of aretes.values()) {
    if (groupes.length > 1 && groupes.every((g) => g === groupes[0])) continue;
    const [x0, y0] = projeter(p[0]); const [x1, y1] = projeter(p[1]);
    d += `M${x0.toFixed(2)} ${y0.toFixed(2)}L${x1.toFixed(2)} ${y1.toFixed(2)}`;
  }
  return d;
}

// Choix des étiquettes visibles, sans chevauchement, par ordre de priorité.
// candidats : { texte, x, y, taille (px), priorite (petit = d'abord), facteur? (largeur d'un caractère / taille), boite?, classe }
// visible : rectangle SVG affiché ; k : unités SVG par pixel.
export function choisirEtiquettes(candidats, visible, k) {
  const places = [];
  const retenues = [];
  const tries = [...candidats].sort((a, b) => a.priorite - b.priorite);
  for (const c of tries) {
    const l = c.texte.length * c.taille * (c.facteur ?? 0.56) * k; // largeur approximative du texte
    const h = c.taille * 1.3 * k;
    // Jamais d'étiquette coupée par le bord de la carte
    if (c.x - l / 2 < visible.x || c.x + l / 2 > visible.x + visible.l
      || c.y - h / 2 < visible.y || c.y + h / 2 > visible.y + visible.h) continue;
    // Une municipalité n'est nommée que si son nom tient dans sa forme à l'écran
    if (c.boite && c.boite.l < l * (c.ajustement ?? 1)) continue;
    const r = { x0: c.x - l / 2, x1: c.x + l / 2, y0: c.y - h / 2, y1: c.y + h / 2 };
    if (places.some((p) => r.x0 < p.x1 && r.x1 > p.x0 && r.y0 < p.y1 && r.y1 > p.y0)) continue;
    places.push(r);
    retenues.push(c);
  }
  return retenues;
}

export async function chargerMunicipalites(url = '/data/municipalites.geojson?v=0.4.0') {
  const r = await fetch(url);
  if (!r.ok) return null;
  return r.json();
}

export async function chargerReperes(url = '/data/villes-reperes.json?v=0.4.0') {
  try { const r = await fetch(url); return r.ok ? r.json() : {}; } catch { return {}; }
}

// creerCarte(conteneur, geojson, { couleur(code), titre(feature), onClic(feature, evenement), reperes, vueDepart })
// reperes : { "Nom officiel": 1 | 2 } (1 = toujours nommée, 2 = nommée en priorité)
export function creerCarte(conteneur, geojson, options) {
  const features = geojson.features;
  const reperes = options.reperes || {};
  const parCode = new Map(features.map((f) => [f.properties.code, f]));
  const svg = document.createElementNS(NS, 'svg');
  svg.setAttribute('class', 'bf-geo');
  svg.setAttribute('role', 'img');
  svg.setAttribute('aria-label', 'Carte des municipalités du Québec');
  const groupe = document.createElementNS(NS, 'g');
  const traitRegions = document.createElementNS(NS, 'path');
  traitRegions.setAttribute('class', 'bf-geo__region');
  traitRegions.setAttribute('vector-effect', 'non-scaling-stroke');
  traitRegions.setAttribute('d', frontieres(features, 'region'));
  const groupeEtiquettes = document.createElementNS(NS, 'g');
  groupeEtiquettes.setAttribute('class', 'bf-geo__etiquettes');
  groupeEtiquettes.setAttribute('aria-hidden', 'true');
  svg.append(groupe, traitRegions, groupeEtiquettes);

  const chemins = new Map();
  for (const f of features) {
    const p = document.createElementNS(NS, 'path');
    p.setAttribute('d', cheminSvg(f.geometry));
    p.setAttribute('data-code', f.properties.code);
    p.setAttribute('vector-effect', 'non-scaling-stroke');
    const t = document.createElementNS(NS, 'title');
    t.textContent = options.titre ? options.titre(f) : f.properties.nom;
    p.append(t);
    groupe.append(p);
    chemins.set(f.properties.code, p);
  }
  conteneur.replaceChildren(svg);

  // Candidats d'étiquettes, calculés une seule fois
  const munis = features.map((f) => {
    const c = centroide(f.geometry);
    if (!c) return null;
    const rang = reperes[f.properties.nom];
    return { texte: f.properties.nom, x: c.x, y: c.y, rang, boite: boite([f]) };
  }).filter(Boolean);
  const regions = regrouper(features, 'region');
  const mrcs = regrouper(features, 'mrc');

  const total = boite(features);
  // Vue de départ : un cadre en degrés { ouest, sud, est, nord } (ex. le sud du Québec), sinon tout
  const vueInitiale = () => {
    const c = options.vueDepart;
    if (!c) return { ...total };
    const [x0, y0] = projeter([c.ouest, c.nord]); const [x1, y1] = projeter([c.est, c.sud]);
    return { x: x0, y: y0, l: x1 - x0, h: y1 - y0 };
  };
  let vue = vueInitiale();

  function visibleEtK() {
    const r = svg.getBoundingClientRect();
    if (!r.width || !r.height) return null;
    const k = Math.max(vue.l / r.width, vue.h / r.height);
    const l = r.width * k; const h = r.height * k;
    return { k, r, visible: { x: vue.x + (vue.l - l) / 2, y: vue.y + (vue.h - h) / 2, l, h } };
  }

  function majEtiquettes() {
    const v = visibleEtK();
    if (!v) return;
    const { k, visible } = v;
    const largeurEcran = (b) => b.l / k;
    const candidats = [];
    for (const m of munis) {
      if (m.rang === 1) candidats.push({ ...m, taille: 13, priorite: 1, classe: 'ville1', boite: null, facteur: 0.6 });
      else if (m.rang === 2) candidats.push({ ...m, taille: 12, priorite: 3, classe: 'ville2', boite: null });
      else candidats.push({ ...m, taille: 11, priorite: 5 + 1 / (1 + largeurEcran(m.boite)), classe: 'ville3', ajustement: 1.05 });
    }
    // Région : nommée quand on la voit en entier ou presque ; MRC : à un zoom intermédiaire
    for (const g of regions) {
      const lp = largeurEcran(g.boite);
      if (lp > 90 && lp < visible.l / k * 2.5) candidats.push({ texte: g.nom.toUpperCase(), x: g.x, y: g.y, taille: 14, priorite: 2, classe: 'region', facteur: 0.82 });
    }
    for (const g of mrcs) {
      const lp = largeurEcran(g.boite);
      if (lp > 140 && lp < visible.l / k * 1.8) candidats.push({ texte: g.nom.toUpperCase(), x: g.x, y: g.y, taille: 10.5, priorite: 4, classe: 'mrc', facteur: 0.72 });
    }
    const retenues = choisirEtiquettes(candidats, visible, k);
    const textes = retenues.map((c) => {
      const t = document.createElementNS(NS, 'text');
      t.setAttribute('x', c.x.toFixed(2));
      t.setAttribute('y', c.y.toFixed(2));
      t.setAttribute('font-size', (c.taille * k).toFixed(4));
      t.setAttribute('stroke-width', (3 * k).toFixed(4));
      t.setAttribute('class', `bf-geo__etiquette bf-geo__etiquette--${c.classe}`);
      t.textContent = c.texte;
      return t;
    });
    groupeEtiquettes.replaceChildren(...textes);
  }

  let attente = 0;
  const appliquer = () => {
    svg.setAttribute('viewBox', `${vue.x} ${vue.y} ${vue.l} ${vue.h}`);
    if (!attente) attente = requestAnimationFrame(() => { attente = 0; majEtiquettes(); });
  };
  appliquer();
  if (typeof ResizeObserver !== 'undefined') new ResizeObserver(() => appliquer()).observe(svg);

  // Coordonnées écran -> SVG
  const versSvg = (cx, cy) => {
    const r = svg.getBoundingClientRect();
    const k = Math.max(vue.l / r.width, vue.h / r.height);
    const ox = vue.x + (vue.l - r.width * k) / 2;
    const oy = vue.y + (vue.h - r.height * k) / 2;
    return [ox + (cx - r.left) * k, oy + (cy - r.top) * k, k];
  };
  const zoomer = (facteur, cx, cy) => {
    const [sx, sy] = versSvg(cx, cy);
    const l = Math.min(Math.max(vue.l * facteur, total.l / 400), total.l * 1.5);
    const f = l / vue.l;
    vue = { x: sx - (sx - vue.x) * f, y: sy - (sy - vue.y) * f, l, h: vue.h * f };
    appliquer();
  };

  svg.addEventListener('wheel', (e) => { e.preventDefault(); zoomer(e.deltaY > 0 ? 1.25 : 0.8, e.clientX, e.clientY); }, { passive: false });

  // Glisser (souris, doigt) et pincer (deux doigts)
  const pointeurs = new Map();
  let depart = null; let deplace = false; let ecart0 = 0;
  svg.addEventListener('pointerdown', (e) => {
    pointeurs.set(e.pointerId, [e.clientX, e.clientY]);
    svg.setPointerCapture(e.pointerId);
    depart = { x: e.clientX, y: e.clientY, vue: { ...vue } }; deplace = false;
    if (pointeurs.size === 2) { const [a, b] = [...pointeurs.values()]; ecart0 = Math.hypot(a[0] - b[0], a[1] - b[1]); }
  });
  svg.addEventListener('pointermove', (e) => {
    if (!pointeurs.has(e.pointerId)) return;
    pointeurs.set(e.pointerId, [e.clientX, e.clientY]);
    if (pointeurs.size === 2) {
      const [a, b] = [...pointeurs.values()];
      const ecart = Math.hypot(a[0] - b[0], a[1] - b[1]);
      if (ecart0) zoomer(ecart0 / ecart, (a[0] + b[0]) / 2, (a[1] + b[1]) / 2);
      ecart0 = ecart; deplace = true; return;
    }
    const dx = e.clientX - depart.x; const dy = e.clientY - depart.y;
    if (Math.hypot(dx, dy) > 4) deplace = true;
    if (!deplace) return;
    const [, , k] = versSvg(e.clientX, e.clientY);
    vue = { ...depart.vue, x: depart.vue.x - dx * k, y: depart.vue.y - dy * k };
    appliquer();
  });
  const fin = (e) => {
    pointeurs.delete(e.pointerId);
    if (pointeurs.size < 2) ecart0 = 0;
    if (e.type === 'pointerup' && !deplace && pointeurs.size === 0) {
      // Avec la capture du pointeur, e.target est le svg : on retrouve le chemin sous le doigt.
      const cible = document.elementFromPoint(e.clientX, e.clientY);
      const code = cible?.getAttribute?.('data-code');
      if (code && options.onClic) options.onClic(parCode.get(code), e);
    }
  };
  svg.addEventListener('pointerup', fin);
  svg.addEventListener('pointercancel', fin);

  function redessiner(selection = new Set()) {
    for (const [code, p] of chemins) {
      p.setAttribute('fill', options.couleur(code));
      p.setAttribute('class', selection.has(code) ? 'selection' : '');
      if (selection.has(code)) groupe.append(p); // contour au premier plan
    }
  }

  // Cadre la vue sur un ensemble de municipalités (ex. le territoire déjà choisi), avec une marge
  function cadrer(codes) {
    const fs = [...codes].map((c) => parCode.get(c)).filter(Boolean);
    if (!fs.length) return false;
    const b = boite(fs);
    const marge = Math.max(b.l, b.h) * 0.15 + total.l / 300;
    vue = { x: b.x - marge, y: b.y - marge, l: b.l + 2 * marge, h: b.h + 2 * marge };
    appliquer();
    return true;
  }

  function zoomSur(code) {
    const f = parCode.get(code);
    if (!f) return;
    const b = boite([f]);
    const marge = Math.max(b.l, b.h) * 2 + total.l / 200;
    vue = { x: b.x - marge, y: b.y - marge, l: b.l + 2 * marge, h: b.h + 2 * marge };
    appliquer();
  }

  return { redessiner, zoomSur, cadrer, toutVoir: () => { vue = { ...total }; appliquer(); }, vueDepart: () => { vue = vueInitiale(); appliquer(); }, parCode };
}
