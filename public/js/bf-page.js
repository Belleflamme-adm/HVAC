// Gabarit commun des pages : session obligatoire, en-tête, bandeau, déconnexion.
import { exigerSession, logout } from './bf-session.js?v=0.3.0';
import { rendreBandeau } from './bf-bandeau.js?v=0.3.0';
import { h } from './bf-dom.js?v=0.3.0';

const LIENS = [['/', 'Accueil'], ['/clients', 'Clients'], ['/devis', 'Devis']];

export async function initPage() {
  const user = await exigerSession();
  if (!user) return null;
  const nav = h('nav', { class: 'bf-nav', 'aria-label': 'Navigation' },
    LIENS.map(([href, t]) => h('a', { href, 'aria-current': location.pathname === href ? 'page' : null }, t)));
  const sortie = h('button', { class: 'bf-bouton bf-bouton--discret', type: 'button', onclick: async () => { await logout(); location.replace('/login'); } }, 'Déconnexion');
  document.getElementById('entete').replaceChildren(
    h('a', { class: 'bf-entete__marque', href: '/' }, 'Belleflamme ', h('span', {}, 'Ventilation | Climatisation')), nav, sortie);
  rendreBandeau(document.getElementById('bandeau'), user);
  if ('serviceWorker' in navigator) navigator.serviceWorker.register('/sw.js').catch(() => {});
  return user;
}

export const estApprobateur = (user) => Boolean(user?.peutApprouverRabais);
