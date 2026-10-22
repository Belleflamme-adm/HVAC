// STUB. Adapter Friday (miroir Monday -> Supabase de Mike, table friday_items), désactivé.
// Activation : FRIDAY_SYNC_ENABLED=true, seulement lors de la migration dans l'app de Mike.
import { DataError, desactive } from './erreurs.js';

export function creerAdapterFriday(cfg) {
  const garde = () => {
    if (!cfg.fridaySyncEnabled) throw desactive('friday', 'FRIDAY_SYNC_ENABLED');
    throw new DataError('non_implemente', 'Adapter Friday : à implémenter lors de la migration', 501);
  };
  return {
    nom: 'friday',
    auth: { signIn: garde, refresh: garde, signOut: garde },
    session: garde,
    repo: () => ({ list: garde, get: garde, insert: garde, update: garde, rpc: garde }),
  };
}
