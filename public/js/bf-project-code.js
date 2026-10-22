// Code projet Macro, logique unique (équivalent de bfProjectCodeOf dans js/bf-project-code.js chez Mike).
// Format Mike : XXX-XXX-XXX, 1er segment = succursale (2 lettres) + division (1 lettre).
// Les 2e et 3e segments sont inconnus : le code complet est attribué par la base
// (app.prochain_numero('projet'), format configurable). Ici : préfixe, validation, analyse.

export const SUCCURSALES = Object.freeze({
  HO: 'Head Office | Saint-Jérôme', ST: 'St-Sauveur', RO: 'Rosemère', DR: 'Drummondville', GA: 'Gatineau',
});

export const DIVISIONS = Object.freeze({
  'Ventilation': 'V', 'Climatisation': 'V', 'Foyer': 'F', 'Foyer-Gaz': 'F', 'Gaz': 'F', 'BBQ': 'B',
});

export const CODES_GENERIQUES = Object.freeze(['FYR', 'FYG', 'VTC', 'BBQ', 'PLB', 'ASV', 'ADM']);

function normaliserDivision(d) {
  if (!d) return null;
  const brut = String(d).trim();
  if (/^[VFB]$/i.test(brut)) return brut.toUpperCase();
  const cle = Object.keys(DIVISIONS).find((k) => k.toLowerCase() === brut.toLowerCase());
  return cle ? DIVISIONS[cle] : null;
}

// bfProjectCodeOf({ succursale: 'RO', division: 'Ventilation' }) -> 'ROV'
// bfProjectCodeOf({ code_projet: 'ROV-001-26' })                -> 'ROV-001-26'
export function bfProjectCodeOf(p) {
  if (!p) return '';
  if (p.code_projet) return String(p.code_projet).trim().toUpperCase();
  const succ = String(p.succursale ?? p.succursale_code ?? '').trim().toUpperCase();
  const lettre = normaliserDivision(p.division);
  if (!SUCCURSALES[succ] || !lettre) return '';
  return succ + lettre;
}

// Analyse un code complet. Tolérant sur les segments 2 et 3 tant que le format de Mike n'est pas confirmé.
export function bfParseProjectCode(code) {
  const m = /^([A-Z]{2})([VFB])-([A-Z0-9]{1,6})-([A-Z0-9]{1,6})$/.exec(String(code || '').trim().toUpperCase());
  if (!m || !SUCCURSALES[m[1]]) return null;
  return { succursale: m[1], division: m[2], segment2: m[3], segment3: m[4], prefixe: m[1] + m[2] };
}

export const estCodeProjet = (code) => bfParseProjectCode(code) !== null;

if (typeof window !== 'undefined') {
  window.bfProjectCodeOf = bfProjectCodeOf;
  window.bfParseProjectCode = bfParseProjectCode;
}
