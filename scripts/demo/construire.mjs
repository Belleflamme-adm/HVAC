#!/usr/bin/env node
// HTML de test (demande de Simon : après chaque modification visuelle ou fonctionnelle, un HTML pour tester).
// Emballe les VRAIES pages de l'app (public/) dans un seul fichier, avec un faux serveur en mémoire
// (scripts/demo/faux-serveur.js) : aucun réseau, aucune base, données fictives.
//
// Usage : npm run demo  ->  demo-build/hvac-test.html (ignoré par git, publié comme artifact)
import { build } from 'esbuild';
import { readFileSync, writeFileSync, mkdirSync, existsSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { TYPES_TRAVAUX, CATEGORIES } from '../reference/types-travaux.mjs';

const PAGES = ['index', 'leads', 'lead', 'crm-rapidite', 'clients', 'client', 'territoire', 'disponibilites', 'sous-traitants', 'sous-traitant', 'tableau-machines', 'tableau-marketing', 'installation-grille', 'demande-prix', 'prix', 'mes-prix'];
const lire = (f) => readFileSync(f, 'utf8');
const icone = `data:image/svg+xml;base64,${Buffer.from(lire('public/icons/icon.svg')).toString('base64')}`;

// Les imports de l'app portent ?v= (cache) : on les retire pour l'emballage
const sansVersion = {
  name: 'sans-version',
  setup(b) {
    b.onResolve({ filter: /\?v=/ }, (args) => ({ path: new URL(args.path.replace(/\?v=.*$/, ''), `file://${args.resolveDir}/`).pathname }));
  },
};

// Navigation : dans l'iframe de test, on passe par la coquille au lieu de changer d'adresse
function adapter(code) {
  return code
    .replace(/location\.href\s*=\s*([^;\n]+);/g, '__nav($1);')
    .replace(/location\.replace\(/g, '__nav(')
    .replace(/location\.pathname/g, '__demo.path')
    .replace(/location\.search/g, '__demo.search')
    .replace(/location\.hash/g, '__demo.hash')
    .replaceAll('/icons/icon.svg', icone);
}

const css = lire('public/css/bf.css');
const shim = `
window.__demo = parent.__demoCourant;
window.__nav = (u) => parent.__naviguer(String(u));
(() => {
  const S = parent.__demoServeur;
  const vraiFetch = window.fetch.bind(window);
  window.fetch = async (url, init = {}) => {
    const u = new URL(String(url), 'https://demo.local' + __demo.path);
    if (u.pathname.startsWith('/.netlify/functions/')) {
      const fn = u.pathname.split('/').pop();
      const r = S.appeler(fn, init.method || 'GET', Object.fromEntries(u.searchParams), init.body ? JSON.parse(init.body) : undefined, init.headers || {});
      return new Response(JSON.stringify(r.body), { status: r.status, headers: { 'Content-Type': 'application/json' } });
    }
    if (u.pathname.startsWith('/data/')) {
      const d = parent.__demoDonnees[u.pathname];
      return new Response(d || '', { status: d ? 200 : 404, headers: { 'Content-Type': 'application/json' } });
    }
    return vraiFetch(url, init);
  };
  try { if (navigator.serviceWorker) navigator.serviceWorker.register = () => Promise.resolve(); } catch (e) {}
  document.addEventListener('click', (e) => {
    const a = e.target.closest && e.target.closest('a[href]');
    if (!a) return;
    const h = a.getAttribute('href');
    if (h.startsWith('/')) { e.preventDefault(); __nav(h); }
  }, true);
})();`;

const pages = {};
for (const p of PAGES) {
  const html = lire(`public/${p}.html`);
  const titre = html.match(/<title>([^<]*)<\/title>/)?.[1] || p;
  const [, attrsBody, corps] = html.match(/<body([^>]*)>([\s\S]*)<\/body>/);
  const entree = html.match(/<script type="module" src="\/js\/([^"?]+)/)[1];
  const r = await build({ entryPoints: [`public/js/${entree}`], bundle: true, format: 'esm', target: 'es2022', write: false, plugins: [sansVersion], logLevel: 'silent' });
  const js = adapter(r.outputFiles[0].text);
  pages[p] = `<!doctype html><html lang="fr-CA"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>${titre}</title><style>${css}</style><script>${shim}</script></head>
<body${attrsBody}>${adapter(corps).replace(/<script[\s\S]*?<\/script>/g, '')}<script type="module">${js.replace(/<\/script/gi, '<\\/script')}</script></body></html>`;
}

const donnees = {};
for (const f of ['municipalites.geojson', 'municipalites-on.geojson', 'villes-reperes.json']) {
  if (existsSync(`public/data/${f}`)) donnees[`/data/${f}`] = lire(`public/data/${f}`);
}
const versJs = (o) => JSON.stringify(o).replace(/</g, '\\u003c');
let commit = 'local';
try { commit = execFileSync('git', ['log', '-1', '--format=%h']).toString().trim(); } catch { /* hors git */ }
const quand = new Date().toLocaleString('fr-CA', { dateStyle: 'medium', timeStyle: 'short', timeZone: 'America/Toronto' });

const coquille = lire('scripts/demo/coquille.html')
  .replace('/*__SERVEUR__*/', () => `window.__demoTypesTravaux = ${versJs(TYPES_TRAVAUX)};\nwindow.__demoCategories = ${versJs(CATEGORIES)};\n${lire('scripts/demo/faux-serveur.js')}`)
  .replace('/*__PAGES__*/', () => `window.__demoPages = ${versJs(pages)};`)
  .replace('/*__DONNEES__*/', () => `window.__demoDonnees = ${versJs(donnees)};`)
  .replace('__VERSION__', () => `${quand} | ${commit.replace(/[<>&]/g, '')}`);
mkdirSync('demo-build', { recursive: true });
writeFileSync('demo-build/hvac-test.html', coquille);
console.log(`OK : demo-build/hvac-test.html (${(coquille.length / 1e6).toFixed(2)} Mo, ${PAGES.length} pages)`);
