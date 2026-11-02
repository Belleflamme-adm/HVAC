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

// Installation par type : prix au client et coût (sous-traitant). Marge d'installation de 25 %, comme la grille (ADR-060).
export const INSTALLATION = {
  mural_simple: { prix: 160000, cout: 120000 },
  mural_multi: { prix: 280000, cout: 210000 },
  central: { prix: 420000, cout: 315000 },
  bienergie: { prix: 380000, cout: 285000 },
};

// Vendeurs fictifs : poids de vente par succursale (certains vendent dans deux territoires).
// numero = ordre de création dans le système : c'est l'ordre d'affichage partout, jamais le classement (ADR-077).
export const VENDEURS = {
  'e-marc': { numero: 1, nom: 'Marc Vendeur (FICTIF)', succ: { HO: 5, ST: 1.5 } },
  'e-julie': { numero: 2, nom: 'Julie Gagnon (FICTIF)', succ: { HO: 3, RO: 1 } },
  'e-sophie': { numero: 3, nom: 'Sophie Vente (FICTIF)', succ: { RO: 5, HO: 1 } },
  'e-eric': { numero: 4, nom: 'Éric Lavoie (FICTIF)', succ: { RO: 3.5 } },
  'e-annie': { numero: 5, nom: 'Annie Roy (FICTIF)', succ: { ST: 4 } },
  'e-karim': { numero: 6, nom: 'Karim Ventes (FICTIF)', succ: { GA: 4.5 } },
  'e-melanie': { numero: 7, nom: 'Mélanie Côté (FICTIF)', succ: { GA: 2.5 } },
  'e-patrick': { numero: 8, nom: 'Patrick Fortin (FICTIF)', succ: { DR: 4, GA: 0.4 } },
};

// Marques et modèles fictifs (marge : part du prix qui reste après le coût de la machine et de l'installation)
export const MODELES = [
  { code: 'ARC-MS12', nom: 'Arctica MS-12 (12 000 BTU)', marque: 'Arctica', type: 'mural_simple', prix: 395000, fournisseur: 'laur', marge: 0.38, poids: 6 },
  { code: 'ARC-MS18', nom: 'Arctica MS-18 (18 000 BTU)', marque: 'Arctica', type: 'mural_simple', prix: 465000, fournisseur: 'laur', marge: 0.36, poids: 3 },
  { code: 'BOR-HX12', nom: 'Boréal HX-12 Hyper-chaleur', marque: 'Boréal', type: 'mural_simple', prix: 449000, fournisseur: 'mtl', marge: 0.40, poids: 5 },
  { code: 'BOR-HX24', nom: 'Boréal HX-24 Hyper-chaleur', marque: 'Boréal', type: 'mural_simple', prix: 579000, fournisseur: 'mtl', marge: 0.37, poids: 2 },
  { code: 'NOR-M2Z', nom: 'Nordair M2 (2 zones)', marque: 'Nordair', type: 'mural_multi', prix: 789000, fournisseur: 'ont', marge: 0.35, poids: 4 },
  { code: 'NOR-M3Z', nom: 'Nordair M3 (3 zones)', marque: 'Nordair', type: 'mural_multi', prix: 965000, fournisseur: 'ont', marge: 0.34, poids: 3 },
  { code: 'ARC-MZ4', nom: 'Arctica MZ-4 (4 zones)', marque: 'Arctica', type: 'mural_multi', prix: 1189000, fournisseur: 'laur', marge: 0.33, poids: 1.5 },
  { code: 'BOR-CT2', nom: 'Boréal CT centrale 2 tonnes', marque: 'Boréal', type: 'central', prix: 1095000, fournisseur: 'mtl', marge: 0.30, poids: 2.5 },
  { code: 'BOR-CT3', nom: 'Boréal CT centrale 3 tonnes', marque: 'Boréal', type: 'central', prix: 1285000, fournisseur: 'mtl', marge: 0.29, poids: 2 },
  { code: 'NOR-BI25', nom: 'Nordair Bi-énergie 2,5 tonnes', marque: 'Nordair', type: 'bienergie', prix: 1165000, fournisseur: 'ont', marge: 0.31, poids: 2.5 },
  { code: 'ARC-BI3', nom: 'Arctica Bi-énergie 3 tonnes', marque: 'Arctica', type: 'bienergie', prix: 1245000, fournisseur: 'laur', marge: 0.30, poids: 1.5 },
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
        const vendeur = tirer(r, Object.entries(VENDEURS).filter(([, v]) => v.succ[code]).map(([id, v]) => [id, v.succ[code]]));
        const direct = modele.type === 'central' || modele.type === 'bienergie' ? r() < 0.45 : r() < 0.15;
        ventes.push({
          mois, jour: 1 + Math.floor(r() * 28), succursale: code, municipalite: tirer(r, s.villes).replace('--', '–'),
          modele: modele.code, type, marque: modele.marque, fournisseur: modele.fournisseur,
          provenance: direct ? 'direct' : 'entrepot', delai_jours: Math.round((direct ? 6 : 2) + r() * (direct ? 8 : 4)),
          vendeur, prix_cents: Math.round(modele.prix * (0.92 + r() * 0.12) / 100) * 100,
        });
        const v = ventes[ventes.length - 1];
        // Coût : marge du modèle, moins le rabais consenti (prix sous la liste = marge plus mince)
        v.cout_cents = Math.round(modele.prix * (1 - modele.marge) * (0.97 + r() * 0.06) / 100) * 100;
        // Part installation (sans tirage au hasard : les totaux restent les mêmes) ; le reste = la machine
        const inst = INSTALLATION[type];
        v.prix_installation_cents = Math.round(inst.prix * (v.prix_cents / modele.prix) / 100) * 100;
        v.cout_installation_cents = inst.cout;
      }
    }
  });
  return ventes;
}

// Inventaire fictif au dernier jour du mois `fin` : par modèle et par lieu (entrepôt central ou succursale)
export const LIEUX_STOCK = { entrepot: 'Entrepôt central', HO: 'Saint-Jérôme', RO: 'Rosemère', ST: 'Saint-Sauveur', GA: 'Gatineau', DR: 'Drummondville' };
export function stockFictif() {
  const r = hasard(777);
  const stock = [];
  for (const m of MODELES) {
    for (const lieu of Object.keys(LIEUX_STOCK)) {
      const base = lieu === 'entrepot' ? m.poids * 3.2 : m.poids * 0.5;
      const qte = Math.max(0, Math.round(base * (0.4 + r() * 1.2) - (m.type === 'bienergie' && lieu !== 'entrepot' ? 1 : 0)));
      if (qte) stock.push({ modele: m.code, type: m.type, marque: m.marque, lieu, qte, valeur_cents: qte * Math.round(m.prix * (1 - m.marge) * 0.7) });
    }
  }
  return stock;
}

// Régions de la carte où se trouvent les villes de chaque succursale (plusieurs municipalités portent le même nom)
export const REGIONS_SUCC = { HO: ['Laurentides', 'Lanaudière'], RO: ['Laurentides', 'Laval', 'Lanaudière'], ST: ['Laurentides'], GA: ['Outaouais'], DR: ['Centre-du-Québec', 'Montérégie'] };
// geo -> fonction (succursale, nom de ville) -> codes de municipalités sur la carte
export function indexVilles(geo) {
  const cache = new Map();
  return (succ, nom) => {
    const cle = `${succ}|${nom}`;
    if (!cache.has(cle)) {
      cache.set(cle, (geo?.features || []).filter((f) => f.properties.nom === nom && REGIONS_SUCC[succ].includes(f.properties.region)).map((f) => f.properties.code));
    }
    return cache.get(cle);
  };
}

// Activité fictive des vendeurs par mois (ADR-074), cohérente avec leurs ventes : leads reçus, contacts (appels,
// textos, courriels), visites, soumissions envoyées, heures travaillées. À la greffe : CRM (leads, contacts),
// Pointage de Mike (heures), devis de Mike (soumissions).
const PROFILS = {   // taux de closing (ventes / soumissions), heures par mois
  'e-marc': { closing: 0.46, heures: 165 }, 'e-julie': { closing: 0.38, heures: 150 }, 'e-sophie': { closing: 0.41, heures: 160 },
  'e-eric': { closing: 0.33, heures: 162 }, 'e-annie': { closing: 0.44, heures: 140 }, 'e-karim': { closing: 0.36, heures: 168 },
  'e-melanie': { closing: 0.29, heures: 110 }, 'e-patrick': { closing: 0.49, heures: 158 },
};
export function activiteVendeurs(ventes) {
  const r = hasard(8128);
  const parCle = new Map();
  for (const v of ventes) { const k = `${v.mois}|${v.vendeur}`; parCle.set(k, (parCle.get(k) || 0) + 1); }
  const lignes = [];
  for (const mois of [...new Set(ventes.map((v) => v.mois))]) {
    for (const [id, p] of Object.entries(PROFILS)) {
      const n = parCle.get(`${mois}|${id}`) || 0;
      const soumissions = Math.max(n, Math.round(n / (p.closing * (0.9 + r() * 0.2))));
      const visites = Math.round(soumissions * (1.1 + r() * 0.15));
      const contacts = Math.round(visites * (1.7 + r() * 0.4));
      const leads = Math.round(contacts * (0.55 + r() * 0.1));
      lignes.push({ mois, vendeur: id, leads, contacts, visites, soumissions, heures: Math.round(p.heures * (0.92 + r() * 0.12)) });
    }
  }
  return lignes;
}

// Tri des vendeurs par ordre de création (le premier entré dans le système en premier)
export const parOrdreCreation = (a, b) => VENDEURS[a].numero - VENDEURS[b].numero;
