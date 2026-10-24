// Dossier de job LogisVert (ADR-084) : numéro AHRI du système, chaque appareil (marque, modèle, numéro de série)
// avec la photo de sa plaque et la photo de l'appareil installé. Obligatoire pour TOUTES les jobs, extras ou pas :
// sans dossier complet, pas de facture finale du sous-traitant et pas d'étape « Terminé ».
// Ces pièces servent à la demande LogisVert (Hydro-Québec) faite avec le client.
import { api } from './bf-api.js?v=0.4.0';
import { h, message } from './bf-dom.js?v=0.4.0';
import { compresserImage, vignettes } from './bf-photo.js?v=0.4.0';

export const ROLES_APPAREIL = { exterieur: 'Unité extérieure', interieur: 'Unité intérieure (tête, serpentin)', fournaise: 'Fournaise', autre: 'Autre' };
const COMPTES = ['exterieur', 'interieur', 'fournaise'];

async function envoyerPhoto(projet, equipement, categorie, fichiers) {
  for (const f of fichiers) await api.post('job-dossier', { action: 'photo', equipement_id: equipement, categorie, ...(await compresserImage(f)) }, { projet });
}

// zone : conteneur à remplir ; j : la job (Mes jobs) ; modifiable : le sous-traitant, avant sa facture finale
export function sectionDossier(j, { modifiable, msg, apres = () => {} }) {
  const zone = h('section', { class: 'bf-dossier', 'aria-label': 'Dossier LogisVert' }, h('p', { class: 'bf-muet' }, 'Chargement du dossier LogisVert…'));
  const recharger = () => charger().then(apres);
  const agir = async (fn, ok) => { try { await fn(); await recharger(); if (ok) message(msg, ok, 'ok'); } catch (e) { message(msg, e.message); } };

  const champPhoto = (equipement, categorie, libelle) => {
    const choix = h('input', { type: 'file', accept: 'image/*', multiple: true, hidden: true });
    const bouton = h('button', { type: 'button', class: 'bf-bouton bf-bouton--discret bf-dossier__photo', onclick: () => choix.click() }, `📷 ${libelle}`);
    choix.addEventListener('change', () => {
      const fichiers = [...choix.files];
      if (!fichiers.length) return;
      bouton.disabled = true; bouton.textContent = 'Envoi…';
      agir(() => envoyerPhoto(j.id, equipement, categorie, fichiers), `${fichiers.length} photo(s) ajoutée(s) au dossier.`).finally(() => { bouton.disabled = false; bouton.textContent = `📷 ${libelle}`; });
    });
    return h('span', {}, bouton, choix);
  };

  function formAppareil() {
    const form = h('form', { class: 'bf-form bf-form--compact bf-jobs__form' },
      h('h4', {}, 'Ajouter un appareil installé'),
      h('div', { class: 'bf-grille2' },
        h('label', {}, 'Type *', h('select', { name: 'role' }, Object.entries(ROLES_APPAREIL).map(([k, t]) => h('option', { value: k }, t)))),
        h('label', {}, 'Marque *', h('input', { name: 'marque', required: true, maxlength: 80, placeholder: 'Mitsubishi' })),
        h('label', {}, 'Modèle *', h('input', { name: 'modele', required: true, maxlength: 80, placeholder: 'MXZ-2C20NAHZ' })),
        h('label', {}, 'Numéro de série *', h('input', { name: 'serie', required: true, maxlength: 60, placeholder: 'Sur la plaque signalétique' })),
        h('label', {}, '📷 Photo de la plaque *', h('input', { type: 'file', name: 'plaque', accept: 'image/*' })),
        h('label', {}, '📷 Photo de l\'appareil installé *', h('input', { type: 'file', name: 'installe', accept: 'image/*' }))),
      h('div', { class: 'bf-actions' }, h('button', { class: 'bf-bouton', type: 'submit' }, 'Ajouter l\'appareil'),
        h('button', { class: 'bf-bouton bf-bouton--discret', type: 'button', onclick: () => form.remove() }, 'Annuler')));
    form.addEventListener('submit', async (ev) => {
      ev.preventDefault();
      const f = new FormData(form);
      const bouton = form.querySelector('[type=submit]'); bouton.disabled = true;
      try {
        const { id } = await api.post('job-dossier', { action: 'equipement', role: f.get('role'), marque: f.get('marque'), modele: f.get('modele'), numero_serie: f.get('serie') }, { projet: j.id });
        let echec = '';
        try {
          await envoyerPhoto(j.id, id, 'plaque', [...form.querySelector('[name=plaque]').files]);
          await envoyerPhoto(j.id, id, 'installe', [...form.querySelector('[name=installe]').files]);
        } catch (e) { echec = ` Photo non envoyée : ${e.message}.`; }
        await recharger();
        message(msg, `Appareil ajouté au dossier.${echec}`, echec ? 'erreur' : 'ok');
      } catch (e) { message(msg, e.message); bouton.disabled = false; }
    });
    return form;
  }

  async function charger() {
    let d;
    try { d = await api.get('job-dossier', { projet: j.id }); }
    catch (e) { zone.replaceChildren(h('p', { class: 'bf-muet' }, `Dossier indisponible : ${e.message}`)); return; }
    const photosDe = (eq, cat) => d.photos.filter((p) => p.equipement_id === eq && p.categorie === cat);
    const retirerPhoto = modifiable ? (p) => agir(() => api.patch('job-dossier', { action: 'retirer_photo', id: p.id }), 'Photo retirée.') : null;
    const zoneForm = h('div');
    const ahri = h('input', { name: 'ahri', inputmode: 'numeric', value: d.numero_ahri || '', placeholder: 'Ex. 210987654', 'aria-label': 'Numéro de certificat AHRI', disabled: !modifiable, maxlength: 16 });
    zone.replaceChildren(...[
      h('div', { class: 'bf-dossier__tete' }, h('h3', {}, 'Dossier LogisVert'),
        d.manques.length ? h('span', { class: 'bf-pastille bf-extra--refuse' }, `${d.manques.length} élément(s) manquant(s)`) : h('span', { class: 'bf-pastille bf-extra--approuve' }, '✓ Dossier complet')),
      d.manques.length ? h('ul', { class: 'bf-dossier__manques' }, d.manques.map((m) => h('li', {}, m))) : null,
      d.manques.length && modifiable ? h('p', { class: 'bf-muet' }, 'Obligatoire pour chaque job : sans dossier complet, pas de facture finale et la job ne peut pas passer à « Terminé ».') : null,
      h('form', { class: 'bf-dossier__ahri', onsubmit: (e) => { e.preventDefault(); agir(() => api.patch('job-dossier', { action: 'ahri', projet: j.id, numero_ahri: ahri.value }), 'Numéro AHRI enregistré.'); } },
        h('label', {}, 'Numéro de certificat AHRI du système *', ahri),
        modifiable ? h('button', { class: 'bf-bouton bf-bouton--discret', type: 'submit' }, 'Enregistrer') : null),
      ...d.equipements.map((eq) => h('div', { class: 'bf-dossier__appareil' },
        h('div', { class: 'bf-dossier__appareil-tete' },
          h('div', {}, h('strong', {}, ROLES_APPAREIL[eq.role] || eq.role), ` | ${eq.marque} ${eq.modele}`, h('div', { class: 'bf-muet' }, `N° de série : ${eq.numero_serie}`)),
          modifiable ? h('button', { type: 'button', class: 'bf-lien', onclick: () => { if (confirm(`Retirer ${eq.marque} ${eq.modele} (${eq.numero_serie}) du dossier ?`)) agir(() => api.patch('job-dossier', { action: 'retirer_equipement', id: eq.id }), 'Appareil retiré.'); } }, 'Retirer') : null),
        COMPTES.includes(eq.role) ? h('div', { class: 'bf-dossier__photos' },
          ...[['plaque', 'Plaque signalétique'], ['installe', 'Appareil installé']].map(([cat, lib]) => {
            const l = photosDe(eq.id, cat);
            return h('div', { class: `bf-dossier__case${l.length ? '' : ' bf-dossier__case--manque'}` },
              h('span', { class: 'bf-muet' }, `${lib}${l.length ? '' : ' *'}`), l.length ? vignettes(l, { titre: `${eq.modele} | ${lib}`, retirer: retirerPhoto }) : null,
              modifiable ? champPhoto(eq.id, cat, l.length ? 'Ajouter' : lib) : (l.length ? null : h('span', { class: 'bf-jobs__raison' }, 'Manquante')));
          })) : null)),
      d.purgees ? h('p', { class: 'bf-muet' }, `${d.purgees} photo(s) purgée(s) après 5 ans (Loi 25).`) : null,
      modifiable ? h('div', { class: 'bf-actions' }, h('button', { type: 'button', class: 'bf-bouton bf-bouton--discret', onclick: () => { if (!zoneForm.firstChild) zoneForm.append(formAppareil()); } }, '+ Appareil installé')) : null,
      zoneForm].filter(Boolean));   // replaceChildren afficherait « null »
  }
  charger();
  return zone;
}
