// Barre du bas (comme chez Mike) : recherche + cloche. Présente sur toutes les pages.
// Recherche : cherche dans les leads (nom, ville, téléphone). Cloche : leads en retard visibles par l'utilisateur.
// (La recherche globale de Mike, fonction global-search, couvrira tout à la greffe.)
import { api } from './bf-api.js?v=0.4.0';
import { h } from './bf-dom.js?v=0.4.0';

export function rendreBarre(user) {
  if (document.querySelector('.bf-barre')) return;
  const champ = h('input', { type: 'search', id: 'bf-recherche', placeholder: 'Rechercher un lead (nom, ville, téléphone)…', 'aria-label': 'Rechercher' });
  const form = h('form', { class: 'bf-barre__recherche', role: 'search' }, champ,
    h('button', { type: 'submit', class: 'bf-barre__loupe', 'aria-label': 'Chercher' }, '🔍'));
  form.addEventListener('submit', (e) => {
    e.preventDefault();
    const q = champ.value.trim();
    location.href = `/leads${q ? `?q=${encodeURIComponent(q)}` : ''}`;
  });
  const compte = h('span', { class: 'bf-barre__compte' }, '0');
  const cloche = h('a', { class: 'bf-barre__cloche', href: '/leads', title: 'Leads en retard', 'aria-label': 'Leads en retard' }, '🔔', compte);
  const barre = h('div', { class: 'bf-barre' }, form, user?.sousTraitantId ? null : cloche);
  document.body.append(barre);
  document.body.classList.add('bf-avec-barre');
  if (!user?.sousTraitantId) {
    api.get('leads', { vue: 'mes', statut: 'actifs', limite: 200 }).then((leads) => {
      const n = leads.filter((l) => l.en_retard).length;
      compte.textContent = String(n);
      cloche.classList.toggle('bf-barre__cloche--alerte', n > 0);
      cloche.title = n ? `${n} lead(s) en retard` : 'Aucun lead en retard';
    }).catch(() => {});
  }
}
