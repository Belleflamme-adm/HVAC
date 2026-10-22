// Registre des versions de la liste de prix d'un sous-traitant (ADR-065).
// La version la plus récente en premier : date, heure, auteur, changements, PDF.
// Utilisé dans « Ma liste de prix » (sous-traitant) et dans « Listes de prix des sous-traitants » (Belleflamme).
import { api } from './bf-api.js?v=0.4.0';
import { h, remplir } from './bf-dom.js?v=0.4.0';
import { phraseChangement } from './bf-liste-prix.js?v=0.4.0';

const dateHeure = (d) => new Date(d).toLocaleString('fr-CA', {
  timeZone: 'America/Toronto', day: 'numeric', month: 'long', year: 'numeric', hour: '2-digit', minute: '2-digit',
});

async function telechargerPdf(fournisseurId, version, bouton) {
  const texte = bouton.textContent;
  bouton.disabled = true; bouton.textContent = 'Préparation…';
  try {
    // La librairie PDF (500 ko) se charge seulement quand on en a besoin
    const [{ pdfListe, nomFichier }, fiche] = await Promise.all([
      import('./bf-pdf-liste.js?v=0.4.0'), api.get('sous-traitant', { id: fournisseurId }).catch(() => ({ nom: 'Sous-traitant' })),
    ]);
    const octets = await pdfListe(fiche, version);
    const url = URL.createObjectURL(new Blob([octets], { type: 'application/pdf' }));
    const a = h('a', { href: url, download: nomFichier(fiche, version) });
    document.body.append(a); a.click(); a.remove();
    setTimeout(() => URL.revokeObjectURL(url), 60000);
  } finally { bouton.disabled = false; bouton.textContent = texte; }
}

export function registreListe(fournisseurId, { titre = 'Registre des listes de prix' } = {}) {
  const zone = h('section', { class: 'bf-form bf-registre', 'aria-label': titre });

  async function charger() {
    remplir(zone, h('h2', {}, titre), h('p', { class: 'bf-muet' }, 'Chargement…'));
    let r;
    try { r = await api.get('listes-prix-versions', { fournisseur: fournisseurId }); }
    catch (e) { remplir(zone, h('h2', {}, titre), h('p', { class: 'bf-message' }, e.message)); return; }
    const { versions, n30, seuil, alerte, jours } = r;
    remplir(zone,
      h('h2', {}, titre),
      h('p', { class: 'bf-muet' }, 'Chaque enregistrement qui change la liste crée une version archivée, impossible à modifier ou à effacer. '
        + 'La plus récente est en premier. Le PDF reproduit exactement la version archivée.'),
      alerte ? h('p', { class: 'bf-message bf-message--alerte', role: 'status' },
        h('strong', {}, `${n30} modifications par le sous-traitant en ${jours} jours`), ` (seuil d'alerte : ${seuil}). Simon et Mike en sont avisés.`)
        : h('p', { class: 'bf-muet' }, `${n30} modification(s) par le sous-traitant dans les ${jours} derniers jours.`),
      versions.length ? h('ol', { class: 'bf-registre__liste', reversed: true }, versions.map((v, i) => {
        const details = h('div', { class: 'bf-registre__details', hidden: true },
          v.changements.length ? h('ul', {}, v.changements.map((c) => h('li', {}, phraseChangement(c))))
            : h('p', { class: 'bf-muet' }, `Première version : ${v.nb_lignes} travaux.`),
          h('p', { class: 'bf-muet bf-registre__empreinte' }, `Empreinte SHA-256 : ${v.empreinte}`));
        const voir = h('button', { class: 'bf-lien', type: 'button', 'aria-expanded': 'false', onclick: () => {
          details.hidden = !details.hidden; voir.setAttribute('aria-expanded', String(!details.hidden));
          voir.textContent = details.hidden ? 'Voir les changements' : 'Masquer les changements';
        } }, 'Voir les changements');
        const pdf = h('button', { class: 'bf-bouton bf-bouton--discret', type: 'button' }, 'Télécharger le PDF');
        pdf.addEventListener('click', () => telechargerPdf(fournisseurId, v, pdf));
        return h('li', { class: `bf-registre__version${i === 0 ? ' bf-registre__version--courante' : ''}` },
          h('div', { class: 'bf-registre__tete' },
            h('strong', {}, `Version ${v.numero}`),
            i === 0 ? h('span', { class: 'bf-pastille bf-pastille--accepte' }, 'En vigueur') : null,
            h('span', {}, dateHeure(v.cree_le)),
            h('span', { class: 'bf-muet' }, `par ${v.auteur_nom} (${v.par_sous_traitant ? 'sous-traitant' : 'Belleflamme'})`)),
          h('div', { class: 'bf-muet' }, `${v.motif} | ${v.nb_lignes} travaux | `
            + (v.changements.length ? `${v.nb_changements} changement(s)` : 'première version')),
          h('div', { class: 'bf-actions' }, pdf, voir),
          details);
      })) : h('p', { class: 'bf-muet' }, 'Aucune version pour l\'instant : la première sera créée au premier enregistrement.'));
  }
  charger();
  return { el: zone, recharger: charger };
}
