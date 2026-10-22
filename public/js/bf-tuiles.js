// Tuiles d'accueil (équivalent bf-tuiles chez Mike). Ordre de livraison : ADR-013 et Phase 3.
export const TUILES_HVAC = [
  { cle: 'clients',     titre: 'Clients',              href: '/clients',     etat: 'actif' },
  { cle: 'devis',       titre: 'Devis',                href: '/devis',       etat: 'actif' },
  { cle: 'leads',       titre: 'Leads',                href: '/leads',       etat: 'phase3' },
  { cle: 'inspections', titre: 'Inspections',          href: '/inspections', etat: 'phase3' },
  { cle: 'projets',     titre: 'Projets (Macro)',      href: '/projets',     etat: 'phase3' },
  { cle: 'bt',          titre: 'Bons de travail',      href: '/bt',          etat: 'phase3' },
  { cle: 'catalogue',   titre: 'Catalogue et kits',    href: '/catalogue',   etat: 'phase3' },
  { cle: 'asv',         titre: 'Appels de service',    href: '/asv',         etat: 'phase3' },
  { cle: 'subventions', titre: 'Subventions LogisVert', href: '/subventions', etat: 'phase3' },
  { cle: 'installation', titre: 'Grille d\'installation', href: '/installation-grille', etat: 'actif' },
  { cle: 'factures',    titre: 'Facturation',          href: '/factures',    etat: 'phase3' },
  { cle: 'assistant',   titre: 'Assistant ventilation', href: '/assistant-ventilation', etat: 'phase3' },
];

export function rendreTuiles(conteneur, tuiles = TUILES_HVAC) {
  conteneur.replaceChildren(...tuiles.map((t) => {
    const a = document.createElement(t.etat === 'actif' ? 'a' : 'div');
    a.className = `bf-tuile${t.etat === 'actif' ? '' : ' bf-tuile--bientot'}`;
    if (t.etat === 'actif') a.href = t.href;
    const titre = document.createElement('span');
    titre.className = 'bf-tuile__titre';
    titre.textContent = t.titre;
    a.append(titre);
    if (t.etat !== 'actif') {
      const etiquette = document.createElement('span');
      etiquette.className = 'bf-tuile__etat';
      etiquette.textContent = 'Bientôt';
      a.append(etiquette);
    }
    return a;
  }));
}
