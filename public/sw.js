// Service worker : coquille hors ligne. Version alignée sur ?v= des scripts.
// Les réponses des fonctions (/.netlify/functions/*) ne sont JAMAIS mises en cache :
// elles contiennent des données personnelles et des jetons.
// La file de synchronisation hors ligne des BT (IndexedDB) arrive avec le module BT (ADR-011).
const VERSION = 'hvac-0.4.1';
const COQUILLE = [
  '/', '/login', '/css/bf.css?v=0.4.0', '/js/bf-theme-init.js?v=0.4.0', '/js/bf-session.js?v=0.4.0',
  '/js/bf-tuiles.js?v=0.4.0', '/js/bf-bandeau.js?v=0.4.0', '/js/accueil.js?v=0.4.0', '/js/login.js?v=0.4.0',
  '/clients', '/client', '/devis', '/devis-edition', '/devis-imprimer', '/css/bf-imprimer.css?v=0.4.0',
  '/js/bf-page.js?v=0.4.0', '/js/bf-api.js?v=0.4.0', '/js/bf-dom.js?v=0.4.0', '/js/bf-money.js?v=0.4.0',
  '/js/bf-project-code.js?v=0.4.0', '/js/bf-entreprise.js?v=0.4.0', '/js/page-clients.js?v=0.4.0',
  '/js/page-client.js?v=0.4.0', '/js/page-devis.js?v=0.4.0', '/js/page-devis-edition.js?v=0.4.0',
  '/js/page-devis-imprimer.js?v=0.4.0', '/territoire', '/disponibilites', '/sous-traitants',
  '/js/bf-carte.js?v=0.4.0', '/js/bf-calendrier.js?v=0.4.0', '/js/page-territoire.js?v=0.4.0',
  '/js/page-disponibilites.js?v=0.4.0', '/js/page-sous-traitants.js?v=0.4.0', '/installation-grille', '/js/page-installation-grille.js?v=0.4.0', '/manifest.webmanifest', '/icons/icon.svg',
  '/leads', '/lead', '/crm-rapidite', '/js/bf-crm.js?v=0.4.0', '/js/page-leads.js?v=0.4.0', '/js/page-lead.js?v=0.4.0',
  '/js/page-crm-rapidite.js?v=0.4.0', '/js/bf-fenetre.js?v=0.4.0', '/js/bf-barre.js?v=0.4.0',
];

self.addEventListener('install', (e) => {
  e.waitUntil(caches.open(VERSION).then((c) => c.addAll(COQUILLE)).then(() => self.skipWaiting()));
});

self.addEventListener('activate', (e) => {
  e.waitUntil(caches.keys()
    .then((cles) => Promise.all(cles.filter((k) => k.startsWith('hvac-') && k !== VERSION).map((k) => caches.delete(k))))
    .then(() => self.clients.claim()));
});

self.addEventListener('fetch', (e) => {
  const url = new URL(e.request.url);
  if (e.request.method !== 'GET' || url.origin !== location.origin) return;
  if (url.pathname.startsWith('/.netlify/')) return; // réseau seulement
  // Pages : réseau d'abord, cache en secours. Fichiers statiques versionnés : cache d'abord.
  if (e.request.mode === 'navigate') {
    e.respondWith(fetch(e.request).catch(() => caches.match(url.pathname).then((r) => r || caches.match('/'))));
    return;
  }
  e.respondWith(caches.match(e.request).then((r) => r || fetch(e.request)));
});
