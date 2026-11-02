// Outils de calendrier (sans DOM), partagés et testés.
export const iso = (d) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;

export function grilleMois(annee, mois) {
  // Semaines du lundi au dimanche ; null pour les cases hors du mois.
  const premier = new Date(annee, mois, 1);
  const decalage = (premier.getDay() + 6) % 7;
  const nbJours = new Date(annee, mois + 1, 0).getDate();
  const cases = [...Array(decalage).fill(null), ...Array.from({ length: nbJours }, (_, i) => new Date(annee, mois, i + 1))];
  while (cases.length % 7) cases.push(null);
  return Array.from({ length: cases.length / 7 }, (_, i) => cases.slice(i * 7, i * 7 + 7));
}
