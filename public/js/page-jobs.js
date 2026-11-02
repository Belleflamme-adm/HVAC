// Mes jobs (ADR-080) : dès que le client signe sa soumission, le projet tombe chez le sous-traitant attitré.
// Il voit les machines (quantités, prix à 0 $) et SES prix d'installation : ce qu'il va nous charger.
// Jamais le prix chargé au client, le total de la facture ni notre marge (la base ne les lui envoie pas).
// Loi 25 : le nom, le téléphone et l'adresse du client arrivent après le dépôt.
// Simon, Mike et la planification ouvrent la même page avec ?fournisseur= pour voir ce que voit le sous-traitant.
// Feuille d'extra (ADR-081) : après le dépôt, le sous-traitant ajoute ses extras (de sa liste, ou hors liste avec
// justification), les envoie pour approbation, puis soumet sa facture finale (installation + extras approuvés).
import { initPage } from './bf-page.js?v=0.4.0';
import { api } from './bf-api.js?v=0.4.0';
import { remplir, h, message, param } from './bf-dom.js?v=0.4.0';
import { formatCents } from './bf-money.js?v=0.4.0';
import { pastilleType } from './bf-crm.js?v=0.4.0';
import { CAUSES, pastilleExtra, marqueHorsListe } from './bf-extras.js?v=0.4.0';
import { envoyerPhotos, galeriePhotos, boutonPhoto } from './bf-photo.js?v=0.4.0';
import { sectionDossier } from './bf-dossier.js?v=0.4.0';

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
  let fournisseurVu = null;
  let maListe = null;   // travaux de sa liste de prix (pour les extras), chargés au premier besoin
  const enCents = (t) => { const n = Number(String(t).replace(',', '.').replace(/[\s$]/g, '')); return Number.isFinite(n) && n > 0 ? Math.round(n * 100) : null; };
  const recharger = () => charger(fournisseurVu);
  const faire = async (corps, ok) => {
    try { const r = await api.patch('extras', corps); await recharger(); message(msg, typeof ok === 'function' ? ok(r) : ok, 'ok'); }
    catch (e) { message(msg, e.message); }
  };

  // Formulaire d'un extra : de ma liste (prix de la liste, non modifiable) ou hors liste (prix + justification)
  async function formExtra(j, zoneForm) {
    if (!maListe) {
      try { maListe = (await api.get('mes-prix')).travaux.filter((t) => t.cout_cents); } catch (e) { message(msg, e.message); return; }
    }
    const tri = [...maListe].sort((a, b) => (b.code.startsWith('EXTRA') - a.code.startsWith('EXTRA')) || a.nom.localeCompare(b.nom, 'fr'));
    const mode = h('select', { name: 'mode', 'aria-label': 'Provenance' }, h('option', { value: 'liste' }, 'De ma liste de prix'), h('option', { value: 'hors' }, 'Hors liste (avec justification)'));
    const deListe = h('label', {}, 'Travail', h('select', { name: 'travail' }, tri.map((t) => h('option', { value: t.id }, `${t.nom} | ${formatCents(t.cout_cents)}`))));
    const horsListe = h('div', { class: 'bf-grille2', hidden: true },
      h('label', {}, 'Description *', h('input', { name: 'description', maxlength: 200, placeholder: 'Support mural renforcé' })),
      h('label', {}, 'Ton prix unitaire ($) *', h('input', { name: 'prix', inputmode: 'decimal', placeholder: '180' })),
      h('label', { class: 'bf-pleine' }, 'Justification * (pourquoi ce n\'est pas dans ta liste, ce qui s\'est passé)', h('textarea', { name: 'justification', rows: 2, minlength: 10 })));
    // Photo obligatoire pour un extra hors liste ou un imprévu de chantier (ADR-083)
    const libPhotos = h('span', {});
    const photoRequise = () => mode.value === 'hors' || form.querySelector('[name=cause]').value === 'imprevu_chantier';
    const majPhotos = () => { libPhotos.textContent = photoRequise() ? '📷 Photos * (obligatoire : hors liste ou imprévu de chantier ; 5 au plus)' : '📷 Photos (5 au plus, recommandées : c\'est ta preuve)'; };
    mode.addEventListener('change', () => { deListe.hidden = mode.value !== 'liste'; horsListe.hidden = mode.value === 'liste'; majPhotos(); });
    const form = h('form', { class: 'bf-form bf-form--compact bf-jobs__form' },
      h('h3', {}, 'Nouvel extra'),
      h('div', { class: 'bf-grille2' }, h('label', {}, 'Provenance', mode), deListe,
        h('label', {}, 'Quantité', h('input', { name: 'qte', inputmode: 'decimal', value: '1' })),
        h('label', {}, 'Cause *', h('select', { name: 'cause', required: true, onchange: () => majPhotos() }, h('option', { value: '' }, 'Choisir…'),
          Object.entries(CAUSES).map(([k, t]) => h('option', { value: k }, t))))),
      horsListe,
      h('label', {}, 'Note (facultatif)', h('input', { name: 'note', maxlength: 500 })),
      h('label', {}, libPhotos, h('input', { type: 'file', name: 'photos', accept: 'image/*', multiple: true })),
      h('div', { class: 'bf-actions' }, h('button', { class: 'bf-bouton', type: 'submit' }, 'Ajouter au brouillon'),
        h('button', { class: 'bf-bouton bf-bouton--discret', type: 'button', onclick: () => zoneForm.replaceChildren() }, 'Annuler')));
    majPhotos();
    form.addEventListener('submit', async (ev) => {
      ev.preventDefault();
      if (photoRequise() && !form.querySelector('[name=photos]').files.length) {
        message(msg, 'Photo obligatoire pour un extra hors liste ou un imprévu de chantier : ajoute au moins une photo.');
        return;
      }
      const f = new FormData(form);
      const corps = { cause: f.get('cause'), quantite: Number(String(f.get('qte')).replace(',', '.')) || 1, note: f.get('note') || undefined };
      if (mode.value === 'liste') corps.type_travail_id = f.get('travail');
      else Object.assign(corps, { description: f.get('description'), cout_cents: enCents(f.get('prix')), justification: f.get('justification') });
      const photos = [...form.querySelector('[name=photos]').files].slice(0, 5);
      const bouton = form.querySelector('[type=submit]');
      bouton.disabled = true;
      try {
        const { id } = await api.post('extras', corps, { projet: j.id });
        let n = 0; let echec = '';
        try { n = await envoyerPhotos(id, photos); } catch (e) { echec = ` Photo non envoyée : ${e.message}. Réessaie avec « Ajouter une photo ».`; }
        await recharger();
        message(msg, `Extra ajouté au brouillon${n ? ` avec ${n} photo(s)` : ''}. Envoie la feuille pour approbation quand elle est complète.${echec}`, echec ? 'erreur' : 'ok');
      } catch (e) { message(msg, e.message); bouton.disabled = false; }
    });
    zoneForm.replaceChildren(form);
  }

  const manquePhoto = (x) => (x.hors_liste || x.cause === 'imprevu_chantier') && !x.nb_photos;
  function feuilleExtras(j) {
    const ext = j.extras || [];
    const sansPhoto = ext.filter((x) => x.statut === 'brouillon' && manquePhoto(x)).length;
    const brouillons = ext.filter((x) => x.statut === 'brouillon').length;
    const enAttente = ext.some((x) => ['brouillon', 'soumis'].includes(x.statut));
    const zoneForm = h('div');
    const peutFacturer = estSt && j.extras_ouverts && ['en_cours', 'termine'].includes(j.statut) && !enAttente;
    return h('section', { class: 'bf-jobs__extras' },
      h('h3', {}, 'Feuille d\'extra'),
      ext.length ? h('div', { class: 'bf-table-zone' }, h('table', { class: 'bf-table bf-jobs__table' },
        h('thead', {}, h('tr', {}, ['Extra', 'Qté', 'Ton prix', 'Total', 'Statut', ''].map((t, i) => h('th', { class: i && i < 4 ? 'num' : null }, t)))),
        h('tbody', {}, ext.map((x) => h('tr', { class: x.statut === 'refuse' ? 'bf-jobs__refuse' : null },
          h('td', {}, x.description, ' ', x.hors_liste ? marqueHorsListe() : null,
            x.statut === 'brouillon' && manquePhoto(x) ? [' ', h('span', { class: 'bf-pastille bf-extra--refuse' }, '📷 Photo obligatoire')] : null,
            h('div', { class: 'bf-muet' }, [CAUSES[x.cause], x.justification, x.note].filter(Boolean).join(' | ')),
            x.raison_refus ? h('div', { class: 'bf-jobs__raison' }, `Refusé : ${x.raison_refus}`) : null,
            galeriePhotos(x, { titre: x.description, peutRetirer: estSt && x.statut === 'brouillon', apres: recharger }),
            estSt && x.statut === 'brouillon' && (x.nb_photos || 0) < 5
              ? boutonPhoto(x.id, { reste: 5 - (x.nb_photos || 0), apres: recharger, erreur: (e) => message(msg, e.message) }) : null),
          h('td', { class: 'num' }, qte(x.quantite)), h('td', { class: 'num' }, formatCents(x.prix_cents)),
          h('td', { class: 'num' }, h('strong', {}, formatCents(x.total_cents))), h('td', {}, pastilleExtra(x.statut)),
          h('td', {}, estSt && x.statut === 'brouillon' ? h('button', { type: 'button', class: 'bf-lien', onclick: () => faire({ action: 'retirer', id: x.id }, 'Extra retiré du brouillon.') }, 'Retirer') : null)))))) 
        : h('p', { class: 'bf-muet' }, j.extras_ouverts ? 'Aucun extra. Un oubli ou un imprévu ? Ajoute-le ici, à partir de ta liste de prix.' : 'Aucun extra.'),
      h('dl', { class: 'bf-jobs__totaux' },
        h('dt', {}, 'Installation'), h('dd', {}, formatCents(j.total_cents)),
        h('dt', {}, 'Extras approuvés'), h('dd', {}, formatCents(j.extras_approuves_cents || 0)),
        j.extras_en_attente_cents ? [h('dt', { class: 'bf-muet' }, 'Extras pas encore approuvés (non comptés)'), h('dd', { class: 'bf-muet' }, formatCents(j.extras_en_attente_cents))] : null,
        h('dt', { class: 'bf-jobs__final' }, j.facture_soumise_le ? 'Facture finale soumise (avant taxes)' : 'Ta facture finale (avant taxes)'),
        h('dd', { class: 'bf-jobs__final' }, formatCents(j.total_final_cents))),
      j.facture_soumise_le ? h('p', { class: 'bf-jobs__facturee' }, `✓ Facture finale soumise le ${jour(j.facture_soumise_le)}. Les extras sont fermés pour cette job.`) : null,
      estSt && j.extras_ouverts ? h('div', { class: 'bf-actions' },
        h('button', { type: 'button', class: 'bf-bouton bf-bouton--discret', onclick: () => formExtra(j, zoneForm) }, '+ Extra'),
        brouillons ? h('button', { type: 'button', class: 'bf-bouton', onclick: () => faire({ action: 'envoyer', projet: j.id },
          (r) => `${r.envoyes} extra(s) envoyé(s) pour approbation à Belleflamme.`) }, `Envoyer pour approbation (${brouillons})`) : null,
        peutFacturer ? h('button', { type: 'button', class: 'bf-bouton', onclick: () => {
          if (confirm(`Soumettre ta facture finale de ${formatCents(j.total_final_cents)} avant taxes ? Ensuite, plus d'extras pour cette job.`)) {
            faire({ action: 'facture', projet: j.id }, (r) => `Facture finale soumise : ${formatCents(r.total_cents)} avant taxes. Envoie ta facture à Belleflamme pour ce montant.`);
          }
        } }, 'Soumettre ma facture finale') : null) : null,
      estSt && sansPhoto ? h('p', { class: 'bf-jobs__raison' }, `${sansPhoto} extra(s) sans photo : la photo est obligatoire pour un extra hors liste ou un imprévu de chantier avant l'envoi.`) : null,
      estSt && j.extras_ouverts && enAttente && ['en_cours', 'termine'].includes(j.statut)
        ? h('p', { class: 'bf-muet' }, 'La facture finale se soumet quand tous tes extras sont approuvés ou refusés.') : null,
      zoneForm);
  }

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
        h('tfoot', {}, h('tr', {}, h('th', { colspan: 3 }, 'Ton installation (avant taxes)'), h('th', { class: 'num' }, formatCents(j.total_cents)))))),
      j.statut === 'attente_paiement' ? h('p', { class: 'bf-muet' }, 'Le dossier LogisVert et la feuille d\'extra s\'ouvrent quand le dépôt du client est reçu.')
        : [sectionDossier(j, { modifiable: estSt && j.extras_ouverts, belleflamme: ['Admin tout', 'Direction', 'Coordonnateur'].includes(user.role), msg }), feuilleExtras(j)]);
  }

  async function charger(fournisseur) {
    fournisseurVu = fournisseur || null;
    try {
      const q = (param('q') || '').toLowerCase();
      const jobs = (await api.get('jobs', { fournisseur: fournisseur || undefined }))
        .filter((j) => !q || [j.code_projet, j.ville, j.client_nom].some((v) => String(v || '').toLowerCase().includes(q)));
      const total = jobs.reduce((s, j) => s + (j.total_final_cents ?? j.total_cents ?? 0), 0);
      const extrasAttente = jobs.reduce((s, j) => s + (j.extras || []).filter((x) => x.statut === 'soumis').length, 0);
      remplir(liste,
        h('div', { class: 'bf-jobs__resume' },
          h('span', {}, h('strong', {}, String(jobs.length)), ` job${jobs.length > 1 ? 's' : ''}`),
          h('span', {}, h('strong', {}, String(jobs.filter((j) => j.statut === 'attente_paiement').length)), ' en attente du dépôt'),
          h('span', {}, h('strong', {}, String(extrasAttente)), ' extra(s) en attente d\'approbation'),
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
