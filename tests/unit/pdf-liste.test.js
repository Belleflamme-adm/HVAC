import { test } from 'node:test';
import assert from 'node:assert/strict';
import { PDFDocument } from '../../public/js/vendor/pdf-lib-1.17.1.esm.min.js';
import { pdfListe, texte, phraseChangement, nomFichier } from '../../public/js/bf-pdf-liste.js';

const version = {
  numero: 3, cree_le: '2026-10-22T18:05:00Z', auteur_nom: 'Martin Lavoie', par_sous_traitant: true, motif: 'Prix modifiés par le sous-traitant',
  empreinte: 'a'.repeat(64), nb_lignes: 40, nb_changements: 1,
  changements: [{ type: 'prix', code: 'INST-MURAL-1T-12', nom: 'Murale 1 tête', avant: 120000, apres: 130000 }],
  lignes: Array.from({ length: 40 }, (_, i) => ({ code: `INST-${i}`, nom: `Installation numéro ${i} avec une description assez longue pour être coupée sur deux lignes`,
    categorie: i < 20 ? 'Thermopompe murale | installation neuve' : 'Biénergie', unite: 'forfait', cout_cents: i % 3 ? 100000 + i : null })),
};

test('PDF de la liste : document valide, plusieurs pages, titre et date de la version', async () => {
  const octets = await pdfListe({ nom: 'Clim Laurentides', licence_rbq: '1234-5678-90', responsable_nom: 'Martin Lavoie' }, version);
  assert.equal(Buffer.from(octets.slice(0, 5)).toString(), '%PDF-');
  const doc = await PDFDocument.load(octets);
  assert.ok(doc.getPageCount() >= 2, 'tableau sur plusieurs pages');
  assert.match(doc.getTitle(), /Clim Laurentides \| version 3/);
  assert.equal(doc.getCreationDate().toISOString(), '2026-10-22T18:05:00.000Z');
  assert.match(doc.getSubject(), /a{64}/);
});

test('PDF : texte compatible avec les polices standard, changements lisibles, nom de fichier', () => {
  assert.equal(texte('Biénergie → 1 200,00 $'), 'Biénergie -> 1 200,00 $');
  assert.equal(texte('≥ 3'), '? 3');
  assert.match(phraseChangement(version.changements[0]), /^Prix : INST-MURAL-1T-12 \| Murale 1 tête : 1\s200,00\s\$ -> 1\s300,00\s\$$/);
  assert.match(phraseChangement({ type: 'ajout', code: 'A', nom: 'x', apres: null }), /^Ajouté : A \| x$/);
  assert.equal(nomFichier({ nom: 'Froid Centre-du-Québec (FICTIF)' }, version), 'liste-prix_froid-centre-du-quebec-fictif_v3_2026-10-22.pdf');
});
