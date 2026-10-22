// STUB. Adapter Monday (belleflamme-team.monday.com), prêt à brancher, désactivé.
// Activation : MONDAY_ENABLED=true + mapping complété dans docs/MAPPING.md.
// Garde-fous (CLAUDE.md §2) : lecture seule tant que Simon n'a pas autorisé l'écriture.
import { DataError, desactive } from './erreurs.js';

export function creerAdapterMonday(cfg) {
  const garde = () => {
    if (!cfg.mondayEnabled) throw desactive('monday', 'MONDAY_ENABLED');
    throw new DataError('non_implemente', 'Adapter Monday : mapping des colonnes à confirmer (docs/MAPPING.md)', 501);
  };
  return {
    nom: 'monday',
    auth: { signIn: garde, refresh: garde, signOut: garde },
    session: garde,
    repo: () => ({ list: garde, get: garde, insert: garde, update: garde, updateWhere: garde, remove: garde, rpc: garde }),
  };
}
