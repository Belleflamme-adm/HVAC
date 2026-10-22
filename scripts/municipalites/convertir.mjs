#!/usr/bin/env node
// Convertit la couche des municipalités du jeu officiel « Découpages administratifs » (MRNF,
// Données Québec, licence CC-BY 4.0) en :
//   1. public/data/municipalites.geojson  (simplifié pour le web : code, nom)
//   2. supabase/migrations/<horodatage>_municipalites_donnees.sql  (code, nom, MRC, région)
//
// Usage :
//   node scripts/municipalites/convertir.mjs <couche-municipalites.shp> [--simplifier 6%]
//        [--champ-code X] [--champ-nom X] [--champ-mrc X] [--champ-region X]
//
// Les noms de champs de la couche officielle sont détectés automatiquement ; s'ils ne le sont pas,
// le script s'arrête et affiche les champs disponibles (on ne devine pas).
import { execFileSync } from 'node:child_process';
import { mkdtempSync, readFileSync, writeFileSync, mkdirSync, readdirSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { tmpdir } from 'node:os';

const MAPSHAPER = 'mapshaper@0.7.71';

export function detecterChamps(proprietes, forces = {}) {
  const champs = Object.keys(proprietes);
  const trouver = (cle, motifs) => forces[cle] || champs.find((c) => motifs.some((m) => m.test(c)));
  const res = {
    code: trouver('code', [/co_?geo/i, /^code_?mun/i, /mus_co/i, /^code$/i]),
    nom: trouver('nom', [/nm_?mun/i, /^nom_?mun/i, /mus_nm_mun/i, /^nom$/i]),
    mrc: trouver('mrc', [/nm_?mrc/i, /nom_?mrc/i]),
    region: trouver('region', [/nm_?reg/i, /nom_?reg/i]),
  };
  const manquants = ['code', 'nom'].filter((k) => !res[k]);
  if (manquants.length) {
    throw new Error(`Champs introuvables (${manquants.join(', ')}). Champs disponibles : ${champs.join(', ')}. `
      + 'Préciser avec --champ-code et --champ-nom.');
  }
  return res;
}

// Propriétés gardées dans le GeoJSON de la carte
export function proprietesCarte(p, champs) {
  const texte = (c) => (c && p[c] !== null && p[c] !== undefined && String(p[c]).trim() !== '' ? String(p[c]).trim() : undefined);
  const res = { code: String(p[champs.code]).trim(), nom: String(p[champs.nom]).trim() };
  const mrc = texte(champs.mrc); const region = texte(champs.region);
  if (mrc) res.mrc = mrc;
  if (region) res.region = region;
  return res;
}

const sql = (v) => (v === null || v === undefined || v === '' ? 'null' : `'${String(v).replace(/'/g, "''")}'`);

export function genererSql(features, champs, date = new Date()) {
  const vus = new Map();
  for (const f of features) {
    const p = f.properties;
    const code = String(p[champs.code] ?? '').trim();
    if (!code || vus.has(code)) continue;
    vus.set(code, { code, nom: String(p[champs.nom] ?? '').trim(), mrc: champs.mrc ? p[champs.mrc] : null, region: champs.region ? p[champs.region] : null });
  }
  const lignes = [...vus.values()].sort((a, b) => a.code.localeCompare(b.code))
    .map((m) => `  (${sql(m.code)}, ${sql(m.nom)}, ${sql(m.mrc)}, ${sql(m.region)})`);
  return `-- GÉNÉRÉ par scripts/municipalites/convertir.mjs le ${date.toISOString().slice(0, 10)}. Ne pas modifier à la main.
-- Source : « Découpages administratifs », MRNF, Données Québec, licence CC-BY 4.0.
-- Ces limites n'ont pas de valeur légale (MRNF).
insert into public.municipalites (code, nom, mrc, region) values
${lignes.join(',\n')}
on conflict (code) do update set nom = excluded.nom, mrc = excluded.mrc, region = excluded.region, updated_at = now();
`;
}

function arg(nom, defaut) {
  const i = process.argv.indexOf(`--${nom}`);
  return i > 0 ? process.argv[i + 1] : defaut;
}

async function principal() {
  const entree = process.argv[2];
  if (!entree || entree.startsWith('--')) {
    console.error('Usage : node scripts/municipalites/convertir.mjs <couche.shp> [--simplifier 6%]');
    process.exit(2);
  }
  const travail = mkdtempSync(join(tmpdir(), 'muni-'));
  const brut = join(travail, 'brut.json');
  // 1. Lecture + reprojection WGS84 + simplification (formes conservées)
  execFileSync('npx', ['--yes', MAPSHAPER, '-i', resolve(entree), 'encoding=utf8', '-proj', 'wgs84',
    '-simplify', arg('simplifier', '6%'), 'keep-shapes', '-o', 'format=geojson', 'precision=0.0001', brut], { stdio: 'inherit' });
  const geo = JSON.parse(readFileSync(brut, 'utf8'));
  const champs = detecterChamps(geo.features[0]?.properties || {}, {
    code: arg('champ-code'), nom: arg('champ-nom'), mrc: arg('champ-mrc'), region: arg('champ-region'),
  });
  console.log('Champs utilisés :', champs);

  // 2. GeoJSON allégé pour la carte : code, nom, MRC et région (étiquettes et frontières de région)
  const leger = {
    type: 'FeatureCollection',
    attribution: 'Découpages administratifs, MRNF, Données Québec (CC-BY 4.0)',
    features: geo.features.filter((f) => f.geometry).map((f) => ({
      type: 'Feature', geometry: f.geometry,
      properties: proprietesCarte(f.properties, champs),
    })),
  };
  mkdirSync('public/data', { recursive: true });
  writeFileSync('public/data/municipalites.geojson', JSON.stringify(leger));

  // 3. Migration SQL des municipalités
  // Toujours APRÈS la dernière migration (la table municipalites doit déjà exister).
  const derniere = readdirSync('supabase/migrations').map((f) => f.slice(0, 14)).filter((x) => /^\d{14}$/.test(x)).sort().at(-1) || '0';
  const horodatage = String(BigInt(derniere) + 1n).padStart(14, '0');
  const fichier = `supabase/migrations/${horodatage}_municipalites_donnees.sql`;
  writeFileSync(fichier, genererSql(geo.features, champs));
  const taille = (readFileSync('public/data/municipalites.geojson').length / 1e6).toFixed(2);
  console.log(`OK : ${leger.features.length} municipalités | public/data/municipalites.geojson (${taille} Mo) | ${fichier}`);
}

if (import.meta.url === `file://${process.argv[1]}`) principal().catch((e) => { console.error(e.message); process.exit(1); });
