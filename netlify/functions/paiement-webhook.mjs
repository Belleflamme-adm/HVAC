// Webhook app de Mike -> HVAC : dépôt du client reçu (ADR-087). INACTIF.
// 503 tant que PAIEMENT_SYNC_ENABLED=false (CLAUDE.md §5). Signature HMAC obligatoire (lib/signature.js).
// La clé serveur appelle hvac_depot_recu (projet à « À céduler ») ou hvac_facture_payee (facture finale payée, ADR-092).
import { config } from '../../lib/config.js';
import { json, erreur, methode } from '../../lib/http.js';
import { creerAccesSysteme } from '../../lib/data/systeme.js';
import { lireSigne } from '../../lib/signature.js';
import { normaliserDepot, normaliserFacturePayee } from '../../lib/modules/paiement.js';

export async function handler(event, _context, { systeme } = {}) {
  const refus = methode(event, 'POST');
  if (refus) return refus;
  const cfg = config();
  if (!cfg.paiementSyncEnabled) return erreur(503, 'desactive', 'Paiements de l\'app de Mike désactivés (PAIEMENT_SYNC_ENABLED=false)');
  const { corpsBrut, probleme } = lireSigne(event, cfg.paiementWebhookSecret);
  if (probleme) return erreur(401, 'signature', probleme);
  let corps;
  try { corps = JSON.parse(corpsBrut); } catch { return erreur(400, 'json', 'Corps JSON invalide'); }
  // Facture finale payée (ADR-092) : condition de la facture conforme LogisVert
  if (corps?.type === 'facture_payee') {
    const { facture, erreur: inv } = normaliserFacturePayee(corps);
    if (inv) return erreur(400, 'validation', inv);
    try { return json(200, await (systeme || creerAccesSysteme(cfg)).rpc('hvac_facture_payee', { p: facture })); }
    catch (e) { return erreur(e.status === 500 ? 422 : (e.status || 500), e.code || 'erreur', e.message); }
  }
  const { depot, ignore, erreur: invalide } = normaliserDepot(corps);
  if (ignore) return json(200, { change: false, raison: ignore });
  if (invalide) return erreur(400, 'validation', invalide);
  try {
    return json(200, await (systeme || creerAccesSysteme(cfg)).rpc('hvac_depot_recu', { p: depot }));
  } catch (e) {
    return erreur(e.status === 500 ? 422 : (e.status || 500), e.code || 'erreur', e.message);
  }
}
