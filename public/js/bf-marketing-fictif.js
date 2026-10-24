// Marketing FICTIF pour le tableau marketing (ADR-072). Aucune donnée réelle.
// À la greffe : leads de Monday et de notre CRM (source, campagne, ville, type, résultat), dépenses et auditoires
// tirés des rapports Facebook (Meta) et Google Ads.
// Loi 25 : le genre et l'âge ne sont JAMAIS inscrits au dossier d'un lead. On utilise seulement les rapports
// d'auditoire agrégés que fournissent les plateformes (combien de leads par tranche, pas qui).
import { SUCCURSALES, moisJusqua } from './bf-ventes-fictives.js?v=0.4.0';

export const SOURCES = {
  facebook: { libelle: 'Facebook', couleur: 'var(--d-s1)', payante: true },
  google: { libelle: 'Google', couleur: 'var(--d-s2)', payante: true },
  site_web: { libelle: 'Site web', couleur: 'var(--d-s3)', payante: true },
  reference: { libelle: 'Référence', couleur: 'var(--d-s4)', payante: false },
  instagram: { libelle: 'Instagram', couleur: 'var(--d-s5)', payante: true },
  autres: { libelle: 'Autres (téléphone, salon, magasin)', couleur: 'var(--d-s6)', payante: true },
};

export const TYPES_DEMANDE = { mural_simple: 'Murale simple', mural_multi: 'Murale multi', central: 'Système central', bienergie: 'Biénergie' };
const VALEUR_TYPE = { mural_simple: 520000, mural_multi: 1050000, central: 1500000, bienergie: 1480000 };   // vente moyenne en cents

// Saison par mois (janv. -> déc.) : climatisation au printemps-été, chauffage à l'automne
const SAISON_CLIM = [0.2, 0.2, 0.35, 0.8, 1.4, 1.7, 1.6, 1.1, 0.5, 0.25, 0.2, 0.2];
const SAISON_CHAUFF = [0.9, 0.7, 0.6, 0.5, 0.35, 0.3, 0.35, 0.6, 1.3, 1.6, 1.4, 1.1];
const PLAT = Array(12).fill(1);

// Campagnes fictives : budget mensuel moyen (cents), coût par clic, taux clic -> lead, qualité (conversion), ciblage
export const CAMPAGNES = [
  { code: 'fb-tp-automne', source: 'facebook', nom: 'Thermopompe automne', budget: 450000, cpc: 220, conv: 0.04, qualite: 0.85, saison: SAISON_CHAUFF,
    types: { mural_simple: 4, mural_multi: 3, central: 1, bienergie: 2 }, geo: { HO: 1, RO: 1.2, ST: 1, GA: 0.8, DR: 0.7 } },
  { code: 'fb-clim-ete', source: 'facebook', nom: 'Climatisation été', budget: 350000, cpc: 180, conv: 0.04, qualite: 0.75, saison: SAISON_CLIM,
    types: { mural_simple: 6, mural_multi: 2, central: 1, bienergie: 0.3 }, geo: { HO: 1, RO: 1.4, ST: 0.8, GA: 0.9, DR: 0.6 } },
  { code: 'fb-logisvert', source: 'facebook', nom: 'Subvention LogisVert', budget: 240000, cpc: 230, conv: 0.046, qualite: 1.05, saison: PLAT,
    types: { mural_simple: 2, mural_multi: 2, central: 2, bienergie: 3 }, geo: { HO: 1, RO: 1, ST: 0.9, GA: 1.1, DR: 1.2 } },
  { code: 'g-recherche-tp', source: 'google', nom: 'Recherche « thermopompe »', budget: 510000, cpc: 520, conv: 0.05, qualite: 1.25, saison: SAISON_CHAUFF,
    types: { mural_simple: 3, mural_multi: 3, central: 2, bienergie: 2 }, geo: { HO: 1, RO: 1.3, ST: 0.8, GA: 1.2, DR: 0.9 } },
  { code: 'g-recherche-clim', source: 'google', nom: 'Recherche « climatiseur »', budget: 290000, cpc: 450, conv: 0.05, qualite: 1.1, saison: SAISON_CLIM,
    types: { mural_simple: 6, mural_multi: 2, central: 1.5, bienergie: 0.2 }, geo: { HO: 1, RO: 1.3, ST: 0.7, GA: 1.1, DR: 0.8 } },
  { code: 'g-pmax', source: 'google', nom: 'Performance Max', budget: 260000, cpc: 140, conv: 0.02, qualite: 0.6, saison: PLAT,
    types: { mural_simple: 4, mural_multi: 2, central: 1, bienergie: 1 }, geo: { HO: 1, RO: 1, ST: 1, GA: 1, DR: 1 } },
  { code: 'ig-reels', source: 'instagram', nom: 'Reels d\'installations', budget: 145000, cpc: 150, conv: 0.02, qualite: 0.55, saison: PLAT,
    types: { mural_simple: 5, mural_multi: 3, central: 0.5, bienergie: 0.3 }, geo: { HO: 0.8, RO: 1.3, ST: 1.4, GA: 0.6, DR: 0.4 } },
  { code: 'web-seo', source: 'site_web', nom: 'Référencement et contenu du site', budget: 70000, cpc: 0, leadsMois: 22, qualite: 1.15, saison: PLAT,
    types: { mural_simple: 3, mural_multi: 3, central: 2, bienergie: 2 }, geo: { HO: 1, RO: 1, ST: 1, GA: 1, DR: 1 } },
  { code: 'ref-bouche', source: 'reference', nom: 'Bouche-à-oreille et clients satisfaits', budget: 0, cpc: 0, leadsMois: 24, qualite: 1.7, saison: PLAT,
    types: { mural_simple: 3, mural_multi: 3, central: 2, bienergie: 2 }, geo: { HO: 1.3, RO: 1, ST: 1.2, GA: 0.8, DR: 0.9 } },
  { code: 'autres-salon', source: 'autres', nom: 'Salon de l\'habitation (mars)', budget: 0, fixe: { '03': 450000 }, cpc: 0, leadsFixe: { '03': 46 }, qualite: 0.9, saison: PLAT,
    types: { mural_simple: 3, mural_multi: 3, central: 2, bienergie: 2 }, geo: { HO: 1.5, RO: 1.2, ST: 0.6, GA: 0.3, DR: 0.3 } },
  { code: 'autres-tel', source: 'autres', nom: 'Appels et visites en magasin', budget: 0, cpc: 0, leadsMois: 12, qualite: 1.3, saison: PLAT,
    types: { mural_simple: 3, mural_multi: 2, central: 2, bienergie: 2 }, geo: { HO: 1.4, RO: 1, ST: 1, GA: 1, DR: 1 } },
];

// Auditoire des plateformes (agrégé) : poids par genre et par tranche d'âge
export const GENRES = { femmes: 'Femmes', hommes: 'Hommes', inconnu: 'Non précisé' };
export const AGES = ['18-24', '25-34', '35-44', '45-54', '55-64', '65+'];
const AUDITOIRE = {
  facebook: { genre: { femmes: 0.56, hommes: 0.41, inconnu: 0.03 }, age: [0.03, 0.14, 0.22, 0.24, 0.22, 0.15] },
  instagram: { genre: { femmes: 0.61, hommes: 0.36, inconnu: 0.03 }, age: [0.1, 0.33, 0.3, 0.17, 0.08, 0.02] },
  google: { genre: { femmes: 0.38, hommes: 0.55, inconnu: 0.07 }, age: [0.04, 0.17, 0.25, 0.24, 0.19, 0.11] },
};
// Conversion relative par tranche d'âge (les 35-64 ans, souvent propriétaires, achètent plus)
const CONV_AGE = [0.3, 0.7, 1.15, 1.25, 1.15, 0.85];

const JOURS = [0.85, 1.15, 1.1, 1.05, 1.0, 0.8, 0.9];                       // dim. -> sam.
const HEURES = [0.1, 0.05, 0.03, 0.03, 0.05, 0.2, 0.6, 1.1, 1.3, 1.2, 1.1, 1.2, 1.3, 1.2, 1.1, 1.1, 1.2, 1.4, 1.7, 1.9, 1.8, 1.4, 0.8, 0.3];

function hasard(graine) {
  let a = graine >>> 0;
  return () => { a = (a + 0x6d2b79f5) >>> 0; let t = a; t = Math.imul(t ^ (t >>> 15), t | 1); t ^= t + Math.imul(t ^ (t >>> 7), t | 61); return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
}
const tirer = (r, paires) => {
  const total = paires.reduce((s, [, p]) => s + p, 0);
  let x = r() * total;
  for (const [v, p] of paires) { x -= p; if (x <= 0) return v; }
  return paires[paires.length - 1][0];
};

// 24 mois : { leads, depenses, auditoire }
// leads : { mois, jour_semaine, heure, source, campagne, type, succursale, municipalite, contacte, visite, vendu, valeur_cents }
// depenses : { mois, campagne, source, depense_cents, impressions, clics }
// auditoire : { mois, campagne, source, genre, age, leads, depense_cents, ventes } (agrégé, comme les rapports des plateformes)
export function marketingFictif(fin = '2026-10') {
  const r = hasard(4242);
  const leads = []; const depenses = []; const auditoire = new Map();
  moisJusqua(fin, 24).forEach((mois, im) => {
    const mm = mois.slice(5); const idx = Number(mm) - 1; const croissance = 1 + im * 0.01;
    for (const c of CAMPAGNES) {
      let depense = Math.round((c.budget * (0.55 + 0.45 * c.saison[idx]) * (0.9 + r() * 0.2)) / 100) * 100;
      if (c.fixe) depense = c.fixe[mm] || 0;
      const clics = c.cpc ? Math.round(depense / c.cpc) : 0;
      const impressions = clics ? Math.round(clics / (0.008 + r() * 0.01)) : 0;
      let n = c.cpc ? Math.round(clics * c.conv * (0.85 + r() * 0.3) * (0.7 + 0.3 * c.saison[idx])) : Math.round((c.leadsMois || 0) * croissance * (0.75 + r() * 0.5));
      if (c.leadsFixe) n = c.leadsFixe[mm] || 0;
      if (depense || clics) depenses.push({ mois, campagne: c.code, source: c.source, depense_cents: depense, impressions, clics });
      const aud = AUDITOIRE[c.source];
      for (let k = 0; k < n; k++) {
        const succ = tirer(r, Object.entries(c.geo));
        const type = tirer(r, Object.entries(c.types));
        let ageIdx = null; let genre = null; let facteur = 1;
        if (aud) { genre = tirer(r, Object.entries(aud.genre)); ageIdx = tirer(r, aud.age.map((p, i) => [i, p])); facteur = CONV_AGE[ageIdx]; }
        const contacte = r() < 0.9;
        const visite = contacte && r() < Math.min(0.85, 0.55 * c.qualite * facteur);
        const vendu = visite && r() < Math.min(0.8, 0.45 * c.qualite);
        const valeur = vendu ? Math.round((VALEUR_TYPE[type] * (0.85 + r() * 0.3)) / 100) * 100 : 0;
        leads.push({ mois, jour_semaine: tirer(r, JOURS.map((p, i) => [i, p])), heure: tirer(r, HEURES.map((p, i) => [i, p])),
          source: c.source, campagne: c.code, type, succursale: succ, municipalite: tirer(r, SUCCURSALES[succ].villes).replace('--', '–'),
          contacte, visite, vendu, valeur_cents: valeur });
        if (aud) {
          const cle = `${mois}|${c.code}|${genre}|${AGES[ageIdx]}`;
          const a = auditoire.get(cle) || { mois, campagne: c.code, source: c.source, genre, age: AGES[ageIdx], leads: 0, depense_cents: 0, ventes: 0 };
          a.leads += 1; a.ventes += vendu ? 1 : 0; a.depense_cents += n ? depense / n : 0;
          auditoire.set(cle, a);
        }
      }
    }
  });
  return { leads, depenses, auditoire: [...auditoire.values()] };
}

export const JOURS_SEMAINE = ['Dim.', 'Lun.', 'Mar.', 'Mer.', 'Jeu.', 'Ven.', 'Sam.'];
export const JOURS_LONGS = ['dimanche', 'lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi'];
// Campagnes qui coûtent quelque chose (le coût par lead, par vente et le rendement se calculent sur leurs leads seulement)
export const CAMPAGNES_PAYANTES = new Set(CAMPAGNES.filter((c) => c.budget > 0 || c.fixe).map((c) => c.code));
