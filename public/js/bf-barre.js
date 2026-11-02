// Barre du bas (comme chez Mike) : recherche + cloche. Présente sur toutes les pages.
// Recherche : cherche dans les leads (nom, ville, téléphone) ; chez le sous-traitant, dans ses jobs (ADR-080).
// Cloche (ADR-090) : avis non lus + tâches ouvertes + leads en retard ; elle ouvre la page « Avis et tâches ». Cloche : leads en retard visibles par l'utilisateur.
// (La recherche globale de Mike, fonction global-search, couvrira tout à la greffe.)
import { api } from './bf-api.js?v=0.4.0';
import { h } from './bf-dom.js?v=0.4.0';

export function rendreBarre(user) {
  if (document.querySelector('.bf-barre')) return;
  const st = Boolean(user?.sousTraitantId);
  const champ = h('input', { type: 'search', id: 'bf-recherche', 'aria-label': 'Rechercher',
    placeholder: st ? 'Rechercher une job (code projet, ville)…' : 'Rechercher un lead (nom, ville, téléphone)…' });
  const form = h('form', { class: 'bf-barre__recherche', role: 'search' }, champ,
    h('button', { type: 'submit', class: 'bf-barre__loupe', 'aria-label': 'Chercher' }, '🔍'));
  form.addEventListener('submit', (e) => {
    e.preventDefault();
    const q = champ.value.trim();
    location.href = `${st ? '/jobs' : '/leads'}${q ? `?q=${encodeURIComponent(q)}` : ''}`;
  });
  const compte = h('span', { class: 'bf-barre__compte' }, '0');
  const cloche = h('a', { class: 'bf-barre__cloche', href: '/avis', title: 'Avis et tâches', 'aria-label': 'Avis et tâches' }, '🔔', compte);
  const barre = h('div', { class: 'bf-barre' }, form, cloche);
  document.body.append(barre);
  document.body.classList.add('bf-avec-barre');
  const compter = async () => {
    const [avis, leads] = await Promise.all([
      api.get('avis').catch(() => ({ notifications: [], taches: [] })),
      st ? Promise.resolve([]) : api.get('leads', { vue: 'mes', statut: 'actifs', limite: 200 }).catch(() => []),
    ]);
    const nonLus = avis.notifications.filter((n) => !n.lu_le).length;
    const retards = leads.filter((l) => l.en_retard).length;
    const n = nonLus + avis.taches.length + retards;
    compte.textContent = String(n);
    cloche.classList.toggle('bf-barre__cloche--alerte', n > 0);
    cloche.title = n ? [nonLus && `${nonLus} avis`, avis.taches.length && `${avis.taches.length} tâche(s)`, retards && `${retards} lead(s) en retard`].filter(Boolean).join(', ') : 'Rien en attente';
  };
  compter();
  document.addEventListener('bf:avis', compter);
}
