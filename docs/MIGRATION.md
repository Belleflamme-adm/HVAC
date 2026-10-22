# Migration | Greffer la division HVAC dans l'app de Mike

> Document vivant. Mis à jour à chaque livraison. Statut : **Phase 3, module Clients + Devis livré en local, rien n'est déployé.**

## Ordre prévu (à valider avec Mike le moment venu)

1. **Code** : copier `public/`, `netlify/functions/` et `lib/data/` dans le repo de Mike. Les noms de fichiers et de fonctions suivent ses conventions (`bf-*`, kebab-case par domaine, `session-*`). Vérifier les collisions de noms avec ses ~430 fonctions.
2. **Schéma** : appliquer `supabase/migrations/` sur le Supabase de Mike, **dans un schéma dédié** (ex. `hvac`) si des tables homonymes existent déjà (`clients`, `factures`, `devis`...). Décision à prendre avec Mike.
3. **Référentiels** : réconcilier `succursales`, `divisions`, `employes` avec BD - Divisions et BD - Employés (via `monday_item_id`).
4. **Compteurs** : aligner `compteurs` sur les derniers numéros réels de Mike **avant** la première facture. Jamais de décrément.
5. **Données** : les données de démo (`fictif = true`) ne migrent pas.
6. **Synchro Monday** : activer `MONDAY_ENABLED` / `FRIDAY_SYNC_ENABLED` et les webhooks seulement une fois le mapping colonne par colonne complété (`docs/MAPPING.md`).
7. **Variables** (voir `.env.example`) : `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY` (tâches système seulement), `DATA_ADAPTER`, `MONDAY_ENABLED`, `FRIDAY_SYNC_ENABLED`, `MONDAY_WEBHOOK_SECRET`, `APP_VERSION`. Aucune clé dans le repo.
8. **DNS / URL** : à définir (sous-chemin de `belleflammemain` ou app séparée dans son hub).

## Risques connus

| Risque | Mitigation |
|---|---|
| Tables homonymes chez Mike | Schéma dédié `hvac` ou préfixe, décidé avant la migration |
| Formats de numéros différents | Configurables (`formats_numerotation`), sans migration |
| Libellés de rôles différents | Contrainte `check` sur `employes.role` à ajuster |
| Région Supabase différente | Dump/restore (ADR-014) |
| Auth : Mike utilise peut-être son propre token, pas Supabase Auth | Le contrat `session-*` reste identique côté front, on adapte seulement `lib/session.js` et l'adapter |
| Collision de noms de fonctions (`session-login`, `health`...) avec les ~430 fonctions de Mike | Ne pas copier les `session-*` : utiliser celles de Mike, qui ont le même contrat. Renommer `health` en `hvac-health`. |
| Composants `bf-*` homonymes chez Mike (`bf-tuiles`, `bf-bandeau`) | Les nôtres sont minimaux : utiliser ceux de Mike et ne greffer que nos tuiles |
| Collision avec le module devis de Mike (~25 fonctions `devis-*`, board Ventes et Devis 2.0) | Décision à prendre avec Mike : (a) nos devis HVAC deviennent la division Ventilation de SON module devis, ou (b) on garde un module séparé préfixé (`hvac-devis-*`). L'option (a) est plus propre mais demande de porter nos règles (plafond, kits, validité) dans son code. |
| Séries de numéros de devis | Nos devis de démo consomment `D-AAAA-0000x`. Avant la greffe, aligner `compteurs` sur la série réelle de Mike (jamais de décrément). |

## Fonctions livrées (Phase 3, Clients + Devis)

`clients-list`, `clients-get`, `clients-create`, `clients-update`, `sites-save`, `catalogue-search`, `devis-list`, `devis-get`, `devis-create`, `devis-update`, `devis-lignes`, `devis-statut`, `devis-renouveler`, `approbations`, `installation-options`, `installation-tarifs`.

