// Libellés communs de la liste de prix des sous-traitants (registre, PDF).
import { formatCents } from './bf-money.js?v=0.4.0';

export const UNITES = { forfait: 'forfait', tete: 'par tête', pied: 'par pied', sortie: 'par sortie', heure: 'par heure', unite: 'par unité', livre: 'par livre' };
export const prix = (c) => (c === null || c === undefined ? 'à remplir' : formatCents(Number(c)));

// Phrase d'un changement entre deux versions : « Prix : CODE | nom : 1 200,00 $ -> 1 300,00 $ »
export function phraseChangement(c) {
  if (c.type === 'ajout') return `Ajouté : ${c.code} | ${c.nom}${c.apres !== null && c.apres !== undefined ? ` (${prix(c.apres)})` : ''}`;
  if (c.type === 'retrait') return `Retiré : ${c.code} | ${c.nom}`;
  return `Prix : ${c.code} | ${c.nom} : ${prix(c.avant)} -> ${prix(c.apres)}`;
}
