// Service worker : coquille hors ligne. Version alignée sur ?v= des scripts.
// Les réponses des fonctions (/.netlify/functions/*) ne sont JAMAIS mises en cache :
// elles contiennent des données personnelles et des jetons.
// La file de synchronisation hors ligne des BT (IndexedDB) arrive avec le module BT (ADR-011).
const VERSION = 'hvac-0.2.0';
const COQUILLE = [
  '/', '/login', '/css/bf.css?v=0.2.0', '/js/bf-theme-init.js?v=0.2.0', '/js/bf-session.js?v=0.2.0',
  '/js/bf-tuiles.js?v=0.2.0', '/js/bf-bandeau.js?v=0.2.0', '/js/accueil.js?v=0.2.0', '/js/login.js?v=0.2.0',
  '/manifest.webmanifest', '/icons/icon.svg',
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
