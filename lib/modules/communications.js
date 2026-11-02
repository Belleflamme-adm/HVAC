// Communications avec le client (ADR-067) : appels, textos, courriels, carte.
// Tout passe par le système de l'app de Mike une fois la greffe faite (MIKE_COMM_ENABLED=true).
// En attendant, les boutons ouvrent le téléphone, les textos ou le courriel de l'appareil, sans rien enregistrer.
import { uuid, ErreurValidation } from '../handler.js';
import { lienAction } from '../../public/js/bf-contact-liens.js';

export const CANAUX = ['appel', 'texto', 'courriel'];
const nonBranche = (quoi) => Object.assign(new Error(`${quoi} : à brancher sur l'app de Mike à la greffe (docs/MIGRATION.md)`),
  { status: 501, code: 'non_branche' });

export async function listerCommunications(repo, { client_id, lead_id, canal } = {}) {
  if (!client_id && !lead_id) throw new ErreurValidation('client_id ou lead_id requis');
  const filtre = client_id ? { client_id: uuid(client_id, 'client_id') } : { lead_id: uuid(lead_id, 'lead_id') };
  if (canal) { if (!CANAUX.includes(canal)) throw new ErreurValidation('Canal inconnu'); filtre.canal = canal; }
  return repo.list('communications_v', { filtre, ordre: { colonne: 'debut', asc: false }, limite: 500 });
}

// Écoute : la base vérifie l'accès et journalise l'écoute, puis l'app de Mike sert l'audio.
export async function ecouter(repo, cfg, id) {
  uuid(id);
  await repo.rpc('hvac_ecouter_enregistrement', { p_communication: id });
  if (!cfg.mikeCommEnabled) {
    return { disponible: false, message: 'Écoute à brancher sur l\'app de Mike (MIKE_COMM_ENABLED=false). L\'accès a été vérifié et journalisé.' };
  }
  // À la greffe : demander à l'app de Mike une URL d'écoute courte durée pour la référence rendue par la base
  throw nonBranche('Lecture de l\'enregistrement');
}

// Bouton téléphone, texto ou courriel : par l'app de Mike une fois branchée ; sinon, lien de l'appareil.
export function lancer(cfg, corps) {
  const { canal, coordonnee } = corps || {};
  if (!CANAUX.includes(canal)) throw new ErreurValidation('Canal : appel, texto ou courriel');
  if (corps.client_id) uuid(corps.client_id, 'client_id');
  if (corps.lead_id) uuid(corps.lead_id, 'lead_id');
  if (!corps.client_id && !corps.lead_id) throw new ErreurValidation('client_id ou lead_id requis');
  const lien = lienAction(canal, coordonnee);
  if (!lien) throw new ErreurValidation(canal === 'courriel' ? 'Courriel du client manquant ou invalide' : 'Numéro du client manquant ou invalide');
  if (!cfg.mikeCommEnabled) return { mode: 'appareil', lien };
  throw nonBranche(canal === 'appel' ? 'Appel par la téléphonie de Mike' : canal === 'texto' ? 'Texto par l\'app de Mike' : 'Courriel par l\'app de Mike');
}
