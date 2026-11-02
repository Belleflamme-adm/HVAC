// Tâche planifiée (netlify.toml, chaque minute) : le moteur de règles exécute les étapes dues (ADR-090).
// Une seule tâche pour toutes les automatisations ; chaque exécution est journalisée en base et un échec alerte Simon et Mike.
import { config } from '../../lib/config.js';
import { creerAccesSysteme } from '../../lib/data/systeme.js';

export const handler = async () => {
  try {
    const r = await creerAccesSysteme(config()).rpc('hvac_regles_executer', { p_limite: 200 });
    if (r?.echecs) console.error('regles-cron', JSON.stringify(r)); else console.log('regles-cron', JSON.stringify(r));
    return { statusCode: 200, body: JSON.stringify(r) };
  } catch (e) {
    // Panne du moteur lui-même : visible dans les journaux Netlify (à brancher sur une alerte à la mise en ligne)
    console.error('regles-cron EN PANNE', e.message);
    return { statusCode: e.status || 500, body: JSON.stringify({ error: e.message }) };
  }
};
