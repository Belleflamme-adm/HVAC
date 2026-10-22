#!/usr/bin/env node
// Municipalités de l'Est ontarien dans un rayon autour d'Ottawa (ADR-053).
// Source : « Municipal Boundary - Lower and Single Tier », ministère des Ressources naturelles de l'Ontario
// (Land Information Ontario), Licence du gouvernement ouvert de l'Ontario.
//
// Produit :
//   1. public/data/municipalites-on.geojson  (code, nom, mrc = comté, region, province)
//   2. supabase/migrations/<horodatage>_municipalites_ontario.sql
//
// Usage : node scripts/municipalites/ontario.mjs [--rayon-km 150] [--simplifier 4%]
import { execFileSync } from 'node:child_process';
import { mkdtempSync, readFileSync, writeFileSync, readdirSync, mkdirSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';

const MAPSHAPER = 'mapshaper@0.7.71';
const SERVICE = 'https://ws.lioservices.lrc.gov.on.ca/arcgis2/rest/services/LIO_OPEN_DATA/LIO_Open03/MapServer/14/query';
export const OTTAWA = [-75.6972, 45.4215]; // colline du Parlement
const CHAMPS = 'MUNID,MUNICIPAL_NAME_SHORTFORM,MUNICIPAL_NAME_SHORTFORM_FR,UPPER_TIER_MUNICIPALITY_FR';

// Distance en km (haversine)
export function distanceKm([lon1, lat1], [lon2, lat2]) {
  const r = Math.PI / 180;
  const a = Math.sin(((lat2 - lat1) * r) / 2) ** 2
    + Math.cos(lat1 * r) * Math.cos(lat2 * r) * Math.sin(((lon2 - lon1) * r) / 2) ** 2;
  return 6371 * 2 * Math.asin(Math.sqrt(a));
}

// Une municipalité est retenue si une partie de son territoire est dans le rayon
export function dansRayon(geometrie, centre, rayonKm) {
  const polys = geometrie.type === 'Polygon' ? [geometrie.coordinates] : geometrie.coordinates;
  return polys.some((p) => p[0].some((pt) => distanceKm(pt, centre) <= rayonKm));
}

// Les noms du service sont en MAJUSCULES : « CANTON D'ELIZABETHTOWN-KITLEY » -> « Canton d'Elizabethtown-Kitley »
const PETITS = new Set(['unis', 'de', 'du', 'des', 'la', 'le', 'les', 'et', 'and', 'of', 'the', 'sur', 'en']);
export function casse(texte) {
  if (!texte) return texte;
  return texte.toLowerCase().split(/(\s+|-|\/)/).map((m, i) => {
    if (!m.trim() || m === '-' || m === '/') return m;
    if (i > 0 && PETITS.has(m)) return m;
    const ap = m.match(/^([dl])'(.+)$/);
    if (ap) return `${i > 0 ? ap[1] : ap[1].toUpperCase()}'${ap[2][0].toUpperCase()}${ap[2].slice(1)}`;
    if (/^mc./.test(m)) return `Mc${m[2].toUpperCase()}${m.slice(3)}`;
    return m[0].toUpperCase() + m.slice(1);
  }).join('');
}

export function proprietesOntario(a) {
  const nom = casse(a.MUNICIPAL_NAME_SHORTFORM_FR || a.MUNICIPAL_NAME_SHORTFORM);
  const comte = casse(a.UPPER_TIER_MUNICIPALITY_FR);
  const p = { code: `ON-${String(a.MUNID).trim()}`, nom, region: 'Est de l\'Ontario', province: 'ON' };
  if (comte) p.mrc = comte;
  return p;
}

const sql = (v) => (v === null || v === undefined || v === '' ? 'null' : `'${String(v).replace(/'/g, "''")}'`);

export function genererSqlOntario(features, date = new Date()) {
  const lignes = features.map((f) => f.properties).sort((a, b) => a.code.localeCompare(b.code))
    .map((p) => `  (${sql(p.code)}, ${sql(p.nom)}, ${sql(p.mrc)}, ${sql(p.region)}, 'ON', ${sql(SOURCE)})`);
  return `-- GÉNÉRÉ par scripts/municipalites/ontario.mjs le ${date.toISOString().slice(0, 10)}. Ne pas modifier à la main.
-- Source : ${SOURCE}.
insert into public.municipalites (code, nom, mrc, region, province, source) values
${lignes.join(',\n')}
on conflict (code) do update set nom = excluded.nom, mrc = excluded.mrc, region = excluded.region,
  province = excluded.province, source = excluded.source, updated_at = now();
`;
}
const SOURCE = 'Municipal Boundary - Lower and Single Tier, MRNF Ontario (Licence du gouvernement ouvert de l\'Ontario)';

function arg(nom, defaut) {
  const i = process.argv.indexOf(`--${nom}`);
  return i > 0 ? process.argv[i + 1] : defaut;
}

async function principal() {
  const rayon = Number(arg('rayon-km', '150'));
  // Boîte englobante du cercle (un peu plus large), puis filtre exact au rayon
  const dLat = rayon / 111; const dLon = rayon / (111 * Math.cos((OTTAWA[1] * Math.PI) / 180));
  const boite = [OTTAWA[0] - dLon, OTTAWA[1] - dLat, OTTAWA[0] + dLon, OTTAWA[1] + dLat].map((x) => x.toFixed(4)).join(',');
  // curl plutôt que fetch : il respecte le proxy et le magasin de certificats du poste.
  // Le service tronque les grosses réponses GeoJSON : on demande d'abord les identifiants, puis par petits lots.
  const appel = (params) => {
    const args = ['-sS', '--fail', '--max-time', '300', '-G', SERVICE];
    for (const [k, v] of Object.entries(params)) args.push('--data-urlencode', `${k}=${v}`);
    return JSON.parse(execFileSync('curl', args, { maxBuffer: 1 << 30 }).toString('utf8'));
  };
  const zone = { geometry: boite, geometryType: 'esriGeometryEnvelope', inSR: '4326', spatialRel: 'esriSpatialRelIntersects' };
  const { objectIds = [] } = appel({ where: '1=1', ...zone, returnIdsOnly: 'true', f: 'json' });
  const toutes = [];
  for (let i = 0; i < objectIds.length; i += 10) {
    const page = appel({ objectIds: objectIds.slice(i, i + 10).join(','), outFields: CHAMPS, outSR: '4326',
      maxAllowableOffset: '0.0002', f: 'geojson' });
    if (!page.features) throw new Error(`Service ontarien : réponse inattendue ${JSON.stringify(page).slice(0, 200)}`);
    toutes.push(...page.features);
  }
  if (toutes.length !== objectIds.length) throw new Error(`Service ontarien : ${toutes.length} reçus sur ${objectIds.length}`);
  console.log(`Service ontarien : ${toutes.length} polygones dans la boîte`);

  const travail = mkdtempSync(join(tmpdir(), 'muni-on-'));
  const brut = join(travail, 'brut.json'); const sortie = join(travail, 'sortie.json');
  writeFileSync(brut, JSON.stringify({ type: 'FeatureCollection', features: toutes }));
  // Fusion par MUNID (une municipalité peut compter plusieurs polygones), puis simplification
  execFileSync('npx', ['--yes', MAPSHAPER, '-i', brut, 'snap', '-dissolve', 'MUNID', `copy-fields=${CHAMPS.replace('MUNID,', '')}`,
    '-simplify', arg('simplifier', '4%'), 'keep-shapes', '-o', 'format=geojson', 'precision=0.0001', sortie], { stdio: 'inherit' });
  const geo = JSON.parse(readFileSync(sortie, 'utf8'));
  const features = geo.features.filter((f) => f.geometry && dansRayon(f.geometry, OTTAWA, rayon))
    .map((f) => ({ type: 'Feature', geometry: f.geometry, properties: proprietesOntario(f.properties) }));

  mkdirSync('public/data', { recursive: true });
  writeFileSync('public/data/municipalites-on.geojson', JSON.stringify({
    type: 'FeatureCollection', attribution: SOURCE, features }));
  // On réécrit la migration existante si elle est là ; sinon, nouvelle migration après la dernière
  const fichiers = readdirSync('supabase/migrations');
  const existante = fichiers.find((f) => f.endsWith('_municipalites_ontario.sql'));
  const derniere = fichiers.map((f) => f.slice(0, 14)).filter((x) => /^\d{14}$/.test(x)).sort().at(-1) || '0';
  const fichier = `supabase/migrations/${existante || `${String(BigInt(derniere) + 1n).padStart(14, '0')}_municipalites_ontario.sql`}`;
  writeFileSync(fichier, genererSqlOntario(features));
  const taille = (readFileSync('public/data/municipalites-on.geojson').length / 1e6).toFixed(2);
  console.log(`OK : ${features.length} municipalités ontariennes à ${rayon} km d'Ottawa | ${taille} Mo | ${fichier}`);
}

if (import.meta.url === `file://${process.argv[1]}`) principal().catch((e) => { console.error(e.message); process.exit(1); });
