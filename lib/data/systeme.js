// Accès SYSTÈME (clé service_role) : tâches planifiées seulement, jamais une requête d'utilisateur.
// La clé ne sort jamais des fonctions serverless (CLAUDE.md §2, règle 7). Elle contourne la RLS : on n'y expose
// que les gestes de la purge des photos (ADR-084) la réception des visites de Pointage (ADR-086) des dépôts (ADR-087), le moteur de règles et les appels manqués (ADR-090).
import { createClient } from '@supabase/supabase-js';
import { DataError } from './erreurs.js';

export function creerAccesSysteme(cfg, { createClientImpl = createClient } = {}) {
  if (!cfg.supabaseUrl || !cfg.supabaseServiceRoleKey) {
    throw new DataError('config_manquante', 'SUPABASE_URL et SUPABASE_SERVICE_ROLE_KEY doivent être définis pour les tâches système', 503);
  }
  const c = createClientImpl(cfg.supabaseUrl, cfg.supabaseServiceRoleKey, { auth: { persistSession: false, autoRefreshToken: false } });
  const verifier = ({ data, error }) => { if (error) throw new DataError(error.code || 'supabase', error.message, 500); return data; };
  return {
    async rpc(fn, args) {
      if (!['hvac_photos_a_purger', 'hvac_photos_purgees', 'hvac_visite_pointage', 'hvac_depot_recu', 'hvac_regles_executer', 'hvac_appel_manque', 'hvac_facture_payee'].includes(fn)) throw new DataError('interdit', `Fonction système non permise : ${fn}`, 500);
      return verifier(await c.rpc(fn, args));
    },
    async supprimerFichiers(bucket, chemins) {
      if (!['jobs-photos', 'extras-photos'].includes(bucket)) throw new DataError('interdit', `Bucket non permis : ${bucket}`, 500);
      return verifier(await c.storage.from(bucket).remove(chemins));
    },
  };
}
