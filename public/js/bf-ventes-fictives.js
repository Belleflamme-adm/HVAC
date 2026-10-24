// Ventes de machines HVAC FICTIVES pour le tableau exécutif (ADR-068). Aucune donnée réelle.
// À la greffe : remplacé par les ventes réelles de l'app de Mike (devis acceptés, équipements HVAC du Macro).
// Générateur déterministe : mêmes chiffres à chaque ouverture.

export const TYPES = { mural_simple: 'Murale simple', mural_multi: 'Murale multi', central: 'Système central', bienergie: 'Biénergie' };

export const SUCCURSALES = {
  HO: { nom: 'Saint-Jérôme', poids: 1.15, types: { mural_simple: 4, mural_multi: 2, central: 2, bienergie: 1.5 },
    villes: [['Saint-Jérôme', 6], ['Saint-Colomban', 2], ['Saint-Hippolyte', 1.5], ['Lachute', 1.2], ['Saint-Lin--Laurentides', 1], ['Mirabel', 2]] },
  RO: { nom: 'Rosemère', poids: 1.35, types: { mural_simple: 4, mural_multi: 3, central: 2.5, bienergie: 1 },
    villes: [['Rosemère', 2.5], ['Blainville', 4], ['Boisbriand', 2.5], ['Sainte-Thérèse', 2.5], ['Lorraine', 1.2], ['Terrebonne', 3], ['Laval', 3.5]] },
  ST: { nom: 'Saint-Sauveur', poids: 0.85, types: { mural_simple: 3, mural_multi: 4, central: 1, bienergie: 1 },
    villes: [['Saint-Sauveur', 3], ['Sainte-Adèle', 2.5], ['Morin-Heights', 1.2], ['Piedmont', 1], ['Sainte-Anne-des-Lacs', 1], ['Prévost', 1.8], ['Val-David', 1], ['Sainte-Agathe-des-Monts', 1.5], ['Mont-Tremblant', 1.4]] },
  GA: { nom: 'Gatineau', poids: 1.0, types: { mural_simple: 3, mural_multi: 2, central: 3, bienergie: 2.5 },
    villes: [['Gatineau', 8], ['Chelsea', 1.2], ['Cantley', 1.4], ["L'Ange-Gardien", 0.8], ['Val-des-Monts', 1.2], ['Pontiac', 0.6]] },
  DR: { nom: 'Drummondville', poids: 0.8, types: { mural_simple: 3, mural_multi: 1.5, central: 2, bienergie: 3 },
    villes: [['Drummondville', 6], ['Saint-Cyrille-de-Wendover', 1], ['Victoriaville', 2], ['Saint-Hyacinthe', 1.5], ['Nicolet', 0.8], ['Saint-Germain-de-Grantham', 0.7]] },
};

export const FOURNISSEURS = {
  laur: 'Distribution Laurentides (FICTIF)',
  mtl: 'Grossiste Montréal HVAC (FICTIF)',
  ont: 'Importation Est ontarien (FICTIF)',
};

// Marques et modèles fictifs
export const MODELES = [
  { code: 'ARC-MS12', nom: 'Arctica MS-12 (12 000 BTU)', marque: 'Arctica', type: 'mural_simple', prix: 395000, fournisseur: 'laur', poids: 6 },
  { code: 'ARC-MS18', nom: 'Arctica MS-18 (18 000 BTU)', marque: 'Arctica', type: 'mural_simple', prix: 465000, fournisseur: 'laur', poids: 3 },
  { code: 'BOR-HX12', nom: 'Boréal HX-12 Hyper-chaleur', marque: 'Boréal', type: 'mural_simple', prix: 449000, fournisseur: 'mtl', poids: 5 },
  { code: 'BOR-HX24', nom: 'Boréal HX-24 Hyper-chaleur', marque: 'Boréal', type: 'mural_simple', prix: 579000, fournisseur: 'mtl', poids: 2 },
  { code: 'NOR-M2Z', nom: 'Nordair M2 (2 zones)', marque: 'Nordair', type: 'mural_multi', prix: 789000, fournisseur: 'ont', poids: 4 },
  { code: 'NOR-M3Z', nom: 'Nordair M3 (3 zones)', marque: 'Nordair', type: 'mural_multi', prix: 965000, fournisseur: 'ont', poids: 3 },
  { code: 'ARC-MZ4', nom: 'Arctica MZ-4 (4 zones)', marque: 'Arctica', type: 'mural_multi', prix: 1189000, fournisseur: 'laur', poids: 1.5 },
  { code: 'BOR-CT2', nom: 'Boréal CT centrale 2 tonnes', marque: 'Boréal', type: 'central', prix: 1095000, fournisseur: 'mtl', poids: 2.5 },
  { code: 'BOR-CT3', nom: 'Boréal CT centrale 3 tonnes', marque: 'Boréal', type: 'central', prix: 1285000, fournisseur: 'mtl', poids: 2 },
  { code: 'NOR-BI25', nom: 'Nordair Bi-énergie 2,5 tonnes', marque: 'Nordair', type: 'bienergie', prix: 1165000, fournisseur: 'ont', poids: 2.5 },
  { code: 'ARC-BI3', nom: 'Arctica Bi-énergie 3 tonnes', marque: 'Arctica', type: 'bienergie', prix: 1245000, fournisseur: 'laur', poids: 1.5 },
];

// PRNG déterministe (mulberry32)
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

// Saison : climatisation au printemps-été, chauffage (thermopompe, biénergie) à l'automne
const SAISON = [0.55, 0.45, 0.5, 0.75, 1.15, 1.45, 1.4, 1.1, 1.05, 1.25, 1.0, 0.7]; // janv. -> déc.

// Mois au format AAAA-MM, du plus ancien au plus récent, se terminant à `fin`
export function moisJusqua(fin, n) {
  const [a, m] = fin.split('-').map(Number);
  return Array.from({ length: n }, (_, i) => {
    const d = new Date(Date.UTC(a, m - 1 - (n - 1 - i), 1));
    return `${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, '0')}`;
  });
}

// 24 mois de ventes fictives (pour comparer à la période précédente) se terminant au mois `fin`
export function ventesFictives(fin = '2026-10') {
  const r = hasard(20261024);
  const ventes = [];
  moisJusqua(fin, 24).forEach((mois, i) => {
    const croissance = 1 + i * 0.012;
    const saison = SAISON[Number(mois.slice(5)) - 1];
    for (const [code, s] of Object.entries(SUCCURSALES)) {
      const n = Math.round(22 * s.poids * saison * croissance * (0.85 + r() * 0.3));
      for (let k = 0; k < n; k++) {
        const type = tirer(r, Object.entries(s.types));
        const modele = tirer(r, MODELES.filter((x) => x.type === type).map((x) => [x, x.poids]));
        const direct = modele.type === 'central' || modele.type === 'bienergie' ? r() < 0.45 : r() < 0.15;
        ventes.push({
          mois, jour: 1 + Math.floor(r() * 28), succursale: code, municipalite: tirer(r, s.villes).replace('--', '–'),
          modele: modele.code, type, marque: modele.marque, fournisseur: modele.fournisseur,
          provenance: direct ? 'direct' : 'entrepot', delai_jours: Math.round((direct ? 6 : 2) + r() * (direct ? 8 : 4)),
          prix_cents: Math.round(modele.prix * (0.92 + r() * 0.12) / 100) * 100,
        });
      }
    }
  });
  return ventes;
}
