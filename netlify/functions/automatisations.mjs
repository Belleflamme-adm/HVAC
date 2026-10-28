// Moteur de règles (ADR-090). GET -> règles et suivi, échecs, journal, messages automatiques, heures, liens d'avis.
// PATCH { action: regle (actif, etapes) | relancer | heures | lien_avis }. Droits vérifiés en base (RLS et fonctions).
import { avecSession } from '../../lib/handler.js';
import { lireAutomatisations, modifierAutomatisations } from '../../lib/modules/automatisations.js';

export const handler = avecSession({
  GET: ({ repo }) => lireAutomatisations(repo),
  PATCH: ({ repo, corps }) => modifierAutomatisations(repo, corps),
});
