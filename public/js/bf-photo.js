// Photos des extras (ADR-082) : compression dans le navigateur, vignettes, agrandissement.
// Les photos de cellulaire (3 à 8 Mo) sont réduites à 1600 px en JPEG avant l'envoi (souvent 200 à 600 Ko) :
// envoi plus rapide sur le chantier, et sous la limite des fonctions serverless.
import { api } from './bf-api.js?v=0.4.0';
import { h } from './bf-dom.js?v=0.4.0';
import { ouvrirFenetre } from './bf-fenetre.js?v=0.4.0';

const COTE_MAX = 1600;

export async function compresserImage(fichier) {
  if (!/^image\//.test(fichier.type)) throw new Error(`${fichier.name} : ce n'est pas une photo`);
  const image = await createImageBitmap(fichier, { imageOrientation: 'from-image' });
  const echelle = Math.min(1, COTE_MAX / Math.max(image.width, image.height));
  const toile = document.createElement('canvas');
  toile.width = Math.round(image.width * echelle); toile.height = Math.round(image.height * echelle);
  toile.getContext('2d').drawImage(image, 0, 0, toile.width, toile.height);
  image.close?.();
  const url = toile.toDataURL('image/jpeg', 0.82);
  return { type: 'image/jpeg', donnees: url.slice(url.indexOf(',') + 1) };
}

// Envoie des photos sur un extra en brouillon ; rend le nombre envoyé
export async function envoyerPhotos(extraId, fichiers) {
  let n = 0;
  for (const f of fichiers) { await api.post('extra-photos', await compresserImage(f), { extra: extraId }); n++; }
  return n;
}

export function agrandir(url, titre) {
  ouvrirFenetre(titre, (corps) => corps.replaceChildren(h('img', { src: url, alt: titre, class: 'bf-photo__grande' })));
}

// Vignettes d'un extra (chargées à la demande : URL signées de 10 minutes)
export function galeriePhotos(extra, { titre = 'Photo de l\'extra', peutRetirer = false, apres = () => {} } = {}) {
  const zone = h('div', { class: 'bf-photos', 'aria-label': 'Photos' });
  if (!extra.nb_photos) return zone;
  zone.append(h('span', { class: 'bf-muet' }, `📷 ${extra.nb_photos} photo(s)…`));
  api.get('extra-photos', { extra: extra.id }).then((photos) => {
    zone.replaceChildren(...photos.map((p, i) => h('span', { class: 'bf-photo' },
      h('button', { type: 'button', class: 'bf-photo__vignette', 'aria-label': `Agrandir la photo ${i + 1}`, onclick: () => agrandir(p.url, `${titre} | photo ${i + 1}`) },
        h('img', { src: p.url, alt: `Photo ${i + 1}`, loading: 'lazy' })),
      peutRetirer ? h('button', { type: 'button', class: 'bf-photo__retirer', 'aria-label': `Retirer la photo ${i + 1}`, title: 'Retirer',
        onclick: async () => { await api.patch('extra-photos', { action: 'retirer', id: p.id }); apres(); } }, '×') : null)));
  }).catch((e) => zone.replaceChildren(h('span', { class: 'bf-muet' }, `Photos indisponibles : ${e.message}`)));
  return zone;
}

// Bouton « Ajouter une photo » (appareil photo ou galerie du téléphone)
export function boutonPhoto(extraId, { reste = 5, apres = () => {}, erreur = () => {} } = {}) {
  const choix = h('input', { type: 'file', accept: 'image/*', multiple: true, hidden: true });
  const bouton = h('button', { type: 'button', class: 'bf-lien', onclick: () => choix.click() }, '📷 Ajouter une photo');
  choix.addEventListener('change', async () => {
    const fichiers = [...choix.files].slice(0, reste);
    if (!fichiers.length) return;
    bouton.disabled = true; bouton.textContent = 'Envoi…';
    try { await envoyerPhotos(extraId, fichiers); apres(); }
    catch (e) { erreur(e); bouton.disabled = false; bouton.textContent = '📷 Ajouter une photo'; }
  });
  return h('span', {}, bouton, choix);
}

// Vignettes à partir d'URL déjà signées (dossier de job, ADR-084)
export function vignettes(photos, { titre = 'Photo', retirer = null } = {}) {
  return h('div', { class: 'bf-photos' }, photos.map((p, i) => h('span', { class: 'bf-photo' },
    h('button', { type: 'button', class: 'bf-photo__vignette', 'aria-label': `Agrandir : ${titre} ${i + 1}`, onclick: () => agrandir(p.url, `${titre} | photo ${i + 1}`) },
      h('img', { src: p.url, alt: `${titre} ${i + 1}`, loading: 'lazy' })),
    retirer ? h('button', { type: 'button', class: 'bf-photo__retirer', 'aria-label': `Retirer : ${titre} ${i + 1}`, title: 'Retirer', onclick: () => retirer(p) }, '×') : null)));
}
