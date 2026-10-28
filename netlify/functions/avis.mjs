// Cloche (ADR-090) : GET -> mes avis et mes tâches ouvertes | PATCH { action: lu, id } | { action: tache_faite, id }
import { avecSession } from '../../lib/handler.js';
import { lireAvis, modifierAvis } from '../../lib/modules/automatisations.js';

export const handler = avecSession({ GET: ({ repo }) => lireAvis(repo), PATCH: ({ repo, corps }) => modifierAvis(repo, corps) });
