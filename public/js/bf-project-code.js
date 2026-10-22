// Code projet Macro, logique unique (équivalent de bfProjectCodeOf dans js/bf-project-code.js chez Mike).
// Format réel (Simon, 22 oct. 2026) : [SUCC][DIV]-[3 lettres prénom]-[3 lettres nom]-[NNN].

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

// 3 lettres majuscules sans accents, complété avec X (identique à app.code3 en base).
export function code3(texte) {
  const lettres = String(texte ?? '')
    .replace(/œ/g, 'oe').replace(/Œ/g, 'OE').replace(/æ/g, 'ae').replace(/Æ/g, 'AE')
    .normalize('NFD').replace(/[̀-ͯ]/g, '')
    .toUpperCase().replace(/[^A-Z]/g, '');
  return lettres.slice(0, 3).padEnd(3, 'X');
}

// Code projet Belleflamme : [SUCC][DIV]-[PRÉ]-[NOM]-[NNN], ex. STV-JEA-TRE-001.
// Le numéro NNN est attribué par la base (compteur sans trou par préfixe).
//   bfProjectCodeOf({ code_projet: 'stv-jea-tre-001' })                          -> 'STV-JEA-TRE-001'
//   bfProjectCodeOf({ succursale: 'ST', division: 'Ventilation', prenom: 'Jean', nom: 'Tremblay' })
//                                                                                 -> 'STV-JEA-TRE'  (préfixe)
//   ... avec sequence: 2                                                          -> 'STV-JEA-TRE-002'
//   bfProjectCodeOf({ succursale: 'RO', division: 'Ventilation' })                -> 'ROV'
export function bfProjectCodeOf(p) {
  if (!p) return '';
  if (p.code_projet) return String(p.code_projet).trim().toUpperCase();
  const succ = String(p.succursale ?? p.succursale_code ?? '').trim().toUpperCase();
  const lettre = normaliserDivision(p.division);
  if (!SUCCURSALES[succ] || !lettre) return '';
  const segment1 = succ + lettre;
  if (!p.nom) return segment1;
  const prefixe = `${segment1}-${code3(p.prenom || p.entreprise || p.nom)}-${code3(p.nom)}`;
  return Number.isInteger(p.sequence) && p.sequence > 0 ? `${prefixe}-${String(p.sequence).padStart(3, '0')}` : prefixe;
}

export function bfParseProjectCode(code) {
  const m = /^([A-Z]{2})([VFB])-([A-Z]{3})-([A-Z]{3})-(\d{3})$/.exec(String(code || '').trim().toUpperCase());
  if (!m || !SUCCURSALES[m[1]]) return null;
  return { succursale: m[1], division: m[2], prenom: m[3], nom: m[4], sequence: Number(m[5]), prefixe: m[1] + m[2] };
}

export const estCodeProjet = (code) => bfParseProjectCode(code) !== null;

if (typeof window !== 'undefined') {
  window.bfProjectCodeOf = bfProjectCodeOf;
  window.bfParseProjectCode = bfParseProjectCode;
}
