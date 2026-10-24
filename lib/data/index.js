// Point d'entrée unique de la couche de données (CLAUDE.md §5).
// Tout le code (fonctions serverless) passe par getAdapter() : jamais d'appel direct à
// Supabase ou à Monday ailleurs. Pour greffer dans l'app de Mike, on change l'adapter,
// pas les modules.
//
// Interface commune d'un adapter :
//   auth.signIn(email, motDePasse)  -> { accessToken, refreshToken, expiresIn }
//   auth.refresh(refreshToken)      -> { accessToken, refreshToken, expiresIn }
//   auth.signOut(accessToken)       -> void
//   session(accessToken)            -> { employe }   (null si le compte n'est lié à aucun employé)
//   repo(accessToken)               -> { list, get, insert, update, updateWhere, upsert, removeWhere, remove, rpc,
//                                        televerser, urlsSignees } avec la RLS de l'utilisateur (tables et fichiers)

import { config } from '../config.js';
import { creerAdapterSupabase } from './supabase.js';
import { creerAdapterMonday } from './monday.js';
import { creerAdapterFriday } from './friday.js';
import { DataError } from './erreurs.js';

export function getAdapter(env = process.env) {
  const cfg = config(env);
  switch (cfg.dataAdapter) {
    case 'supabase': return creerAdapterSupabase(cfg);
    case 'monday': return creerAdapterMonday(cfg);
    case 'friday': return creerAdapterFriday(cfg);
    default: throw new DataError('adapter_inconnu', `DATA_ADAPTER inconnu : ${cfg.dataAdapter}`, 500);
  }
}

export { DataError } from './erreurs.js';
