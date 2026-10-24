// Gabarit commun des pages : session obligatoire, en-tête, bandeau, déconnexion.
import { exigerSession, logout } from './bf-session.js?v=0.4.0';
import { rendreBandeau } from './bf-bandeau.js?v=0.4.0';
import { h } from './bf-dom.js?v=0.4.0';
import { rendreBarre } from './bf-barre.js?v=0.4.0';

// Menu selon le rôle : un sous-traitant ne voit que ses jobs, son territoire, ses prix et ses disponibilités.
export function liensPour(user) {
  if (user?.sousTraitantId) return [['/', 'Accueil'], ['/jobs', 'Mes jobs'], ['/territoire', 'Mon territoire'], ['/mes-prix', 'Ma liste de prix'], ['/disponibilites', 'Mes disponibilités']];
  // Devis : en veille (app de Mike, ADR-055), retiré du menu ; la tuile grisée reste à l'accueil
  const liens = [['/', 'Accueil'], ['/leads', 'Leads'], ['/clients', 'Clients']];
  if (['Admin tout', 'Direction', 'Coordonnateur'].includes(user?.role)) liens.push(['/sous-traitants', 'Sous-traitants']);
  return liens;
}

export async function initPage() {
  const user = await exigerSession();
  if (!user) return null;
  const nav = h('nav', { class: 'bf-nav', 'aria-label': 'Navigation' },
    liensPour(user).map(([href, t]) => h('a', { href, 'aria-current': location.pathname === href ? 'page' : null }, t)));
  const sortie = h('button', { class: 'bf-entete__sortie', type: 'button', onclick: async () => { await logout(); location.replace('/login'); } }, 'Déconnexion');
  document.getElementById('entete').replaceChildren(
    h('a', { class: 'bf-entete__marque', href: '/' }, h('img', { src: '/icons/icon.svg', alt: '', width: 30, height: 30 }),
      h('span', {}, 'Ventilation | Climatisation')), nav, sortie);
  rendreBandeau(document.getElementById('bandeau'), user);
  rendreBarre(user);
  if ('serviceWorker' in navigator) navigator.serviceWorker.register('/sw.js').catch(() => {});
  return user;
}

export const estApprobateur = (user) => Boolean(user?.peutApprouverRabais);
