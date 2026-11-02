// Fiche d'un lead (ADR-056) : prise en charge, appel / courriel / texto, visite planifiée dans Pointage, journal.
// Chaque geste est horodaté par la base : c'est ce qui mesure la rapidité du vendeur.
// Soumission signée (ADR-079) : le projet tombe dans le Macro et le lead passe à Vendu.
import { initPage } from './bf-page.js?v=0.4.0';
import { barreContact, historiqueComms } from './bf-contact.js?v=0.4.0';
import { api } from './bf-api.js?v=0.4.0';
import { remplir, h, message, param } from './bf-dom.js?v=0.4.0';
import { formatCents } from './bf-money.js?v=0.4.0';
import { SOURCES_LEAD, ACTIVITES, RESULTATS, TYPES_DEMANDE, pastilleLead, pastilleType, filigranePerdu, delaiLead, heure, duree, voitBoard } from './bf-crm.js?v=0.4.0';

const URL_POINTAGE = 'https://belleflammetime.netlify.app';   // app de Mike : lien seulement
// Visite (ADR-086) : planifiée UNE fois dans Pointage (pré-installation Ventilation). Le lien porte la référence du lead ;
// Pointage la renvoie avec la date, qui arrive seule dans le lead. Paramètres d'URL à confirmer avec Mike.
const lienPointage = (l) => `${URL_POINTAGE}/?hvac_lead=${encodeURIComponent(l.id)}&client=${encodeURIComponent(l.contact_nom || '')}`
  + `&tel=${encodeURIComponent(l.contact_tel || '')}&division=Ventilation`;

const user = await initPage();
if (user) {
  const zone = document.getElementById('contenu');
  const msg = h('p', { class: 'bf-message', role: 'alert' });
  const id = param('id');

  const noter = async (corps) => {
    try { await api.post('lead-activite', corps, { id }); await charger(); message(msg, 'Enregistré.', 'ok'); }
    catch (e) { message(msg, e.message); }
  };

  // Formulaire de geste : un seul à la fois, selon le bouton choisi
  const panneau = h('div');
  // Pointage branché ? Alors la date de visite vient seulement de Pointage (plus de saisie dans le lead)
  let pointage = false;
  try { ({ pointage } = await api.get('integrations')); } catch { /* inconnu : saisie temporaire permise */ }
  const PLANIF = ['Admin tout', 'Direction', 'Coordonnateur'];

  // Soumission signée par le client (dans l'app de Mike) : Simon, Mike ou la planification l'inscrivent d'ici la greffe
  // Sous-traitant attitré + lignes (ADR-080) : machines sans prix, installation tirée de SA liste de prix.
  // Le projet tombe aussi dans « Mes jobs » du sous-traitant, qui ne voit que son prix.
  async function ouvrirSigne(l) {
    let opts = { types: [], sousTraitants: [], confies: [], grille: [] };
    try { opts = await api.get('installation-options'); } catch { /* sans options : projet sans sous-traitant */ }
    const sts = opts.sousTraitants.filter((f) => f.actif !== false);
    const prixDe = (st, t) => opts.grille.find((g) => g.fournisseur_id === st && g.type_travail_id === t)?.cout_cents;
    const choixSt = h('select', { name: 'sous_traitant' }, h('option', { value: '' }, 'Aucun pour l\'instant'), sts.map((f) => h('option', { value: f.id }, f.nom)));
    const machines = h('div', { class: 'bf-signe__lignes' });
    const installs = h('div', { class: 'bf-signe__lignes' });
    const total = h('p', { class: 'bf-muet' });
    const retirer = (el) => h('button', { type: 'button', class: 'bf-lien', 'aria-label': 'Retirer la ligne', onclick: () => { el.remove(); recalc(); } }, 'Retirer');
    const champQte = () => h('label', {}, 'Qté', h('input', { name: 'qte', inputmode: 'decimal', value: '1', oninput: () => recalc() }));
    function ajouterMachine() {
      const el = h('div', { class: 'bf-signe__ligne', 'data-type': 'machine' });
      el.append(h('label', {}, 'Machine', h('input', { name: 'desc', placeholder: 'Thermopompe murale 12 000 BTU' })), champQte(), retirer(el));
      machines.append(el);
    }
    function ajouterInstall() {
      const st = choixSt.value;
      const confies = new Set(opts.confies.filter((c) => c.fournisseur_id === st).map((c) => c.type_travail_id));
      const types = opts.types.filter((t) => confies.has(t.id) && prixDe(st, t.id));
      if (!types.length) { message(msg, 'Ce sous-traitant n\'a aucun travail avec un prix dans sa liste.'); return; }
      const el = h('div', { class: 'bf-signe__ligne', 'data-type': 'installation' });
      el.append(h('label', {}, 'Travail (liste du sous-traitant)', h('select', { name: 'travail', onchange: () => recalc() },
        types.map((t) => h('option', { value: t.id }, `${t.nom} | ${formatCents(prixDe(st, t.id))}`)))), champQte(), retirer(el));
      installs.append(el);
      recalc();
    }
    const qteDe = (el) => Number(String(el.querySelector('[name=qte]').value).replace(',', '.')) || 0;
    function recalc() {
      const st = choixSt.value;
      const c = [...installs.children].reduce((s, el) => s + Math.round(qteDe(el) * (prixDe(st, el.querySelector('[name=travail]').value) || 0)), 0);
      total.textContent = c ? `Coût d'installation du sous-traitant : ${formatCents(c)} (c'est ce qu'il verra, rien d'autre)` : '';
    }
    const boutonInstall = h('button', { type: 'button', class: 'bf-bouton bf-bouton--discret', disabled: true, onclick: ajouterInstall }, '+ Installation');
    choixSt.addEventListener('change', () => { installs.replaceChildren(); boutonInstall.disabled = !choixSt.value; recalc(); });
    const form = h('form', { class: 'bf-form bf-form--compact' },
      h('h2', {}, 'Soumission signée par le client'),
      h('p', { class: 'bf-muet' }, 'Le client a signé sa soumission dans l\'app de Mike. Le projet tombera dans le Macro, à l\'étape « Signé, attente du dépôt », et le lead passera à Vendu.'),
      h('div', { class: 'bf-grille2' },
        h('label', {}, 'Numéro de la soumission (app de Mike) *', h('input', { name: 'numero', required: true, inputmode: 'numeric', placeholder: '120815' })),
        h('label', {}, 'Montant avant taxes ($)', h('input', { name: 'montant', inputmode: 'decimal', placeholder: '9 850' })),
        h('label', {}, 'Type de système', h('select', { name: 'type' }, h('option', { value: '' }, 'Celui du lead'),
          Object.entries(TYPES_DEMANDE).map(([v, t]) => h('option', { value: v, selected: v === l.type_demande }, t)))),
        h('label', {}, 'Sous-traitant attitré', choixSt)),
      h('h3', {}, 'Machines'), h('p', { class: 'bf-muet' }, 'Le sous-traitant les voit à 0 $ : aucun prix n\'est inscrit ici.'), machines,
      h('div', { class: 'bf-actions' }, h('button', { type: 'button', class: 'bf-bouton bf-bouton--discret', onclick: ajouterMachine }, '+ Machine')),
      h('h3', {}, 'Installation du sous-traitant'), installs, total,
      h('div', { class: 'bf-actions' }, boutonInstall),
      h('div', { class: 'bf-actions' },
        h('button', { class: 'bf-bouton', type: 'submit' }, 'Envoyer dans le Macro'),
        h('button', { class: 'bf-bouton bf-bouton--discret', type: 'button', onclick: () => panneau.replaceChildren() }, 'Annuler')));
    form.addEventListener('submit', async (ev) => {
      ev.preventDefault();
      const f = new FormData(form);
      const brut = String(f.get('montant') || '').replace(/\s/g, '').replace(',', '.');
      const lignes = [
        ...[...machines.children].map((el) => ({ type_ligne: 'machine', description: el.querySelector('[name=desc]').value.trim(), quantite: qteDe(el) }))
          .filter((x) => x.description),
        ...[...installs.children].map((el) => ({ type_ligne: 'installation', type_travail_id: el.querySelector('[name=travail]').value, quantite: qteDe(el) })),
      ];
      try {
        await api.post('projet-signe', { lead_id: id, devis_numero_mike: String(f.get('numero')).trim(),
          montant_avant_taxes_cents: brut ? Math.round(Number(brut) * 100) : undefined, type_systeme: f.get('type') || undefined,
          sous_traitant_id: choixSt.value || undefined, lignes });
        panneau.replaceChildren();
        await charger();
        message(msg, `Projet envoyé dans le Macro, à l'étape « Signé, attente du dépôt ». Le lead est maintenant Vendu.${choixSt.value ? ' Le sous-traitant le voit dans « Mes jobs ».' : ''}`, 'ok');
      } catch (e) { message(msg, e.message); }
    });
    ajouterMachine();
    panneau.replaceChildren(form);
  }
  function ouvrir(type) {
    const resultats = type === 'appel' ? ['joint', 'message_laisse', 'pas_de_reponse'] : null;
    const form = h('form', { class: 'bf-form bf-form--compact' },
      h('h2', {}, ACTIVITES[type]),
      resultats ? h('label', {}, 'Résultat', h('select', { name: 'resultat' }, resultats.map((r) => h('option', { value: r }, RESULTATS[r])))) : null,
      type === 'visite_planifiee' ? h('p', { class: 'bf-muet' },
        'Temporaire, tant que Pointage n\'est pas branché à l\'app : planifie la visite dans ', h('a', { href: URL_POINTAGE, target: '_blank', rel: 'noopener' }, 'Pointage'),
        ', puis inscris la même date ici. Une fois branché, la date arrivera toute seule.') : null,
      type === 'visite_planifiee' ? h('label', {}, 'Date et heure de la visite *', h('input', { type: 'datetime-local', name: 'visite_le', required: true })) : null,
      h('label', {}, type === 'perdu' ? 'Raison de la perte *' : 'Note', h('textarea', { name: 'note', rows: 2, required: type === 'perdu' })),
      h('div', { class: 'bf-actions' },
        h('button', { class: 'bf-bouton', type: 'submit' }, 'Enregistrer'),
        h('button', { class: 'bf-bouton bf-bouton--discret', type: 'button', onclick: () => panneau.replaceChildren() }, 'Annuler')));
    form.addEventListener('submit', async (ev) => {
      ev.preventDefault();
      const f = new FormData(form);
      const visite = f.get('visite_le');
      await noter({ type, resultat: f.get('resultat') || undefined, note: (f.get('note') || '').toString().trim() || undefined,
        visite_le: visite ? new Date(visite).toISOString() : undefined });
      panneau.replaceChildren();
    });
    panneau.replaceChildren(form);
  }

  async function charger() {
    let res;
    try { res = await api.get('lead', { id }); } catch (e) { remplir(zone, h('h1', {}, 'Lead'), h('p', { class: 'bf-message' }, e.message)); return; }
    const { lead: l, activites } = res;
    const ferme = ['perdu', 'converti'].includes(l.statut);
    const tel = l.contact_tel ? l.contact_tel.replace(/[^\d+]/g, '') : null;

    const boutons = ferme
      ? [h('button', { class: 'bf-bouton bf-bouton--discret', type: 'button', onclick: () => noter({ type: 'reouvert' }) }, 'Réouvrir')]
      : [
        !l.pris_en_charge_le ? h('button', { class: 'bf-bouton', type: 'button', onclick: () => noter({ type: 'prise_en_charge' }) }, 'Je prends en charge') : null,
        h('button', { class: 'bf-bouton', type: 'button', onclick: () => ouvrir('appel') }, 'Appel'),
        h('button', { class: 'bf-bouton', type: 'button', onclick: () => ouvrir('courriel') }, 'Courriel'),
        h('button', { class: 'bf-bouton', type: 'button', onclick: () => ouvrir('texto') }, 'Texto'),
        h('a', { class: 'bf-bouton', href: lienPointage(l), target: '_blank', rel: 'noopener', 'data-pointage': '1' }, l.visite_prevue_le ? '📅 Changer la visite dans Pointage' : '📅 Planifier dans Pointage'),
        pointage ? null : h('button', { class: 'bf-bouton bf-bouton--discret', type: 'button', title: 'Temporaire : tant que Pointage n\'est pas branché',
          onclick: () => ouvrir('visite_planifiee') }, 'Inscrire la date (temporaire)'),
        h('button', { class: 'bf-bouton bf-bouton--discret', type: 'button', onclick: () => ouvrir('note') }, 'Note'),
        h('button', { class: 'bf-bouton bf-bouton--discret', type: 'button', onclick: () => ouvrir('perdu') }, 'Perdu'),
        PLANIF.includes(user.role) ? h('button', { class: 'bf-bouton bf-bouton--signe', type: 'button', onclick: () => ouvrirSigne(l) }, '✓ Soumission signée') : null,
      ];
    // Projet dans le Macro (lead vendu)
    let projet = null;
    if (l.statut === 'converti') { try { [projet] = await api.get('macro', { lead: id }); } catch { /* sans Macro */ } }

    // Board principal : type de demande et réattribution (avec les qualifications de chaque vendeur)
    let reattribution = null;
    if (voitBoard(user)) {
      const choixType = h('select', { 'aria-label': 'Type de demande' }, h('option', { value: '' }, 'À préciser'),
        Object.entries(TYPES_DEMANDE).map(([v, t]) => h('option', { value: v, selected: v === l.type_demande }, t)));
      const choix = h('select', { 'aria-label': 'Vendeur' });
      const avis = h('span', { class: 'bf-muet' });
      let qualifs = {};
      const majAvis = () => {
        const t = choixType.value; const v = choix.value;
        avis.textContent = t && v && !(qualifs[v] || []).includes(t) ? `⚠ ce vendeur n'est pas qualifié pour « ${TYPES_DEMANDE[t]} »` : '';
        avis.className = avis.textContent ? 'bf-retard' : 'bf-muet';
      };
      api.get('crm-vendeurs').then(({ membres, employes }) => {
        qualifs = Object.fromEntries(membres.map((m) => [m.employe_id, m.types || []]));
        choix.append(...employes.map((e) => h('option', { value: e.id, selected: e.id === l.assigne_a },
          `${e.prenom} ${e.nom}${qualifs[e.id] ? ` (${qualifs[e.id].map((t) => TYPES_DEMANDE[t]).join(', ') || 'aucun type'})` : ''}`)));
        majAvis();
      }).catch(() => {});
      choixType.addEventListener('change', majAvis);
      choix.addEventListener('change', majAvis);
      reattribution = h('section', { class: 'bf-carte-section' },
        h('h2', {}, 'Board principal'),
        h('div', { class: 'bf-filtres' }, h('span', { class: 'bf-muet' }, 'Type de demande'), choixType,
          h('span', { class: 'bf-muet' }, 'Vendeur'), choix,
          h('button', { class: 'bf-bouton bf-bouton--discret', type: 'button', onclick: async () => {
            try {
              await api.patch('lead', { type_demande: choixType.value || null, ...(choix.value && choix.value !== l.assigne_a ? { assigne_a: choix.value } : {}) }, { id });
              await charger(); message(msg, 'Lead mis à jour.', 'ok');
            } catch (e) { message(msg, e.message); }
          } }, 'Enregistrer')),
        avis);
    }

    remplir(zone,
      h('p', {}, h('a', { href: '/leads' }, '← Leads')),
      h('div', { class: 'bf-titre' }, h('h1', {}, l.contact_nom || 'Lead'),
        h('div', { class: 'bf-titre__droite' },
          h('span', { class: 'bf-etampes' }, pastilleLead(l.statut), pastilleType(l.type_demande)),
          barreContact({ tel: l.contact_tel, courriel: l.contact_courriel, site: l.ville ? { adresse: l.adresse, ville: l.ville } : null, lead_id: l.id, msg }))),
      h('section', { class: `bf-carte-section${l.statut === 'perdu' ? ' bf-fiche-perdue' : ''}` },
        l.statut === 'perdu' ? filigranePerdu() : null,
        h('dl', { class: 'bf-fiche' },
          h('dt', {}, 'Téléphone'), h('dd', {}, tel ? h('a', { href: `tel:${tel}` }, l.contact_tel) : 'n/d'),
          h('dt', {}, 'Courriel'), h('dd', {}, l.contact_courriel ? h('a', { href: `mailto:${l.contact_courriel}` }, l.contact_courriel) : 'n/d'),
          h('dt', {}, 'Ville'), h('dd', {}, l.ville || 'n/d'),
          h('dt', {}, 'Type'), h('dd', {}, l.type_demande ? TYPES_DEMANDE[l.type_demande] : 'À préciser'),
          h('dt', {}, 'Source'), h('dd', {}, [SOURCES_LEAD[l.source], l.campagne].filter(Boolean).join(' | ')),
          h('dt', {}, 'Reçu'), h('dd', {}, heure(l.recu_le)),
          h('dt', {}, 'Vendeur'), h('dd', {}, l.vendeur_nom || 'Non attribué : aucun vendeur qualifié pour ce type'),
          h('dt', {}, 'Rapidité'), h('dd', {}, delaiLead(l) || 'n/d'),
          l.visite_prevue_le ? h('dt', {}, 'Visite') : null,
          l.visite_prevue_le ? h('dd', {}, heure(l.visite_prevue_le), l.visite_pointage_ref ? h('span', { class: 'bf-pastille bf-pastille--pointage', title: `Pointage : ${l.visite_pointage_ref}` }, '📅 reçue de Pointage') : null) : null),
        l.besoin ? h('p', {}, l.besoin) : null),
      msg,
      projet ? h('section', { class: 'bf-carte-section bf-projet-lie' },
        h('h2', {}, 'Projet dans le Macro'),
        h('p', {}, h('strong', {}, projet.code_projet), ` | ${projet.client_nom}`, projet.montant_avant_taxes_cents ? ` | ${formatCents(projet.montant_avant_taxes_cents)}` : '',
          projet.devis_numero_mike ? ` | soumission #${projet.devis_numero_mike}` : ''),
        h('a', { class: 'bf-bouton', href: '/macro' }, 'Ouvrir le Macro')) : null,
      h('div', { class: 'bf-actions' }, boutons),
      panneau,
      reattribution,
      historiqueComms({ lead_id: l.id }),
      h('h2', {}, 'Journal'),
      h('ol', { class: 'bf-journal' }, [...activites].reverse().map((a) => h('li', {},
        h('strong', {}, ACTIVITES[a.type] || a.type), a.source === 'pointage' ? h('span', { class: 'bf-pastille bf-pastille--pointage' }, 'Pointage') : null,
        a.resultat ? ` (${RESULTATS[a.resultat] || a.resultat})` : '',
        h('span', { class: 'bf-muet' }, ` | ${heure(a.fait_le)} | ${duree((new Date(a.fait_le) - new Date(l.recu_le)) / 60000)} après l'arrivée`),
        a.visite_le ? h('div', {}, `Visite : ${heure(a.visite_le)}`) : null,
        a.note ? h('div', {}, a.note) : null))));
  }
  charger();
  // Un appel, texto ou courriel lancé de la fiche change le statut et la rapidité du lead : on recharge
  document.addEventListener('bf:communications', () => charger());
}
