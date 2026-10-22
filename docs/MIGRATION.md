# Migration | Greffer la division HVAC dans l'app de Mike

> Document vivant. Mis à jour à chaque livraison. Statut : **Phase 1, schéma proposé, rien n'est déployé.**

## Ordre prévu (à valider avec Mike le moment venu)

1. **Code** : copier `public/`, `netlify/functions/` et `lib/data/` dans le repo de Mike. Les noms de fichiers et de fonctions suivent ses conventions (`bf-*`, kebab-case par domaine, `session-*`). Vérifier les collisions de noms avec ses ~430 fonctions.
2. **Schéma** : appliquer `supabase/migrations/` sur le Supabase de Mike, **dans un schéma dédié** (ex. `hvac`) si des tables homonymes existent déjà (`clients`, `factures`, `devis`...). Décision à prendre avec Mike.
3. **Référentiels** : réconcilier `succursales`, `divisions`, `employes` avec BD - Divisions et BD - Employés (via `monday_item_id`).
4. **Compteurs** : aligner `compteurs` sur les derniers numéros réels de Mike **avant** la première facture. Jamais de décrément.
5. **Données** : les données de démo (`fictif = true`) ne migrent pas.
6. **Synchro Monday** : activer `MONDAY_ENABLED` / `FRIDAY_SYNC_ENABLED` et les webhooks seulement une fois le mapping colonne par colonne complété (`docs/MAPPING.md`).
7. **Variables** : à lister en Phase 2. Aucune clé dans le repo.
8. **DNS / URL** : à définir (sous-chemin de `belleflammemain` ou app séparée dans son hub).

## Risques connus

| Risque | Mitigation |
|---|---|
| Tables homonymes chez Mike | Schéma dédié `hvac` ou préfixe, décidé avant la migration |
| Formats de numéros différents | Configurables (`formats_numerotation`), sans migration |
| Libellés de rôles différents | Contrainte `check` sur `employes.role` à ajuster |
| Région Supabase différente | Dump/restore (ADR-014) |
| Auth : Mike utilise peut-être son propre token, pas Supabase Auth | Le contrat `session-*` reste identique côté front, on adapte seulement les fonctions |
