// Webhook app de Mike (Pointage) -> HVAC : visite planifiée, déplacée ou annulée (ADR-086). INACTIF.
// 503 tant que POINTAGE_SYNC_ENABLED=false (CLAUDE.md §5). Signature HMAC obligatoire (lib/modules/pointage.js).
// La clé serveur n'appelle qu'une fonction : hvac_visite_pointage.
import { config } from '../../lib/config.js';
import { json, erreur, methode } from '../../lib/http.js';
import { creerAccesSysteme } from '../../lib/data/systeme.js';
import { lireSigne } from '../../lib/signature.js';
import { normaliserVisite } from '../../lib/modules/pointage.js';

export async function handler(event, _context, { systeme } = {}) {
  const refus = methode(event, 'POST');
  if (refus) return refus;
  const cfg = config();
  if (!cfg.pointageSyncEnabled) return erreur(503, 'desactive', 'Synchro Pointage désactivée (POINTAGE_SYNC_ENABLED=false)');
  const { corpsBrut, probleme } = lireSigne(event, cfg.pointageWebhookSecret);
  if (probleme) return erreur(401, 'signature', probleme);
  let corps;
  try { corps = JSON.parse(corpsBrut); } catch { return erreur(400, 'json', 'Corps JSON invalide'); }
  const { visite, erreur: invalide } = normaliserVisite(corps);
  if (invalide) return erreur(400, 'validation', invalide);
  try {
    const r = await (systeme || creerAccesSysteme(cfg)).rpc('hvac_visite_pointage', { p: visite });
    return json(200, r);
  } catch (e) {
    return erreur(e.status === 500 ? 422 : (e.status || 500), e.code || 'erreur', e.message);
  }
}
