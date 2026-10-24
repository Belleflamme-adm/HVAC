// Mes jobs (ADR-080) : dès que le client signe sa soumission, le projet tombe chez le sous-traitant attitré.
// Il voit les machines (quantités, prix à 0 $) et SES prix d'installation : ce qu'il va nous charger.
// Jamais le prix chargé au client, le total de la facture ni notre marge (la base ne les lui envoie pas).
// Loi 25 : le nom, le téléphone et l'adresse du client arrivent après le dépôt.
// Simon, Mike et la planification ouvrent la même page avec ?fournisseur= pour voir ce que voit le sous-traitant.
import { initPage } from './bf-page.js?v=0.4.0';
import { api } from './bf-api.js?v=0.4.0';
import { remplir, h, message, param } from './bf-dom.js?v=0.4.0';
import { formatCents } from './bf-money.js?v=0.4.0';
import { pastilleType } from './bf-crm.js?v=0.4.0';

const ETAPES = [
  ['attente_paiement', 'Nouveau | en attente du dépôt du client'], ['a_planifier', 'Dépôt reçu | à céduler'], ['planifie', 'Planifié'],
  ['en_cours', 'En cours'], ['termine', 'Terminé'], ['facture', 'Facturé'],
];
const LIBELLE = Object.fromEntries(ETAPES);
const jour = (d) => (d ? new Date(d).toLocaleDateString('fr-CA', { weekday: 'short', day: 'numeric', month: 'short', year: 'numeric' }) : '');
const qte = (n) => String(Number(n)).replace('.', ',');

const user = await initPage();
if (user) {
  const zone = document.getElementById('contenu');
  const msg = h('p', { class: 'bf-message', role: 'alert' });
  const estSt = Boolean(user.sousTraitantId);
  const liste = h('div', { class: 'bf-jobs' });

  function carte(j) {
    const machines = j.lignes.filter((l) => l.type_ligne === 'machine');
    const install = j.lignes.filter((l) => l.type_ligne === 'installation');
    const ligne = (l) => h('tr', { class: l.type_ligne === 'machine' ? 'bf-jobs__machine' : null },
      h('td', {}, l.description, l.type_ligne === 'machine' ? h('div', { class: 'bf-muet' }, 'Fournie par Belleflamme') : null),
      h('td', { class: 'num' }, qte(l.quantite)),
      h('td', { class: 'num' }, formatCents(l.prix_cents)),
      h('td', { class: 'num' }, h('strong', {}, formatCents(l.total_cents))));
    return h('article', { class: `bf-jobs__carte bf-jobs__carte--${j.statut}` },
      h('div', { class: 'bf-jobs__tete' },
        h('div', {}, h('h2', {}, j.code_projet || 'Code à venir'), h('p', { class: 'bf-muet' }, [j.ville, j.signe_le ? `signé le ${jour(j.signe_le)}` : null].filter(Boolean).join(' | '))),
        h('div', { class: 'bf-macro__ligne' }, j.type_systeme ? pastilleType(j.type_systeme) : null,
          h('span', { class: `bf-pastille bf-jobs__etape bf-jobs__etape--${j.statut}` }, LIBELLE[j.statut] || j.statut))),
      j.installation_prevue_le ? h('p', {}, h('strong', {}, 'Installation : '), jour(j.installation_prevue_le)) : null,
      j.client_nom
        ? h('p', { class: 'bf-jobs__client' }, h('strong', {}, j.client_nom),
          j.client_telephone ? [' | ', h('a', { href: `tel:${j.client_telephone}` }, j.client_telephone)] : null,
          j.adresse ? ` | ${j.adresse}` : null)
        : h('p', { class: 'bf-muet' }, 'Les coordonnées du client arrivent quand son dépôt est reçu (Loi 25). Tu peux déjà réserver la job dans tes disponibilités.'),
      h('div', { class: 'bf-table-zone' }, h('table', { class: 'bf-table bf-jobs__table' },
        h('thead', {}, h('tr', {}, ['Description', 'Qté', 'Ton prix', 'Total'].map((t, i) => h('th', { class: i ? 'num' : null }, t)))),
        h('tbody', {},
          machines.length ? h('tr', { class: 'bf-jobs__groupe' }, h('td', { colspan: 4 }, 'Machines')) : null, machines.map(ligne),
          install.length ? h('tr', { class: 'bf-jobs__groupe' }, h('td', { colspan: 4 }, 'Ton installation')) : null, install.map(ligne),
          !j.lignes.length ? h('tr', {}, h('td', { colspan: 4, class: 'bf-muet' }, 'Lignes à venir : Belleflamme les inscrit avec le projet.')) : null),
        h('tfoot', {}, h('tr', {}, h('th', { colspan: 3 }, 'Ce que tu factures à Belleflamme (avant taxes)'), h('th', { class: 'num' }, formatCents(j.total_cents)))))));
  }

  async function charger(fournisseur) {
    try {
      const q = (param('q') || '').toLowerCase();
      const jobs = (await api.get('jobs', { fournisseur: fournisseur || undefined }))
        .filter((j) => !q || [j.code_projet, j.ville, j.client_nom].some((v) => String(v || '').toLowerCase().includes(q)));
      const total = jobs.reduce((s, j) => s + (j.total_cents || 0), 0);
      remplir(liste,
        h('div', { class: 'bf-jobs__resume' },
          h('span', {}, h('strong', {}, String(jobs.length)), ` job${jobs.length > 1 ? 's' : ''}`),
          h('span', {}, h('strong', {}, String(jobs.filter((j) => j.statut === 'attente_paiement').length)), ' en attente du dépôt'),
          h('span', {}, h('strong', {}, formatCents(total)), ' à facturer à Belleflamme')),
        ...ETAPES.flatMap(([k, lib]) => {
          const l = jobs.filter((j) => j.statut === k);
          return l.length ? [h('h2', { class: 'bf-jobs__section' }, `${lib} (${l.length})`), ...l.map(carte)] : [];
        }),
        jobs.length ? null : h('p', { class: 'bf-muet' }, 'Aucune job pour l\'instant. Dès qu\'un client signe une soumission qui t\'est attitrée, elle apparaît ici.'));
    } catch (e) { message(msg, e.message); }
  }

  let choix = null;
  if (!estSt) {
    choix = h('select', { 'aria-label': 'Sous-traitant' }, h('option', { value: '' }, 'Choisir un sous-traitant…'));
    choix.addEventListener('change', () => (choix.value ? charger(choix.value) : remplir(liste)));
    api.get('sous-traitants').then((fs) => {
      fs.filter((f) => f.actif !== false && f.type !== 'fournisseur').forEach((f) => choix.append(h('option', { value: f.id, selected: f.id === param('fournisseur') }, f.nom)));
      if (choix.value) charger(choix.value);
    }).catch((e) => message(msg, e.message));
  }

  remplir(zone,
    h('div', { class: 'bf-titre' }, h('h1', {}, 'Mes jobs'),
      h('span', { class: 'bf-muet' }, estSt ? 'Les projets signés qui te sont attitrés, avec ton prix d\'installation. Les machines sont fournies par Belleflamme.'
        : 'Ce que voit le sous-traitant : machines à 0 $, son prix d\'installation seulement. Ni le prix client, ni la facture, ni la marge.')),
    choix ? h('div', { class: 'bf-filtres' }, choix) : null,
    msg, liste);
  if (estSt) charger();
}
