// Carte des municipalités en SVG (aucune tuile externe, aucune librairie : rien ne sort vers un tiers).
// Données : public/data/municipalites.geojson, généré par scripts/municipalites/convertir.mjs
// (« Découpages administratifs », MRNF, CC-BY 4.0).

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

export async function chargerMunicipalites(url = '/data/municipalites.geojson?v=0.4.0') {
  const r = await fetch(url);
  if (!r.ok) return null;
  return r.json();
}

// creerCarte(conteneur, geojson, { couleur(code), titre(feature), onClic(feature, evenement) })
export function creerCarte(conteneur, geojson, options) {
  const features = geojson.features;
  const parCode = new Map(features.map((f) => [f.properties.code, f]));
  const svg = document.createElementNS(NS, 'svg');
  svg.setAttribute('class', 'bf-carte');
  svg.setAttribute('role', 'img');
  svg.setAttribute('aria-label', 'Carte des municipalités du Québec');
  const groupe = document.createElementNS(NS, 'g');
  svg.append(groupe);

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

  const total = boite(features);
  let vue = { ...total };
  const appliquer = () => svg.setAttribute('viewBox', `${vue.x} ${vue.y} ${vue.l} ${vue.h}`);
  appliquer();

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
      const code = e.target?.getAttribute?.('data-code');
      if (code && options.onClic) options.onClic(parCode.get(code), e);
    }
  };
  svg.addEventListener('pointerup', fin);
  svg.addEventListener('pointercancel', fin);

  function redessiner(selection = new Set()) {
    for (const [code, p] of chemins) {
      p.setAttribute('fill', options.couleur(code));
      p.setAttribute('class', selection.has(code) ? 'selection' : '');
    }
  }

  function zoomSur(code) {
    const f = parCode.get(code);
    if (!f) return;
    const b = boite([f]);
    const marge = Math.max(b.l, b.h) * 2 + total.l / 200;
    vue = { x: b.x - marge, y: b.y - marge, l: b.l + 2 * marge, h: b.h + 2 * marge };
    appliquer();
  }

  return { redessiner, zoomSur, toutVoir: () => { vue = { ...total }; appliquer(); }, parCode };
}
