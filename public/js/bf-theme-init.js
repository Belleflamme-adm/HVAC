// Applique le thème avant le premier rendu (préférence dans localStorage, préfixe bf_).
(function () {
  var theme = null;
  try { theme = localStorage.getItem('bf_theme'); } catch (e) { /* stockage indisponible */ }
  if (theme === 'light' || theme === 'dark') document.documentElement.setAttribute('data-theme', theme);
})();
