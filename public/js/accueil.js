// Accueil, au style de l'app de Mike : couverture, logo rond, titre condensé, ruban de stats,
// tuiles en liste (un groupe s'ouvre en fenêtre), barre du bas.
import { exigerSession, logout } from './bf-session.js?v=0.4.0';
import { rendreTuiles, accueilPour } from './bf-tuiles.js?v=0.4.0';
import { rendreBarre } from './bf-barre.js?v=0.4.0';
import { api } from './bf-api.js?v=0.4.0';
import { h } from './bf-dom.js?v=0.4.0';
import { SUCCURSALES } from './bf-project-code.js?v=0.4.0';

const user = await exigerSession();
if (user) {
  const jour = new Date().toLocaleDateString('fr-CA', { weekday: 'long', day: 'numeric', month: 'long', year: 'numeric' });
  document.getElementById('date').textContent = jour.charAt(0).toUpperCase() + jour.slice(1);
  document.getElementById('qui').textContent = `${user.name} · ${user.role} · ${SUCCURSALES[user.succursale] || user.succursale}`;
  rendreTuiles(document.getElementById('tuiles'), accueilPour(user));
  rendreBarre(user);
  document.getElementById('deconnexion').addEventListener('click', async () => { await logout(); location.replace('/login'); });

  // Ruban de stats (équivalent bandeau-stats chez Mike), calculé sur les leads visibles
  const ruban = document.getElementById('ruban');
  const item = (libelle, valeur, unite = '') => h('span', { class: 'bf-ruban__item' },
    libelle, ' ', h('span', { class: 'bf-ruban__chiffre' }, valeur), unite ? ` ${unite}` : '', h('span', { class: 'bf-ruban__sep', 'aria-hidden': 'true' }, '✦'));
  if (user.sousTraitantId) {
    ruban.hidden = true;
    // Partenariat (ADR-096) : depuis quand, compte créé, liste de prix active (version du registre, mise à jour à chaque changement)
    try {
      const p = await api.get('partenariat');
      const date = (d) => new Date(d.length === 10 ? `${d}T12:00:00` : d).toLocaleDateString('fr-CA', { day: 'numeric', month: 'long', year: 'numeric' });
      const zone = document.getElementById('partenariat');
      zone.replaceChildren(...[
        p.partenaire_depuis ? h('span', {}, 'Partenaire Belleflamme depuis le ', h('strong', {}, date(p.partenaire_depuis))) : null,
        p.compte_cree_le ? h('span', {}, 'Compte créé le ', h('strong', {}, date(p.compte_cree_le))) : null,
        h('a', { class: 'bf-partenariat__liste', href: '/mes-prix' }, p.version ? `Liste de prix active : V${p.version}` : 'Liste de prix : aucune version encore',
          p.version_le ? h('small', {}, `depuis le ${date(p.version_le)}`) : null),
      ].filter(Boolean));
      zone.hidden = false;
    } catch { /* sans partenariat */ }
  } else {
    try {
      const leads = await api.get('leads', { vue: ['Admin tout', 'Direction', 'Gérant de succursale', 'Coordonnateur'].includes(user.role) ? 'board' : 'mes', limite: 500 });
      const debut = new Date(); debut.setHours(0, 0, 0, 0);
      const aujourdhui = leads.filter((l) => new Date(l.recu_le) >= debut);
      const contactes = aujourdhui.filter((l) => l.premier_contact_le);
      const delais = contactes.map((l) => Number(l.minutes_premier_contact)).sort((a, b) => a - b);
      const mediane = delais.length ? Math.round(delais[Math.floor((delais.length - 1) / 2)]) : null;
      const items = [
        item('LEADS AUJOURD\'HUI :', String(aujourdhui.length)),
        item('EN ATTENTE :', String(leads.filter((l) => !l.premier_contact_le && !['perdu', 'converti'].includes(l.statut)).length)),
        item('EN RETARD :', String(leads.filter((l) => l.en_retard).length)),
        item('CONTACTÉS AUJOURD\'HUI :', String(contactes.length)),
        item('DÉLAI MÉDIAN DU 1er CONTACT :', mediane === null ? 'n/d' : `${mediane} min`),
        item('VISITES PLANIFIÉES :', String(leads.filter((l) => l.statut === 'inspection_planifiee').length)),
      ];
      // Le contenu est doublé pour un défilement continu
      ruban.replaceChildren(h('div', { class: 'bf-ruban__piste' }, items, items.map((n) => n.cloneNode(true))));
    } catch { ruban.hidden = true; }
  }
}

if ('serviceWorker' in navigator) navigator.serviceWorker.register('/sw.js').catch(() => {});
