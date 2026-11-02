// Fenêtre flottante (équivalent bf-windows chez Mike) : barre de titre, agrandir, fermer.
// Échap ferme ; le focus revient sur l'élément qui l'a ouverte. Position non mémorisée pour l'instant
// (chez Mike : localStorage bf_win_rect:*).
// Flèche Retour d'Android (ou Précédent) : ferme la fenêtre au lieu de quitter la page. La fenêtre ajoute une
// entrée à l'historique ; un lien cliqué dans la fenêtre retire d'abord cette entrée, puis change de page.
let apresRetour = null;   // geste à faire une fois l'entrée de la fenêtre retirée (lien cliqué dans la fenêtre)
let fermerOuverte = null;
if (typeof window !== 'undefined') {
  window.addEventListener('popstate', () => {
    if (fermerOuverte) fermerOuverte(false);
    if (apresRetour) { const f = apresRetour; apresRetour = null; f(); }
  });
}
// Pour un changement de page : sort d'abord de l'entrée de la fenêtre, s'il y en a une
export function apresFenetre(geste) {
  if (fermerOuverte && history.state?.bfFenetre) { apresRetour = geste; history.back(); } else geste();
}
if (typeof window !== 'undefined') window.__bfApresFenetre = apresFenetre;

export function ouvrirFenetre(titre, remplirCorps) {
  if (fermerOuverte) fermerOuverte(false);   // une fenêtre en remplace une autre : on garde son entrée d'historique
  document.querySelector('.bf-fenetre-fond')?.remove();
  const retour = document.activeElement;
  const fond = document.createElement('div');
  fond.className = 'bf-fenetre-fond';
  const fen = document.createElement('section');
  fen.className = 'bf-fenetre';
  fen.setAttribute('role', 'dialog');
  fen.setAttribute('aria-modal', 'true');
  fen.setAttribute('aria-label', titre);

  const barre = document.createElement('div');
  barre.className = 'bf-fenetre__barre';
  const nom = document.createElement('span');
  nom.textContent = titre;
  const agrandir = document.createElement('button');
  agrandir.type = 'button'; agrandir.textContent = '□'; agrandir.title = 'Agrandir'; agrandir.setAttribute('aria-label', 'Agrandir');
  agrandir.addEventListener('click', () => fen.classList.toggle('bf-fenetre--grande'));
  const fermer = document.createElement('button');
  fermer.type = 'button'; fermer.textContent = '✕'; fermer.title = 'Fermer'; fermer.setAttribute('aria-label', 'Fermer');
  const boutons = document.createElement('span');
  boutons.className = 'bf-fenetre__boutons';
  boutons.append(agrandir, fermer);
  barre.append(nom, boutons);

  const corps = document.createElement('div');
  corps.className = 'bf-fenetre__corps bf-tuiles';
  remplirCorps(corps);
  fen.append(barre, corps);
  fond.append(fen);
  document.body.append(fond);

  let enHistorique = false;
  try {
    if (!history.state?.bfFenetre) history.pushState({ ...(history.state || {}), bfFenetre: true }, '');
    enHistorique = true;
  } catch { /* sans historique : Échap et ✕ seulement */ }
  // parGeste : ✕, Échap ou clic à côté (on retire alors l'entrée de l'historique) ; false : déjà fait par Retour
  const fermerFenetre = (parGeste = true) => {
    if (fermerOuverte !== fermerFenetre) return;
    fermerOuverte = null;
    fond.remove(); document.removeEventListener('keydown', clavier); retour?.focus?.();
    if (parGeste && enHistorique && history.state?.bfFenetre) history.back();
  };
  fermerOuverte = fermerFenetre;
  const clavier = (e) => { if (e.key === 'Escape') fermerFenetre(); };
  // Lien dans la fenêtre (tuile d'un groupe) : retirer l'entrée de la fenêtre, puis changer de page
  corps.addEventListener('click', (e) => {
    const a = e.target.closest?.('a[href]');
    if (!a || e.defaultPrevented || a.target === '_blank' || !enHistorique) return;
    e.preventDefault();
    const href = a.getAttribute('href');
    apresFenetre(() => { location.href = href; });
  });
  fermer.addEventListener('click', () => fermerFenetre());
  fond.addEventListener('click', (e) => { if (e.target === fond) fermerFenetre(); });
  // Retour d'Android : ferme la fenêtre (popstate ci-haut)
  document.addEventListener('keydown', clavier);
  (corps.querySelector('a, button') || fermer).focus();
  return fermerFenetre;
}
