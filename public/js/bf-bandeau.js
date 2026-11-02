// Bandeau de stats (équivalent bf-bandeau / fonction bandeau-stats chez Mike).
// Phase 2 : affiche l'utilisateur et la succursale. Les stats arrivent avec les modules (Phase 3).
export function rendreBandeau(conteneur, user) {
  const nom = document.createElement('strong');
  nom.textContent = user.name;
  const details = document.createElement('span');
  details.textContent = ` | ${user.role} | ${user.succursale}`;
  conteneur.replaceChildren(nom, details);
  if (user.masterImpersonation) {
    const imp = document.createElement('span');
    imp.className = 'bf-bandeau__imp';
    imp.textContent = ` | vu par ${user.masterImpersonation.name}`;
    conteneur.append(imp);
  }
}
