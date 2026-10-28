// Macro HVAC (ADR-079) : chaque projet signé par le client tombe ici, à l'étape « Signé, attente du dépôt ».
// Colonnes par étape ; on fait avancer un projet (ou reculer d'une étape) avec les flèches de sa carte.
// À la greffe : ces projets vivent dans le Macro de l'app de Mike (même code projet, mêmes étapes).
import { initPage } from './bf-page.js?v=0.4.0';
import { api } from './bf-api.js?v=0.4.0';
import { remplir, h, message } from './bf-dom.js?v=0.4.0';
import { formatCents } from './bf-money.js?v=0.4.0';
import { pastilleType } from './bf-crm.js?v=0.4.0';

const ETAPES = [
  ['attente_paiement', 'Signé, attente du dépôt'], ['a_planifier', 'À céduler'], ['planifie', 'Planifié'],
  ['en_cours', 'En cours'], ['termine', 'Terminé'], ['facture', 'Facturé'],
];
const LIBELLE = Object.fromEntries([...ETAPES, ['ferme', 'Fermé'], ['annule', 'Annulé']]);
const SUCCURSALES = { HO: 'Saint-Jérôme', RO: 'Rosemère', ST: 'Saint-Sauveur', GA: 'Gatineau', DR: 'Drummondville' };
const PLANIF = ['Admin tout', 'Direction', 'Coordonnateur', 'Gérant de succursale'];
// Subvention LogisVert (ADR-090) : chaque étape envoie un texto au client (règle « Suivi de subvention »)
const SUBVENTION = { a_deposer: 'À déposer', deposee: 'Déposée', acceptee: 'Acceptée', versee: 'Versée', refusee: 'Refusée' };
const jour = (d) => (d ? new Date(d).toLocaleDateString('fr-CA', { day: 'numeric', month: 'short', year: 'numeric' }) : '');
const recent = (d) => d && Date.now() - new Date(d).getTime() < 48 * 3600e3;

const user = await initPage();
if (user) {
  const zone = document.getElementById('contenu');
  const msg = h('p', { class: 'bf-message', role: 'alert' });
  const peutBouger = PLANIF.includes(user.role);
  const filtres = { succursale: '', recherche: '', fermes: false };
  let projets = [];

  const choixSucc = h('select', { 'aria-label': 'Succursale' }, h('option', { value: '' }, 'Toutes les succursales'),
    Object.entries(SUCCURSALES).map(([k, n]) => h('option', { value: k }, n)));
  choixSucc.addEventListener('change', () => { filtres.succursale = choixSucc.value; charger(); });
  const recherche = h('input', { type: 'search', placeholder: 'Chercher un projet (code, client, ville, vendeur, n° de soumission)…', 'aria-label': 'Chercher un projet' });
  recherche.addEventListener('input', () => { filtres.recherche = recherche.value.trim().toLowerCase(); afficher(); });
  const caseFermes = h('input', { type: 'checkbox' });
  caseFermes.addEventListener('change', () => { filtres.fermes = caseFermes.checked; charger(); });
  const tableau = h('div', { class: 'bf-macro', role: 'region', 'aria-label': 'Projets par étape' });
  const fermes = h('div');

  async function deplacer(p, statut) {
    try {
      await api.patch('macro', { statut }, { id: p.id });
      message(msg, `${p.code_projet} : ${LIBELLE[statut]}.`, 'ok');
      await charger();
    } catch (e) { message(msg, e.message); }
  }

  // Les 4 mentions obligatoires de la facture finale (Hydro-Québec refuse la demande LogisVert sans elles)
  function panneauFacture(p) {
    const ok = (v) => (v ? '✓' : '✗');
    const zone = h('div', { class: `bf-facture${p.facture_manques ? ' bf-facture--manque' : ''}` },
      h('strong', {}, p.facture_manques ? `🧾 Facture finale : ${p.facture_manques} élément(s) avant « Facturé »` : '🧾 Facture finale conforme LogisVert'),
      h('ul', {},
        h('li', {}, `${ok(p.numero_ahri || p.numero_energy_star)} Numéro ${p.numero_ahri ? `AHRI ${p.numero_ahri}` : p.numero_energy_star ? `ENERGY STAR ${p.numero_energy_star}` : 'AHRI ou ENERGY STAR (dossier de la job)'}`),
        h('li', {}, '✓ Licence RBQ 5631-7035-01'),
        h('li', {}, `${ok(p.installation_terminee_le)} Date d'installation${p.installation_terminee_le ? ` : ${jour(p.installation_terminee_le)}` : ''}`),
        h('li', {}, `${ok(p.facture_payee_le)} Payée${p.facture_numero_mike ? ` (facture ${p.facture_numero_mike})` : ''}`),
        h('li', {}, `${ok(p.facture_verifiee_le)} Les 4 mentions vues sur la facture de Mike`)));
    if (peutBouger && !p.facture_payee_le) {
      const num = h('input', { placeholder: 'N° facture de Mike', 'aria-label': `Numéro de facture de ${p.code_projet}`, maxlength: 40 });
      zone.append(h('div', { class: 'bf-facture__geste' }, num, h('button', { type: 'button', class: 'bf-lien', onclick: async () => {
        try { await api.patch('macro', { action: 'facture_payee', facture_numero_mike: num.value }, { id: p.id }); message(msg, `${p.code_projet} : facture payée.`, 'ok'); await charger(); }
        catch (e) { message(msg, e.message); }
      } }, 'Marquer payée')));
    }
    if (peutBouger && p.facture_payee_le && !p.facture_verifiee_le) {
      zone.append(h('button', { type: 'button', class: 'bf-lien', onclick: async () => {
        if (!confirm('Confirmes-tu avoir vu, sur la facture finale de Mike : le numéro AHRI ou ENERGY STAR, la licence RBQ, la date d\'installation et la mention « Payé » ?')) return;
        try { await api.patch('macro', { action: 'facture_verifiee' }, { id: p.id }); message(msg, `${p.code_projet} : facture conforme. Tu peux passer à « Facturé ».`, 'ok'); await charger(); }
        catch (e) { message(msg, e.message); }
      } }, '✓ J\'ai vu les 4 mentions sur la facture'));
    }
    return zone;
  }

  function carte(p) {
    const idx = ETAPES.findIndex(([k]) => k === p.statut);
    const prec = ETAPES[idx - 1]; const suiv = ETAPES[idx + 1];
    return h('article', { class: `bf-macro__carte${recent(p.signe_le) && p.statut === 'attente_paiement' ? ' bf-macro__carte--nouveau' : ''}` },
      h('div', { class: 'bf-macro__tete' }, h('strong', {}, p.code_projet || 'Code à venir'),
        recent(p.signe_le) && p.statut === 'attente_paiement' ? h('span', { class: 'bf-etampe bf-etampe--converti' }, h('span', {}, 'Nouveau')) : null),
      h('p', { class: 'bf-macro__client' }, p.client_nom),
      h('p', { class: 'bf-muet' }, [p.ville, SUCCURSALES[p.succursale_code]].filter(Boolean).join(' | ')),
      h('div', { class: 'bf-macro__ligne' }, p.type_systeme ? pastilleType(p.type_systeme) : null,
        p.montant_avant_taxes_cents ? h('strong', {}, formatCents(p.montant_avant_taxes_cents)) : null),
      h('p', { class: 'bf-muet' }, [p.vendeur_nom, p.devis_numero_mike ? `soumission #${p.devis_numero_mike}` : null, p.signe_le ? `signé le ${jour(p.signe_le)}` : null].filter(Boolean).join(' | ')),
      p.installation_prevue_le ? h('p', {}, `Installation : ${jour(p.installation_prevue_le)}`) : null,
      ['termine', 'facture', 'en_cours'].includes(p.statut) || p.subvention_statut ? (peutBouger
        ? h('label', { class: 'bf-macro__subv' }, '🌱 LogisVert',
          h('select', { 'aria-label': `Subvention LogisVert de ${p.code_projet}`, onchange: async (ev) => {
            try { await api.patch('macro', { subvention_statut: ev.target.value }, { id: p.id }); message(msg, `${p.code_projet} : subvention « ${SUBVENTION[ev.target.value]} ». Le client reçoit un texto.`, 'ok'); await charger(); }
            catch (e) { message(msg, e.message); }
          } }, h('option', { value: '', disabled: true, selected: !p.subvention_statut }, 'Étape…'),
          Object.entries(SUBVENTION).map(([k, t]) => h('option', { value: k, selected: k === p.subvention_statut }, t))))
        : h('p', { class: 'bf-macro__st' }, `🌱 LogisVert : ${SUBVENTION[p.subvention_statut] || 'à déposer'}`)) : null,
      // Date limite LogisVert : 9 mois après la fin des travaux, tant que la demande n'est pas déposée
      p.installation_terminee_le && !['deposee', 'acceptee', 'versee', 'refusee'].includes(p.subvention_statut) ? (() => {
        const lim = new Date(p.installation_terminee_le); lim.setMonth(lim.getMonth() + 9);
        const jours = Math.ceil((lim - Date.now()) / 864e5);
        return h('p', { class: `bf-macro__st${jours < 60 ? ' bf-jobs__raison' : ''}` }, `⏳ LogisVert à déposer avant le ${jour(lim)}${jours < 60 ? ` (${Math.max(jours, 0)} j)` : ''}`);
      })() : null,
      // Facture finale conforme LogisVert (ADR-092) : les 4 mentions sur la facture de Mike, exigées avant « Facturé »
      p.statut === 'termine' ? panneauFacture(p) : null,
      p.depot_recu_le ? h('p', { class: 'bf-macro__depot' }, `💳 Dépôt reçu le ${jour(p.depot_recu_le)}${p.depot_montant_cents ? ` | ${formatCents(p.depot_montant_cents)}` : ''}`) : null,
      p.sous_traitant_nom ? h('p', { class: 'bf-macro__st' }, `🧰 ${p.sous_traitant_nom}`, p.cout_installation_cents ? ` | install. ${formatCents(p.cout_installation_cents)}` : '') : null,
      p.extras_a_approuver ? h('a', { href: '/extras', class: 'bf-macro__extras' }, `➕ ${p.extras_a_approuver} extra(s) à approuver`) : null,
      p.extras_approuves_cents ? h('p', { class: 'bf-macro__st' }, `Extras approuvés : ${formatCents(p.extras_approuves_cents)}`) : null,
      p.facture_st_soumise_le ? h('p', { class: 'bf-macro__st' }, `✓ Facture finale du sous-traitant : ${formatCents(p.facture_st_total_cents)}`) : null,
      p.sous_traitant_id && !['attente_paiement'].includes(p.statut) ? h('a', { href: `/jobs?fournisseur=${p.sous_traitant_id}&q=${encodeURIComponent(p.code_projet || '')}`,
        class: `bf-macro__dossier${p.dossier_manques ? ' bf-macro__dossier--manque' : ''}` },
        p.dossier_manques ? `📋 Dossier LogisVert : ${p.dossier_manques} manque(s)` : '📋 Dossier LogisVert complet') : null,
      p.lead_id ? h('a', { href: `/lead?id=${p.lead_id}`, class: 'bf-macro__lien' }, 'Voir le lead d\'origine') : null,
      peutBouger ? h('div', { class: 'bf-macro__actions' },
        h('button', { type: 'button', class: 'bf-macro__fleche', disabled: !prec, 'aria-label': prec ? `Reculer ${p.code_projet} à « ${prec[1]} »` : 'Première étape',
          title: prec ? `Reculer à « ${prec[1]} »` : '', onclick: () => deplacer(p, prec[0]) }, '◀'),
        h('button', { type: 'button', class: 'bf-macro__fleche', disabled: !suiv, 'aria-label': suiv ? `Avancer ${p.code_projet} à « ${suiv[1]} »` : 'Dernière étape',
          title: suiv ? `Avancer à « ${suiv[1]} »` : '', onclick: () => deplacer(p, suiv[0]) }, '▶'),
        p.statut !== 'facture' ? h('button', { type: 'button', class: 'bf-lien bf-macro__annuler', onclick: () => {
          if (confirm(`Annuler le projet ${p.code_projet} (${p.client_nom}) ? Un projet annulé ne revient pas.`)) deplacer(p, 'annule');
        } }, 'Annuler') : null) : null);
  }

  function afficher() {
    const t = filtres.recherche;
    const vus = projets.filter((p) => !t || [p.code_projet, p.client_nom, p.ville, p.vendeur_nom, p.devis_numero_mike].some((v) => String(v || '').toLowerCase().includes(t)));
    remplir(tableau, ...ETAPES.map(([k, lib]) => {
      const l = vus.filter((p) => p.statut === k);
      const total = l.reduce((s, p) => s + (p.montant_avant_taxes_cents || 0), 0);
      return h('section', { class: `bf-macro__colonne bf-macro__colonne--${k}`, 'aria-label': `${lib} : ${l.length} projet(s)` },
        h('header', { class: 'bf-macro__entete' }, h('h2', {}, lib), h('span', { class: 'bf-macro__compte' }, String(l.length)),
          total ? h('span', { class: 'bf-muet' }, formatCents(total)) : null),
        ...(l.length ? l.map(carte) : [h('p', { class: 'bf-muet bf-macro__vide' }, 'Aucun projet')]));
    }));
    const autres = vus.filter((p) => ['ferme', 'annule'].includes(p.statut));
    remplir(fermes, filtres.fermes && autres.length ? h('section', { class: 'bf-carte-section' }, h('h2', {}, `Fermés et annulés (${autres.length})`),
      h('ul', { class: 'bf-simple' }, autres.map((p) => h('li', {}, `${p.code_projet} | ${p.client_nom} | ${LIBELLE[p.statut]}`)))) : null);
  }

  async function charger() {
    try { projets = await api.get('macro', { succursale: filtres.succursale || undefined, fermes: filtres.fermes ? '1' : undefined }); }
    catch (e) { message(msg, e.message); projets = []; }
    afficher();
  }

  remplir(zone,
    h('div', { class: 'bf-titre' }, h('h1', {}, 'Macro | Projets HVAC'),
      h('span', { class: 'bf-muet' }, 'Chaque soumission signée par le client tombe ici, à l\'étape « Signé, attente du dépôt ».')),
    h('div', { class: 'bf-filtres' }, choixSucc, recherche, h('label', { class: 'bf-case' }, caseFermes, 'Afficher les fermés et annulés')),
    msg, tableau, fermes,
    h('p', { class: 'bf-muet' }, 'Le client signe sa soumission dans l\'app de Mike. D\'ici la greffe, Simon, Mike ou la planification inscrivent la soumission signée depuis la fiche du lead ; ensuite, le projet arrivera tout seul.'));
  charger();
}
