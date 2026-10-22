// Tuiles d'accueil (équivalent bf-tuiles chez Mike) : cartes en liste, icône sur fond menthe,
// titre condensé, description, chevron ; un groupe s'ouvre en fenêtre flottante (comme « Opération »).
// Recentrage (ADR-055) : notre app = CRM des leads + espace sous-traitants.
// Les modules qui existent déjà chez Mike sont « en veille » : visibles, grisés, inactifs.
// Leur code est conservé ; pour en réactiver un, remettre etat: 'actif'.
import { ouvrirFenetre } from './bf-fenetre.js?v=0.4.0';

export const TUILES_HVAC = [
  { cle: 'leads',       titre: 'Leads (CRM)',          href: '/leads',       etat: 'actif', icone: '🎯', desc: 'Leads Google · Facebook (via Monday) · tour de rôle · appels, courriels, textos' },
  { cle: 'clients',     titre: 'Clients',              href: '/clients',     etat: 'actif', icone: '👤', desc: 'Fiches clients · lieux d\'installation' },
  { cle: 'devis',       titre: 'Devis',                href: '/devis',       etat: 'veille', icone: '📄', desc: 'Dans l\'app de Mike : Devis / Facture / Extra' },
  { cle: 'inspections', titre: 'Pré-installation',     href: '/inspections', etat: 'veille', icone: '📋', desc: 'Dans l\'app de Mike : formulaire Pré-install Ventilation' },
  { cle: 'projets',     titre: 'Projets (Macro)',      href: '/projets',     etat: 'veille', icone: '🏗️', desc: 'Dans l\'app de Mike : Macro / Projets' },
  { cle: 'bt',          titre: 'Bons de travail et BC', href: '/bt',         etat: 'veille', icone: '📦', desc: 'Dans l\'app de Mike : gestion d\'inventaire' },
  { cle: 'catalogue',   titre: 'Catalogue et kits',    href: '/catalogue',   etat: 'veille', icone: '🗂️', desc: 'Dans l\'app de Mike : catalogue produits' },
  { cle: 'asv',         titre: 'Appels de service',    href: '/asv',         etat: 'veille', icone: '📞', desc: 'Dans l\'app de Mike : appels de service' },
  { cle: 'subventions', titre: 'Subventions LogisVert', href: '/subventions', etat: 'veille', icone: '🌱', desc: 'Dans l\'app de Mike : documents importants' },
  { cle: 'factures',    titre: 'Facturation',          href: '/factures',    etat: 'veille', icone: '💰', desc: 'Dans l\'app de Mike : comptabilité' },
  { cle: 'assistant',   titre: 'Assistant ventilation', href: '/assistant-ventilation', etat: 'veille', icone: '🌀', desc: 'Dans l\'app de Mike : assistant-ventilation' },
];

export const LIBELLES_ETAT = { construction: 'En construction', veille: 'En veille | app de Mike' };

const TUILES_SOUS_TRAITANT = [
  { cle: 'territoire', titre: 'Mon territoire', href: '/territoire', etat: 'actif', icone: '🗺️', desc: 'Villes où je vais, où je ne vais pas, suppléments' },
  { cle: 'prix', titre: 'Ma liste de prix', href: '/mes-prix', etat: 'construction', icone: '🧾', desc: 'Mes prix par type de travail, envoyés à Belleflamme' },
  { cle: 'disponibilites', titre: 'Mes disponibilités', href: '/disponibilites', etat: 'actif', icone: '📅', desc: 'Les journées où je suis disponible' },
  { cle: 'jobs', titre: 'Mes jobs', href: '/jobs', etat: 'veille', icone: '🧰', desc: 'Jobs planifiées (bons de travail)' },
];

// Directeur des opérations : sous-traitants, accès, territoires, listes de prix
const TUILES_PLANIFICATION = [
  { cle: 'sous-traitants', titre: 'Sous-traitants', href: '/sous-traitants', etat: 'actif', icone: '🛠️', desc: 'Inscrire un sous-traitant · donner un accès' },
  { cle: 'territoires', titre: 'Territoires', href: '/territoire', etat: 'actif', icone: '🗺️', desc: 'Carte de chaque sous-traitant · sous-traitants principaux' },
  { cle: 'installation', titre: 'Listes de prix des sous-traitants', href: '/installation-grille', etat: 'actif', icone: '🧾', desc: 'Prix par type de travail · marge · suppléments' },
  { cle: 'disponibilites', titre: 'Disponibilités', href: '/disponibilites', etat: 'actif', icone: '📅', desc: 'Calendrier des sous-traitants' },
];

const RAPIDITE = { cle: 'rapidite', titre: 'Rapidité des vendeurs', href: '/crm-rapidite', etat: 'actif', icone: '⏱️', desc: 'Tableau de quantification · bon, moyen, à améliorer · tour de rôle' };

const estPlanif = (user) => ['Admin tout', 'Direction', 'Coordonnateur'].includes(user?.role);
const voitBoard = (user) => ['Admin tout', 'Direction', 'Gérant de succursale', 'Coordonnateur'].includes(user?.role);

// Liste à plat (menus, tests) : modules actifs d'abord, ceux en veille à la fin
export function tuilesPour(user) {
  if (user?.sousTraitantId) return TUILES_SOUS_TRAITANT;
  const toutes = estPlanif(user) ? [...TUILES_HVAC, ...TUILES_PLANIFICATION] : TUILES_HVAC;
  return [...toutes.filter((t) => t.etat !== 'veille'), ...toutes.filter((t) => t.etat === 'veille')];
}

// Accueil : tuiles directes et groupes (fenêtres), selon le rôle
export function accueilPour(user) {
  if (user?.sousTraitantId) return TUILES_SOUS_TRAITANT.filter((t) => t.etat !== 'veille');
  const veille = TUILES_HVAC.filter((t) => t.etat === 'veille');
  const ventes = [TUILES_HVAC[0], TUILES_HVAC[1], ...(voitBoard(user) ? [RAPIDITE] : [])];
  const liste = [
    { cle: 'ventes', titre: 'Ventes HVAC', icone: '📈', desc: 'Leads · clients · rapidité des vendeurs', groupe: ventes },
  ];
  if (estPlanif(user)) liste.push({ cle: 'operations', titre: 'Sous-traitants', icone: '🛠️', desc: 'Sous-traitants · accès · territoires · listes de prix · disponibilités', groupe: TUILES_PLANIFICATION });
  liste.push({ cle: 'veille', titre: 'Dans l\'app de Mike', icone: '💤', desc: 'Devis, pré-installation, facturation, projets... : en veille ici, on utilise ceux de Mike', groupe: veille, veille: true });
  return liste;
}

function carte(t) {
  const actif = t.groupe || t.etat === 'actif';
  const el = document.createElement(t.groupe ? 'button' : actif ? 'a' : 'div');
  el.className = `bf-tuile${actif && !t.veille ? '' : ` bf-tuile--${t.veille ? 'veille-groupe' : t.etat}`}`;
  if (t.groupe) { el.type = 'button'; el.addEventListener('click', () => ouvrirFenetre(t.titre, (corps) => rendreTuiles(corps, t.groupe))); }
  else if (actif) el.href = t.href;
  else el.setAttribute('aria-disabled', 'true');
  const icone = document.createElement('span');
  icone.className = 'bf-tuile__icone';
  icone.setAttribute('aria-hidden', 'true');
  icone.textContent = t.icone || '•';
  const texte = document.createElement('span');
  texte.className = 'bf-tuile__texte';
  const titre = document.createElement('span');
  titre.className = 'bf-tuile__titre';
  titre.textContent = t.titre;
  const desc = document.createElement('span');
  desc.className = 'bf-tuile__desc';
  desc.textContent = !actif ? `${LIBELLES_ETAT[t.etat] || 'Bientôt'} · ${t.desc || ''}` : (t.desc || '');
  texte.append(titre, desc);
  const fleche = document.createElement('span');
  fleche.className = 'bf-tuile__fleche';
  fleche.setAttribute('aria-hidden', 'true');
  fleche.textContent = actif ? '›' : '';
  el.append(icone, texte, fleche);
  return el;
}

export function rendreTuiles(conteneur, tuiles = TUILES_HVAC) {
  conteneur.replaceChildren(...tuiles.map(carte));
}
