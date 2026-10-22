// Tuiles d'accueil (équivalent bf-tuiles chez Mike).
// Recentrage (ADR-055) : notre app = CRM des leads + espace sous-traitants.
// Les modules qui existent déjà chez Mike (devis, facturation, BT/BC, projets...) sont « en veille » :
// visibles, grisés, inactifs. Leur code est conservé ; pour en réactiver un, remettre etat: 'actif'.
export const TUILES_HVAC = [
  { cle: 'leads',       titre: 'Leads (CRM)',          href: '/leads',       etat: 'construction' },
  { cle: 'clients',     titre: 'Clients',              href: '/clients',     etat: 'actif' },
  { cle: 'devis',       titre: 'Devis',                href: '/devis',       etat: 'veille' },
  { cle: 'inspections', titre: 'Pré-installation',     href: '/inspections', etat: 'veille' },
  { cle: 'projets',     titre: 'Projets (Macro)',      href: '/projets',     etat: 'veille' },
  { cle: 'bt',          titre: 'Bons de travail et BC', href: '/bt',         etat: 'veille' },
  { cle: 'catalogue',   titre: 'Catalogue et kits',    href: '/catalogue',   etat: 'veille' },
  { cle: 'asv',         titre: 'Appels de service',    href: '/asv',         etat: 'veille' },
  { cle: 'subventions', titre: 'Subventions LogisVert', href: '/subventions', etat: 'veille' },
  { cle: 'factures',    titre: 'Facturation',          href: '/factures',    etat: 'veille' },
  { cle: 'assistant',   titre: 'Assistant ventilation', href: '/assistant-ventilation', etat: 'veille' },
];

export const LIBELLES_ETAT = { construction: 'En construction', veille: 'En veille | app de Mike' };

const TUILES_SOUS_TRAITANT = [
  { cle: 'territoire', titre: 'Mon territoire', href: '/territoire', etat: 'actif' },
  { cle: 'prix', titre: 'Ma liste de prix', href: '/mes-prix', etat: 'construction' },
  { cle: 'disponibilites', titre: 'Mes disponibilités', href: '/disponibilites', etat: 'actif' },
  { cle: 'jobs', titre: 'Mes jobs', href: '/jobs', etat: 'veille' },
];

// Directeur des opérations : sous-traitants, accès, territoires, listes de prix
const TUILES_PLANIFICATION = [
  { cle: 'sous-traitants', titre: 'Sous-traitants', href: '/sous-traitants', etat: 'actif' },
  { cle: 'territoires', titre: 'Territoires', href: '/territoire', etat: 'actif' },
  { cle: 'installation', titre: 'Listes de prix des sous-traitants', href: '/installation-grille', etat: 'actif' },
  { cle: 'disponibilites', titre: 'Disponibilités', href: '/disponibilites', etat: 'actif' },
];

export function tuilesPour(user) {
  if (user?.sousTraitantId) return TUILES_SOUS_TRAITANT;
  const planif = ['Admin tout', 'Direction', 'Coordonnateur'].includes(user?.role);
  // Les modules actifs d'abord, ceux en veille à la fin
  const toutes = planif ? [...TUILES_HVAC, ...TUILES_PLANIFICATION] : TUILES_HVAC;
  return [...toutes.filter((t) => t.etat !== 'veille'), ...toutes.filter((t) => t.etat === 'veille')];
}

export function rendreTuiles(conteneur, tuiles = TUILES_HVAC) {
  conteneur.replaceChildren(...tuiles.map((t) => {
    const a = document.createElement(t.etat === 'actif' ? 'a' : 'div');
    a.className = `bf-tuile${t.etat === 'actif' ? '' : ` bf-tuile--${t.etat}`}`;
    if (t.etat !== 'actif') a.setAttribute('aria-disabled', 'true');
    if (t.etat === 'actif') a.href = t.href;
    const titre = document.createElement('span');
    titre.className = 'bf-tuile__titre';
    titre.textContent = t.titre;
    a.append(titre);
    if (t.etat !== 'actif') {
      const etiquette = document.createElement('span');
      etiquette.className = 'bf-tuile__etat';
      etiquette.textContent = LIBELLES_ETAT[t.etat] || 'Bientôt';
      a.append(etiquette);
    }
    return a;
  }));
}
