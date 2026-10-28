// Webhook téléphonie (Twilio de l'app de Mike) -> HVAC : appel manqué (ADR-090). INACTIF.
// 503 tant que TELEPHONIE_SYNC_ENABLED=false. Signé comme les autres webhooks de Mike (lib/signature.js).
// Corps : { telephone, succursale_code, appele_le?, appel_ref? } -> lead (existant ou nouveau) et règle « Texto après appel manqué ».
import { config } from '../../lib/config.js';
import { json, erreur, methode } from '../../lib/http.js';
import { creerAccesSysteme } from '../../lib/data/systeme.js';
import { lireSigne } from '../../lib/signature.js';

export async function handler(event, _context, { systeme } = {}) {
  const refus = methode(event, 'POST');
  if (refus) return refus;
  const cfg = config();
  if (!cfg.telephonieSyncEnabled) return erreur(503, 'desactive', 'Téléphonie de l\'app de Mike désactivée (TELEPHONIE_SYNC_ENABLED=false)');
  const { corpsBrut, probleme } = lireSigne(event, cfg.telephonieWebhookSecret);
  if (probleme) return erreur(401, 'signature', probleme);
  let c;
  try { c = JSON.parse(corpsBrut); } catch { return erreur(400, 'json', 'Corps JSON invalide'); }
  if (!/^[A-Z]{2}$/.test(String(c.succursale_code || ''))) return erreur(400, 'validation', 'succursale_code requis');
  if (String(c.telephone || '').replace(/\D/g, '').length < 10) return erreur(400, 'validation', 'telephone requis');
  const p = { telephone: String(c.telephone), succursale_code: c.succursale_code };
  if (c.appele_le && !Number.isNaN(new Date(c.appele_le).getTime())) p.appele_le = new Date(c.appele_le).toISOString();
  if (c.appel_ref) p.appel_ref = String(c.appel_ref).slice(0, 100);
  try { return json(200, await (systeme || creerAccesSysteme(cfg)).rpc('hvac_appel_manque', { p })); }
  catch (e) { return erreur(e.status === 500 ? 422 : (e.status || 500), e.code || 'erreur', e.message); }
}
