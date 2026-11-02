// Avis et tâches (ADR-090) : ce que la cloche annonce. Les tâches créées par les automatisations (rappeler un client,
// lead sans contact, entretien à planifier), les avis (dépôt reçu, extras à approuver, facture finale, échecs), et,
// pour les vendeurs et le board, les leads en retard.
import { initPage } from './bf-page.js?v=0.4.0';
import { api } from './bf-api.js?v=0.4.0';
import { remplir, h, message } from './bf-dom.js?v=0.4.0';

const quand = (d) => (d ? new Date(d).toLocaleString('fr-CA', { weekday: 'short', day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' }) : '');
const enRetard = (t) => t.echeance && new Date(t.echeance) < new Date();

const user = await initPage();
if (user) {
  const zone = document.getElementById('contenu');
  const msg = h('p', { class: 'bf-message', role: 'alert' });
  const st = Boolean(user.sousTraitantId);

  async function geste(corps, ok) {
    try { await api.patch('avis', corps); if (ok) message(msg, ok, 'ok'); await charger(); document.dispatchEvent(new CustomEvent('bf:avis')); }
    catch (e) { message(msg, e.message); }
  }

  async function charger() {
    let d; let retards = [];
    try { d = await api.get('avis'); } catch (e) { message(msg, e.message); return; }
    if (!st) { try { retards = (await api.get('leads', { vue: 'mes', statut: 'actifs', limite: 200 })).filter((l) => l.en_retard); } catch { /* sans leads */ } }
    const nonLus = d.notifications.filter((n) => !n.lu_le);
    remplir(zone,
      h('div', { class: 'bf-titre' }, h('h1', {}, 'Avis et tâches'),
        h('span', { class: 'bf-muet' }, st ? 'Les nouvelles de tes jobs : dépôt reçu, extras approuvés ou refusés.' : 'Tes tâches à faire, tes avis, et tes leads en retard.')),
      msg,
      st ? null : h('section', { class: 'bf-carte-section' }, h('h2', {}, `Mes tâches (${d.taches.length})`),
        d.taches.length ? h('ul', { class: 'bf-avis' }, d.taches.map((t) => h('li', { class: `bf-avis__item${enRetard(t) ? ' bf-avis__item--retard' : ''}` },
          h('div', {}, h('strong', {}, t.titre), t.details ? h('div', { class: 'bf-muet' }, t.details) : null,
            h('div', { class: enRetard(t) ? 'bf-jobs__raison' : 'bf-muet' }, t.echeance ? `${enRetard(t) ? 'En retard : ' : 'À faire avant '}${quand(t.echeance)}` : ''),
            t.lead_id ? h('a', { href: `/lead?id=${t.lead_id}` }, 'Ouvrir le lead') : t.projet_id ? h('a', { href: '/macro' }, 'Voir le Macro') : null),
          h('button', { type: 'button', class: 'bf-bouton bf-bouton--discret', onclick: () => geste({ action: 'tache_faite', id: t.id }, 'Tâche faite.') }, '✓ Faite'))))
          : h('p', { class: 'bf-muet' }, 'Aucune tâche. 👍')),
      !st && retards.length ? h('section', { class: 'bf-carte-section' }, h('h2', {}, `Leads en retard (${retards.length})`),
        h('ul', { class: 'bf-simple' }, retards.map((l) => h('li', {}, h('a', { href: `/lead?id=${l.id}` }, l.contact_nom || 'Lead'), ` | ${l.ville || ''} | reçu ${quand(l.recu_le)}`)))) : null,
      h('section', { class: 'bf-carte-section' }, h('h2', {}, `Avis${nonLus.length ? ` (${nonLus.length} non lu${nonLus.length > 1 ? 's' : ''})` : ''}`),
        d.notifications.length ? h('ul', { class: 'bf-avis' }, d.notifications.map((n) => h('li', { class: `bf-avis__item${n.lu_le ? ' bf-avis__item--lu' : ''}${n.type === 'regle_echec' ? ' bf-avis__item--retard' : ''}` },
          h('div', {}, h('strong', {}, n.titre), n.message ? h('div', {}, n.message) : null, h('div', { class: 'bf-muet' }, quand(n.created_at)),
            n.lien ? h('a', { href: n.lien, onclick: () => { if (!n.lu_le) api.patch('avis', { action: 'lu', id: n.id }).catch(() => {}); } }, 'Ouvrir') : null),
          n.lu_le ? null : h('button', { type: 'button', class: 'bf-lien', onclick: () => geste({ action: 'lu', id: n.id }) }, 'Marquer lu'))))
          : h('p', { class: 'bf-muet' }, 'Aucun avis.')));
  }
  charger();
}
