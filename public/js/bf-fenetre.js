// Fenêtre flottante (équivalent bf-windows chez Mike) : barre de titre, agrandir, fermer.
// Échap ferme ; le focus revient sur l'élément qui l'a ouverte. Position non mémorisée pour l'instant
// (chez Mike : localStorage bf_win_rect:*).
export function ouvrirFenetre(titre, remplirCorps) {
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

  const fermerFenetre = () => { fond.remove(); document.removeEventListener('keydown', clavier); retour?.focus?.(); };
  const clavier = (e) => { if (e.key === 'Escape') fermerFenetre(); };
  fermer.addEventListener('click', fermerFenetre);
  fond.addEventListener('click', (e) => { if (e.target === fond) fermerFenetre(); });
  document.addEventListener('keydown', clavier);
  (corps.querySelector('a, button') || fermer).focus();
  return fermerFenetre;
}
