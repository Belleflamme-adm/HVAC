// GET [?fournisseur=] -> { nom, partenaire_depuis, compte_cree_le, version, version_le } (ADR-096)
// Le sous-traitant reçoit le sien ; la planification passe le fournisseur.
import { avecSession } from '../../lib/handler.js';
import { lirePartenariat } from '../../lib/modules/sous-traitants.js';

export const handler = avecSession({
  GET: ({ repo, query }) => lirePartenariat(repo, query.fournisseur),
});
