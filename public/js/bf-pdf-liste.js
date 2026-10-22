// PDF d'une version archivée de la liste de prix d'un sous-traitant (ADR-065).
// Le PDF est produit dans le navigateur à partir de la copie figée en base (listes_prix_versions) :
// même version = même contenu. L'empreinte SHA-256 de la version est imprimée au bas de chaque page.
// Librairie : pdf-lib 1.17.1 (MIT), copiée dans public/js/vendor : rien ne sort vers un tiers.
import { PDFDocument, StandardFonts, rgb } from './vendor/pdf-lib-1.17.1.esm.min.js';
import { UNITES, prix, phraseChangement } from './bf-liste-prix.js?v=0.4.0';

export { phraseChangement };

const VERT = rgb(0.12, 0.65, 0.29);
const ENCRE = rgb(0.08, 0.13, 0.1);
const GRIS = rgb(0.34, 0.39, 0.36);
const LIGNE = rgb(0.88, 0.9, 0.89);

// Les polices standard du PDF (WinAnsi) couvrent le français ; on remplace le reste.
export function texte(v) {
  return String(v ?? '')
    .replace(/[\u202F\u2009]/g, '\u00A0')
    .replace(/[\u2192\u21D2]/g, '->')
    .replace(/[^\x20-\x7E\xA0-\xFF\u2018\u2019\u201C\u201D\u2013\u2022\u2026\u20AC\u0152\u0153]/g, '?');
}

export const dateHeure = (d) => new Date(d).toLocaleString('fr-CA', {
  timeZone: 'America/Toronto', day: 'numeric', month: 'long', year: 'numeric', hour: '2-digit', minute: '2-digit',
});

function couper(mots, police, taille, largeur) {
  const lignes = [];
  let courante = '';
  for (const m of String(mots).split(/\s+/)) {
    const essai = courante ? `${courante} ${m}` : m;
    if (police.widthOfTextAtSize(essai, taille) <= largeur || !courante) courante = essai;
    else { lignes.push(courante); courante = m; }
  }
  if (courante) lignes.push(courante);
  return lignes;
}

// fournisseur : { nom, licence_rbq?, responsable_nom? } ; version : une ligne de listes_prix_versions
export async function pdfListe(fournisseur, version) {
  const doc = await PDFDocument.create();
  const normal = await doc.embedFont(StandardFonts.Helvetica);
  const gras = await doc.embedFont(StandardFonts.HelveticaBold);
  const titre = `Liste de prix | ${fournisseur.nom} | version ${version.numero}`;
  doc.setTitle(texte(titre));
  doc.setAuthor('Groupe Belleflamme | Division Ventilation/Climatisation');
  doc.setSubject(texte(`Empreinte SHA-256 : ${version.empreinte}`));
  doc.setProducer('HVAC Belleflamme');
  doc.setCreator('HVAC Belleflamme');
  doc.setCreationDate(new Date(version.cree_le));
  doc.setModificationDate(new Date(version.cree_le));

  const L = 612; const H = 792; const M = 48; const largeur = L - 2 * M;
  let page; let y;
  const nouvellePage = () => { page = doc.addPage([L, H]); y = H - M; };
  const place = (h) => { if (y - h < M + 30) nouvellePage(); };
  const ecrire = (t, { x = M, taille = 10, police = normal, couleur = ENCRE, max = largeur, interligne = 1.35 } = {}) => {
    for (const l of couper(texte(t), police, taille, max)) {
      place(taille * interligne);
      page.drawText(l, { x, y: y - taille, size: taille, font: police, color: couleur });
      y -= taille * interligne;
    }
  };

  nouvellePage();
  page.drawRectangle({ x: 0, y: H - 6, width: L, height: 6, color: VERT });
  ecrire('GROUPE BELLEFLAMME | DIVISION VENTILATION/CLIMATISATION', { taille: 9, police: gras, couleur: VERT });
  y -= 4;
  ecrire(`Liste de prix | ${fournisseur.nom}`, { taille: 18, police: gras });
  const fiche = [fournisseur.licence_rbq ? `RBQ ${fournisseur.licence_rbq}` : null,
    fournisseur.responsable_nom ? `Responsable : ${fournisseur.responsable_nom}` : null].filter(Boolean).join(' | ');
  if (fiche) ecrire(fiche, { couleur: GRIS });
  y -= 6;
  ecrire(`Version ${version.numero} | ${dateHeure(version.cree_le)}`, { taille: 12, police: gras });
  ecrire(`Faite par : ${version.auteur_nom} (${version.par_sous_traitant ? 'sous-traitant' : 'Belleflamme'}) | ${version.motif}`, { couleur: GRIS });

  const chg = version.changements || [];
  if (chg.length) {
    y -= 8;
    ecrire(`Changements depuis la version ${version.numero - 1} (${chg.length})`, { taille: 11, police: gras });
    for (const c of chg) ecrire(`• ${phraseChangement(c)}`, { x: M + 8, max: largeur - 8 });
  }

  // Tableau : catégorie, puis Code | Travail | Unité | Coût du sous-traitant
  const col = { code: M, nom: M + 128, unite: M + 372, cout: L - M };
  const entete = () => {
    place(22);
    page.drawRectangle({ x: M, y: y - 16, width: largeur, height: 18, color: rgb(0.85, 0.95, 0.88) });
    for (const [k, t] of [['code', 'CODE'], ['nom', 'TRAVAIL'], ['unite', 'UNITÉ']]) {
      page.drawText(texte(t), { x: col[k] + 4, y: y - 11, size: 8, font: gras, color: ENCRE });
    }
    const w = gras.widthOfTextAtSize('COÛT', 8);
    page.drawText(texte('COÛT'), { x: col.cout - w - 4, y: y - 11, size: 8, font: gras, color: ENCRE });
    y -= 20;
  };
  y -= 10;
  ecrire(`Travaux et prix (${version.nb_lignes})`, { taille: 11, police: gras });
  let categorie = null;
  for (const l of version.lignes || []) {
    if (l.categorie !== categorie) {
      categorie = l.categorie;
      y -= 6; place(40);
      ecrire(String(categorie || 'Autres').toUpperCase(), { taille: 9, police: gras, couleur: VERT });
      entete();
    }
    const noms = couper(texte(l.nom), normal, 9, col.unite - col.nom - 10);
    const h = Math.max(1, noms.length) * 12 + 4;
    if (y - h < M + 30) { nouvellePage(); entete(); }
    page.drawText(texte(l.code), { x: col.code + 4, y: y - 10, size: 8, font: gras, color: ENCRE });
    noms.forEach((n, i) => page.drawText(n, { x: col.nom + 4, y: y - 10 - i * 12, size: 9, font: normal, color: ENCRE }));
    page.drawText(texte(UNITES[l.unite] || l.unite || 'forfait'), { x: col.unite + 4, y: y - 10, size: 9, font: normal, color: GRIS });
    const p = texte(prix(l.cout_cents));
    const police = l.cout_cents === null || l.cout_cents === undefined ? normal : gras;
    page.drawText(p, { x: col.cout - police.widthOfTextAtSize(p, 9) - 4, y: y - 10, size: 9, font: police, color: ENCRE });
    page.drawLine({ start: { x: M, y: y - h + 2 }, end: { x: L - M, y: y - h + 2 }, thickness: 0.5, color: LIGNE });
    y -= h;
  }

  // Pied de chaque page : empreinte et numéro de page
  const pages = doc.getPages();
  pages.forEach((pg, i) => {
    pg.drawText(texte(`Copie fidèle de la version ${version.numero} archivée au registre. Toute modification de la liste crée une nouvelle version.`),
      { x: M, y: M - 8, size: 7, font: normal, color: GRIS });
    pg.drawText(texte(`Empreinte SHA-256 : ${version.empreinte}`), { x: M, y: M - 18, size: 7, font: normal, color: GRIS });
    const n = texte(`Page ${i + 1} / ${pages.length}`);
    pg.drawText(n, { x: L - M - normal.widthOfTextAtSize(n, 7), y: M - 18, size: 7, font: normal, color: GRIS });
  });
  return doc.save();
}

// Nom de fichier : liste-prix_<compagnie>_v<numéro>_<date>.pdf
export function nomFichier(fournisseur, version) {
  const base = String(fournisseur.nom || 'sous-traitant').normalize('NFD').replace(/[\u0300-\u036f]/g, '')
    .replace(/[^A-Za-z0-9]+/g, '-').replace(/^-|-$/g, '').toLowerCase();
  const jour = new Date(version.cree_le).toLocaleDateString('en-CA', { timeZone: 'America/Toronto' });
  return `liste-prix_${base}_v${version.numero}_${jour}.pdf`;
}
