// Vérification des codes d'accès des tuiles protégées (ADR-078). Le rôle est vérifié d'abord : le code s'ajoute
// à la restriction par rôle, il ne la remplace pas.
import { ErreurValidation } from '../handler.js';
import { verifierCode } from '../../public/js/bf-code.js';

export const ZONES = { vendeurs: ['Admin tout', 'Direction', 'Comptabilité'] };
const pause = (ms) => new Promise((r) => setTimeout(r, ms));

export async function verifierAcces(data, token, cfg, corps, { delaiEchec = 800 } = {}) {
  const zone = String(corps?.zone || '');
  if (!ZONES[zone]) throw new ErreurValidation('Zone inconnue');
  const { employe } = await data.session(token);
  if (!employe || !ZONES[zone].includes(employe.role)) throw Object.assign(new Error('Accès réservé'), { status: 403, code: 'interdit' });
  const empreinte = cfg.codesAcces?.[zone];
  if (!empreinte) throw Object.assign(new Error('Code d\'accès non configuré (CODE_ACCES_VENDEURS)'), { status: 503, code: 'non_configure' });
  if (!(await verifierCode(corps.code, empreinte))) {
    await pause(delaiEchec);   // ralentit les essais à répétition
    throw Object.assign(new Error('Code incorrect'), { status: 403, code: 'code_incorrect' });
  }
  return { ok: true };
}
