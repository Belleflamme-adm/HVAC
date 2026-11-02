// Automatisations (ADR-090) : le moteur de règles. Chaque règle = un déclencheur et des étapes (attendre, texto, courriel,
// tâche, avis). Simon et Mike activent, désactivent et modifient les messages et les délais, sans code. Suivi : en cours,
// terminées, arrêtées, ÉCHECS (relance), journal et messages envoyés. Envois simulés d'ici la greffe.
import { initPage } from './bf-page.js?v=0.4.0';
import { api } from './bf-api.js?v=0.4.0';
import { remplir, h, message } from './bf-dom.js?v=0.4.0';

const ADMIN = ['Admin tout', 'Direction'];
const LECTURE = [...ADMIN, 'Coordonnateur'];
const DECLENCHEURS = {
  lead_recu: 'Un lead arrive', appel_manque: 'Un appel est manqué', visite_planifiee: 'Une visite est planifiée (Pointage)',
  projet_etape: 'Un projet change d\'étape', subvention_etape: 'La subvention LogisVert avance', entretien_annuel: '30 jours avant l\'anniversaire de l\'installation',
};
const CONDITIONS = { lead_non_contacte: 'le lead n\'est pas encore contacté', aucun_appel_sortant: 'personne n\'a rappelé le client',
  aucun_avis_12_mois: 'aucun avis demandé à ce client depuis 12 mois', lead_ouvert: 'le lead est encore ouvert',
  subvention_non_deposee: 'la demande LogisVert n\'est pas encore déposée' };
const A = { vendeur: 'le vendeur', directeur: 'le directeur de la succursale', planification: 'la planification' };
const ARRETS = { client_repond: 'le client répond', lead_contacte: 'le vendeur contacte le client', lead_ferme: 'le lead est vendu ou perdu',
  visite_changee: 'la visite est déplacée ou annulée', visite_planifiee: 'une visite est planifiée', projet_annule: 'le projet est annulé' };
const JOURS = ['Dimanche', 'Lundi', 'Mardi', 'Mercredi', 'Jeudi', 'Vendredi', 'Samedi'];
const VARIABLES = '{prenom} {succursale} {vendeur} {type} {date_visite} {heure_visite} {lien_avis} {code_projet} {subvention} {telephone} {lien_guide_logisvert} {date_limite_logisvert} {numero_logisvert}';
// Ordre du parcours client (lead, appel manqué, visite, subvention, avis, entretien)
const ORDRE = ['lead_eclair', 'lead_escalade', 'lead_sequence', 'appel_manque', 'rappel_visite', 'logisvert_client', 'subvention_suivi', 'avis_google', 'entretien_annuel'];
const rang = (r) => { const i = ORDRE.indexOf(r.code); return i < 0 ? 99 : i; };
const quand = (d) => (d ? new Date(d).toLocaleString('fr-CA', { day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' }) : '');

function resumeEtape(e) {
  switch (e.type) {
    case 'attendre': return e.jours ? `Attendre ${e.jours} jour${e.jours > 1 ? 's' : ''} (envoi pendant les heures d'ouverture)`
      : `Attendre ${e.minutes} min${e.ouvrables ? ' ouvrables' : ''}`;
    case 'attendre_avant_visite': return `Attendre jusqu'à ${e.heures} h avant la visite`;
    case 'si': return `Continuer seulement si ${CONDITIONS[e.condition] || e.condition}`;
    case 'sms': return `Texto : « ${e.texte} »`;
    case 'courriel': return `Courriel « ${e.sujet || ''} »`;
    case 'tache': return `Tâche pour ${A[e.a] || e.a} : « ${e.titre} »`;
    case 'notifier': return `Avis à ${A[e.a] || e.a} : « ${e.titre} »`;
    case 'noter_avis': return 'Noter la demande d\'avis (pas d\'autre demande avant 12 mois)';
    default: return e.type;
  }
}

const user = await initPage();
if (user) {
  const zone = document.getElementById('contenu');
  const msg = h('p', { class: 'bf-message', role: 'alert' });
  const peutModifier = ADMIN.includes(user.role);
  let d = null;

  async function patch(corps, ok) {
    try { await api.patch('automatisations', corps); message(msg, ok, 'ok'); await charger(); return true; }
    catch (e) { message(msg, e.message); return false; }
  }

  // Éditeur d'une règle : textes, sujets, délais, destinataires. La structure (types et conditions) reste celle de la règle.
  function editeur(r, zoneEd) {
    const lignes = r.etapes.map((e, i) => {
      const champ = (nom, attrs = {}) => h('input', { 'data-i': i, 'data-champ': nom, ...attrs });
      let controles = [];
      if (e.type === 'attendre') {
        controles = e.jours
          ? [h('label', {}, 'Jours', champ('jours', { type: 'number', min: 1, max: 365, value: e.jours }))]
          : [h('label', {}, 'Minutes', champ('minutes', { type: 'number', min: 1, max: 100000, value: e.minutes })),
            h('label', { class: 'bf-case' }, champ('ouvrables', { type: 'checkbox', checked: Boolean(e.ouvrables) }), 'ouvrables')];
      } else if (e.type === 'attendre_avant_visite') {
        controles = [h('label', {}, 'Heures avant la visite', champ('heures', { type: 'number', min: 1, max: 168, value: e.heures }))];
      } else if (e.type === 'sms') {
        const compteur = h('span', { class: 'bf-muet' });
        const zoneTexte = h('textarea', { 'data-i': i, 'data-champ': 'texte', rows: 3, maxlength: 320 }, e.texte);
        const maj = () => { compteur.textContent = `${zoneTexte.value.length} / 320${r.commercial ? ' (+ mention STOP ajoutée)' : ''}`; };
        zoneTexte.addEventListener('input', maj); maj();
        controles = [h('label', { class: 'bf-pleine' }, 'Texto', zoneTexte, compteur)];
      } else if (e.type === 'courriel') {
        controles = [h('label', { class: 'bf-pleine' }, 'Sujet', champ('sujet', { value: e.sujet || '' })),
          h('label', { class: 'bf-pleine' }, 'Courriel', h('textarea', { 'data-i': i, 'data-champ': 'texte', rows: 5 }, e.texte))];
      } else if (['tache', 'notifier'].includes(e.type)) {
        controles = [h('label', {}, 'Pour', h('select', { 'data-i': i, 'data-champ': 'a' }, Object.entries(A).map(([k, t]) => h('option', { value: k, selected: k === e.a }, t)))),
          h('label', { class: 'bf-pleine' }, 'Titre', champ('titre', { value: e.titre || '' })),
          h('label', { class: 'bf-pleine' }, 'Détail', champ('texte', { value: e.texte || '' }))];
      }
      return h('li', { class: 'bf-regle__etape' }, h('strong', {}, `${i + 1}. ${resumeEtape(e).split(' : ')[0].split(' « ')[0]}`),
        controles.length ? h('div', { class: 'bf-grille2' }, ...controles) : h('span', { class: 'bf-muet' }, resumeEtape(e)));
    });
    const form = h('form', { class: 'bf-form bf-form--compact bf-regle__editeur' },
      h('p', { class: 'bf-muet' }, `Variables permises : ${VARIABLES}`),
      h('ol', { class: 'bf-regle__etapes' }, ...lignes),
      h('div', { class: 'bf-actions' }, h('button', { class: 'bf-bouton', type: 'submit' }, 'Enregistrer'),
        h('button', { class: 'bf-bouton bf-bouton--discret', type: 'button', onclick: () => zoneEd.replaceChildren() }, 'Annuler')));
    form.addEventListener('submit', async (ev) => {
      ev.preventDefault();
      const etapes = r.etapes.map((e) => ({ ...e }));
      form.querySelectorAll('[data-champ]').forEach((el) => {
        const e = etapes[Number(el.dataset.i)]; const k = el.dataset.champ;
        e[k] = el.type === 'checkbox' ? el.checked : el.type === 'number' ? Number(el.value) : el.value;
      });
      if (await patch({ action: 'regle', id: r.id, etapes }, `« ${r.nom} » enregistrée.`)) zoneEd.replaceChildren();
    });
    zoneEd.replaceChildren(form);
  }

  function carteRegle(r) {
    const zoneEd = h('div');
    const inter = h('input', { type: 'checkbox', checked: r.actif, disabled: !peutModifier, 'aria-label': `Activer « ${r.nom} »` });
    inter.addEventListener('change', () => patch({ action: 'regle', id: r.id, actif: inter.checked }, `« ${r.nom} » ${inter.checked ? 'activée' : 'désactivée'}.`));
    return h('article', { class: `bf-regle${r.actif ? '' : ' bf-regle--inactive'}${Number(r.echecs) ? ' bf-regle--echec' : ''}` },
      h('div', { class: 'bf-regle__tete' },
        h('div', {}, h('h2', {}, r.nom), h('p', { class: 'bf-muet' }, `Quand : ${DECLENCHEURS[r.declencheur] || r.declencheur}`)),
        h('label', { class: 'bf-interrupteur' }, inter, h('span', {}, r.actif ? 'Active' : 'Inactive'))),
      r.description ? h('p', {}, r.description) : null,
      h('div', { class: 'bf-macro__ligne' },
        r.commercial ? h('span', { class: 'bf-pastille bf-extra--hors', title: 'Message commercial : consentement exigé, mention STOP ajoutée' }, 'LCAP : consentement exigé') : h('span', { class: 'bf-pastille' }, 'Transactionnel'),
        h('span', { class: 'bf-pastille' }, `${r.en_cours} en cours`), h('span', { class: 'bf-pastille bf-extra--approuve' }, `${r.terminees_30j} terminées (30 j)`),
        h('span', { class: 'bf-pastille' }, `${r.arretees_30j} arrêtées (30 j)`),
        Number(r.echecs) ? h('span', { class: 'bf-pastille bf-extra--refuse' }, `${r.echecs} en échec`) : null),
      h('ol', { class: 'bf-regle__resume' }, ...r.etapes.map((e) => h('li', {}, resumeEtape(e)))),
      r.arret?.length ? h('p', { class: 'bf-muet' }, `S'arrête si ${r.arret.map((a) => ARRETS[a] || a).join(', ')}.`) : null,
      peutModifier ? h('div', { class: 'bf-actions' }, h('button', { type: 'button', class: 'bf-bouton bf-bouton--discret', onclick: () => editeur(r, zoneEd) }, 'Modifier les messages et les délais')) : null,
      zoneEd);
  }

  function reglages() {
    const parSucc = (code) => d.heures.filter((x) => x.succursale_code === code);
    return h('section', { class: 'bf-carte-section' }, h('h2', {}, 'Heures ouvrables et liens d\'avis Google'),
      h('p', { class: 'bf-muet' }, 'Les délais « ouvrables » (escalade de 15 minutes) et les envois des séquences suivent ces heures. Le lien d\'avis Google est envoyé à TOUS les clients, sans filtre (règle de Google).'),
      ...d.succursales.map((s) => {
        const lignes = JOURS.map((nom, jour) => {
          const x = parSucc(s.code).find((y) => y.jour === jour);
          return h('tr', {}, h('td', {}, nom),
            h('td', {}, h('input', { type: 'checkbox', 'data-jour': jour, 'data-champ': 'ouvert', checked: Boolean(x), disabled: !peutModifier, 'aria-label': `${nom} ouvert` })),
            h('td', {}, h('input', { type: 'time', 'data-jour': jour, 'data-champ': 'ouvre', value: x ? x.ouvre.slice(0, 5) : '09:00', disabled: !peutModifier, 'aria-label': `${nom} ouverture` })),
            h('td', {}, h('input', { type: 'time', 'data-jour': jour, 'data-champ': 'ferme', value: x ? x.ferme.slice(0, 5) : '17:00', disabled: !peutModifier, 'aria-label': `${nom} fermeture` })));
        });
        const table = h('table', { class: 'bf-table bf-heures' }, h('thead', {}, h('tr', {}, ['Jour', 'Ouvert', 'Ouvre', 'Ferme'].map((t) => h('th', {}, t)))), h('tbody', {}, ...lignes));
        const lien = h('input', { type: 'url', value: s.lien_avis_google || '', placeholder: 'https://g.page/r/.../review', disabled: !peutModifier, 'aria-label': `Lien d'avis Google ${s.nom}` });
        return h('details', { class: 'bf-heures__succ' }, h('summary', {}, h('strong', {}, s.nom), s.lien_avis_google ? '' : h('span', { class: 'bf-jobs__raison' }, ' | lien d\'avis manquant')),
          h('div', { class: 'bf-table-zone' }, table),
          peutModifier ? h('button', { type: 'button', class: 'bf-bouton bf-bouton--discret', onclick: () => {
            const heures = JOURS.map((_, jour) => {
              const q = (c) => table.querySelector(`[data-jour="${jour}"][data-champ="${c}"]`);
              return q('ouvert').checked ? { jour, ouvre: q('ouvre').value, ferme: q('ferme').value } : null;
            }).filter(Boolean);
            patch({ action: 'heures', succursale_code: s.code, heures }, `Heures de ${s.nom} enregistrées.`);
          } }, 'Enregistrer les heures') : null,
          h('label', {}, 'Lien d\'avis Google de la succursale', lien),
          peutModifier ? h('button', { type: 'button', class: 'bf-bouton bf-bouton--discret', onclick: () => patch({ action: 'lien_avis', succursale_code: s.code, lien: lien.value }, `Lien d'avis de ${s.nom} enregistré.`) }, 'Enregistrer le lien') : null);
      }));
  }

  async function charger() {
    try { d = await api.get('automatisations'); } catch (e) { message(msg, e.message); return; }
    const nomRegle = Object.fromEntries(d.regles.map((r) => [r.id, r.nom]));
    const echecs = d.echecs.length;
    remplir(zone,
      h('div', { class: 'bf-titre' }, h('h1', {}, 'Automatisations'),
        h('span', { class: 'bf-muet' }, 'Chaque règle : un déclencheur, puis des étapes. Une seule tâche les exécute chaque minute, et chaque exécution est journalisée.')),
      h('p', { class: 'bf-avertissement' }, '🧪 Envois SIMULÉS d\'ici la greffe : les textos et courriels s\'inscrivent dans l\'historique du client avec la mention « simulé », sans partir. À la greffe, ils passeront par l\'app de Mike.'),
      msg,
      h('div', { class: 'bf-jobs__resume' },
        h('span', {}, h('strong', {}, String(d.regles.filter((r) => r.actif).length)), ` règle(s) active(s) sur ${d.regles.length}`),
        h('span', {}, h('strong', {}, String(d.regles.reduce((s, r) => s + Number(r.en_cours), 0))), ' en cours'),
        h('span', { class: echecs ? 'bf-jobs__raison' : '' }, h('strong', {}, String(echecs)), ' en échec'),
        h('span', {}, h('strong', {}, String(d.messages.length)), ' message(s) automatique(s) récents')),
      echecs ? h('section', { class: 'bf-carte-section bf-regle--echec' }, h('h2', {}, `⚠ Échecs (${echecs})`),
        h('p', { class: 'bf-muet' }, 'Une exécution en échec ne réessaie pas toute seule : corrige la règle au besoin, puis relance.'),
        h('ul', { class: 'bf-simple' }, d.echecs.map((x) => h('li', {}, h('strong', {}, nomRegle[x.regle_id] || 'Règle'), ` | étape ${x.etape + 1} | ${quand(x.updated_at)}`,
          h('div', { class: 'bf-jobs__raison' }, x.derniere_erreur || ''),
          x.lead_id ? h('a', { href: `/lead?id=${x.lead_id}` }, 'Voir le lead') : null,
          peutModifier ? h('button', { type: 'button', class: 'bf-lien', onclick: () => patch({ action: 'relancer', id: x.id }, 'Exécution relancée.') }, 'Relancer') : null)))) : null,
      ...d.regles.slice().sort((a, b) => rang(a) - rang(b)).map(carteRegle),
      h('details', { class: 'bf-carte-section' }, h('summary', {}, h('strong', {}, `Messages automatiques récents (${d.messages.length})`)),
        d.messages.length ? h('ul', { class: 'bf-simple' }, d.messages.map((m) => h('li', {},
          h('strong', {}, m.canal === 'texto' ? 'Texto' : 'Courriel'), ` à ${m.coordonnee_client} | ${quand(m.debut)} | ${m.statut === 'simule' ? 'simulé' : m.statut}`,
          m.lead_id ? [' | ', h('a', { href: `/lead?id=${m.lead_id}` }, 'lead')] : null,
          h('div', { class: 'bf-muet' }, m.sujet ? `${m.sujet} : ${m.contenu.slice(0, 160)}` : m.contenu)))) : h('p', { class: 'bf-muet' }, 'Aucun message pour l\'instant.')),
      h('details', { class: 'bf-carte-section' }, h('summary', {}, h('strong', {}, 'Journal des exécutions (60 dernières étapes)')),
        h('div', { class: 'bf-table-zone' }, h('table', { class: 'bf-table' },
          h('thead', {}, h('tr', {}, ['Quand', 'Étape', 'Résultat', 'Détail'].map((t) => h('th', {}, t)))),
          h('tbody', {}, d.journal.map((j) => h('tr', { class: j.resultat === 'echec' ? 'bf-jobs__refuse' : null },
            h('td', {}, quand(j.le)), h('td', {}, `${j.etape + 1}. ${j.action}`), h('td', {}, j.resultat), h('td', {}, j.detail || ''))))))),
      reglages());
  }

  if (!LECTURE.includes(user.role)) remplir(zone, h('h1', {}, 'Automatisations'), h('p', { class: 'bf-message' }, 'Réservé à Simon, Mike et la planification.'));
  else charger();
}
