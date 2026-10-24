# Migration | Greffer la division HVAC dans l'app de Mike

> Document vivant. Mis à jour à chaque livraison. Statut : **Phase 3, module Clients + Devis livré en local, rien n'est déployé.**

## Ordre prévu (à valider avec Mike le moment venu)

1. **Code** : copier `public/`, `netlify/functions/` et `lib/data/` dans le repo de Mike. Les noms de fichiers et de fonctions suivent ses conventions (`bf-*`, kebab-case par domaine, `session-*`). Vérifier les collisions de noms avec ses ~430 fonctions.
2. **Schéma** : appliquer `supabase/migrations/` sur le Supabase de Mike, **dans un schéma dédié** (ex. `hvac`) si des tables homonymes existent déjà (`clients`, `factures`, `devis`...). Décision à prendre avec Mike.
3. **Référentiels** : réconcilier `succursales`, `divisions`, `employes` avec BD - Divisions et BD - Employés (via `monday_item_id`).
4. **Compteurs** : aligner `compteurs` sur les derniers numéros réels de Mike **avant** le premier devis réel. Les devis de démonstration commencent à 900001 (ADR-043) et ne migrent pas. Jamais de décrément.
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
| Séries de numéros de devis | Même série que Mike (ADR-043). En autonome, les devis de démo partent de 900001 ; à la greffe, l'app de Mike attribue les numéros. |

## Fonctions livrées (Phase 3, Clients + Devis)

`clients-list`, `clients-get`, `clients-create`, `clients-update`, `sites-save`, `catalogue-search`, `devis-list`, `devis-get`, `devis-create`, `devis-update`, `devis-lignes`, `devis-statut`, `devis-renouveler`, `approbations`, `installation-options`, `installation-tarifs`, `sous-traitants`, `territoire`, `principaux`, `disponibilites`, `municipalites`.
| Comptes sous-traitants dans l'app de Mike | Mike n'a peut-être pas de rôle externe. Il faut décider si les sous-traitants entrent dans SON app (avec des droits limités) ou dans un portail séparé. Ils voient des renseignements de clients en Lot B : entente de confidentialité requise. |
| Disponibilités vs Pointage (`belleflammetime`) | Vérifier si le calendrier de Mike peut accueillir les disponibilités des sous-traitants, pour éviter deux calendriers. |


## Demandes de prix aux sous-traitants (ADR-061)
- Variable Netlify `URL` : Netlify la fournit automatiquement. Elle sert à construire le lien `…/prix#jeton`. À la greffe, ce sera le domaine de l'app de Mike.
- Page publique `/prix` : aucune session. Vérifier que la CSP de Mike permet les images `data:` (signature).
- Envoi automatique du lien par courriel : à brancher sur le fournisseur de courriel de Mike (à confirmer).

## Registre des listes de prix des sous-traitants (ADR-065)
- Table `listes_prix_versions` : à migrer telle quelle, **sans jamais réécrire les lignes** (preuve). Garder `cree_le`, `auteur_nom` et `empreinte` d'origine.
- Fonctions : `hvac_maj_mes_prix`, `hvac_confier_travaux`, `hvac_versionner_liste`. Tout chemin qui modifie un tarif ou un travail confié chez Mike doit appeler `hvac_versionner_liste`, sinon le registre aura des trous.
- PDF produit dans le navigateur avec `public/js/vendor/pdf-lib-1.17.1.esm.min.js` (MIT). Chez Mike, on peut le remplacer par une fonction `generate-*` côté serveur, à condition de partir de la même copie figée.
- Paramètre `seuil_versions_liste_30j` (3 par défaut).

## Communications : téléphonie, textos, courriels, carte (ADR-067)
À fixer avec Mike avant d'activer `MIKE_COMM_ENABLED=true` :
1. **Lancer** (`communication-lancer`) : l'appel à la fonction de Mike qui place l'appel (téléphonie Twilio chez Mike), ouvre sa fenêtre de textos ou envoie le courriel, avec l'employé connecté.
2. **Recevoir** (`communications-webhook`) : le format que Mike envoie pour chaque appel, texto et courriel, et sa signature (secret partagé en variable d'environnement). Pour chaque communication : trouver le client ou le lead par le numéro ou le courriel, l'insérer dans `communications` (par `externe_id`, sans doublon) et, pour un lead, ajouter l'activité `appel`, `texto` ou `courriel` qui compte pour la rapidité du vendeur.
3. **Écouter** (`communication-audio`) : l'audio reste chez Mike. Après la vérification et la journalisation par `hvac_ecouter_enregistrement`, demander à Mike une URL d'écoute de courte durée. Jamais d'URL publique permanente.
4. **Conservation** : inscrire la durée de Mike dans le paramètre `conservation_enregistrements_jours` et planifier `app.purger_enregistrements()` chaque nuit.
5. **Carte** : remplacer le lien Google Maps par la carte du client de l'app de Mike, et remplir `sites.latitude` / `sites.longitude` depuis ses données.
6. **Avis d'enregistrement** : vérifier que la téléphonie de Mike annonce l'enregistrement au début de chaque appel, entrant et sortant (à valider par un professionnel).
7. Une fois les communications automatiques en place, mettre en veille les boutons manuels Appel, Courriel et Texto de la fiche du lead, pour éviter les doublons.

## Tableau des vendeurs (ADR-074)
- Les taux de commission et salaires de base saisis dans la maquette ne sont pas la source de vérité : à la greffe, lire ceux du module Commissions de Mike (taux par vendeur, règles, exceptions), sans en garder une copie.
- Heures travaillées : Pointage de Mike. Soumissions : ses devis envoyés. Ventes et marges : ses devis acceptés et factures (même définition de marge que la comptabilité, avec installation).

## Codes d'accès des tuiles (ADR-078)
- Variable `CODE_ACCES_VENDEURS` (empreinte, jamais le code) à créer dans Netlify par Simon : `node scripts/code-acces.mjs`.
- Avant les vraies données : la fonction de rémunération doit exiger un jeton remis par `code-acces` (courte durée), et les échecs doivent être comptés en base pour bloquer après plusieurs essais.
- Chez Mike : vérifier s'il a déjà un mécanisme de code ou de PIN (ex. impersonation, « Admin tout ») et s'y aligner.

## Macro (ADR-079)
- Webhook de Mike « soumission acceptée » -> `hvac_projet_signe` (numéro de soumission, client ou lead, montant avant taxes, type de système, vendeur). Une seule fois par numéro.
- Correspondance des étapes avec le Macro de Mike : à confirmer (noms et ordre de ses statuts). Nos projets HVAC déjà créés devront être repris dans son Macro sous le même code projet.

## Mes jobs du sous-traitant (ADR-080)
- Migration `20261024001400_jobs_sous_traitant.sql` :
  - `projets.sous_traitant_id` ;
  - table `projet_lignes` (machines sans prix, installation au coût figé de la liste du sous-traitant) ;
  - `hvac_projet_signe` accepte `sous_traitant_id` et `lignes` ;
  - vue `projets_macro_v` (sous-traitant, coût d'installation) ;
  - fonction `hvac_mes_projets`.
- À la greffe :
  - le webhook « devis accepté » de Mike doit fournir le sous-traitant attitré et les lignes du devis (machines : description et quantité ; installation : type de travail et quantité). Ne jamais transmettre le prix client au portail du sous-traitant.
  - si le devis de Mike porte déjà le coût du sous-traitant, comparer avec sa liste et décider laquelle fait foi (à confirmer avec Mike).

## Feuille d'extra et facture finale du sous-traitant (ADR-081)
- Migration `20261024001500_extras_sous_traitant.sql` :
  - table `projet_extras` ;
  - `projets.facture_st_soumise_le` et `projets.facture_st_total_cents` ;
  - fonctions `hvac_extra_ajouter`, `hvac_extra_retirer`, `hvac_extras_envoyer`, `hvac_extra_decider`, `hvac_facture_finale` ;
  - vue `extras_v` ;
  - `projets_macro_v` et `hvac_mes_projets` enrichies.
- À la greffe :
  - la facture finale approuvée doit créer une facture payable dans l'app de Mike (board « Factures payables Bot » ou son équivalent Supabase). Format à confirmer avec Mike ;
  - les extras approuvés pour « oubli du vendeur » peuvent alimenter les commissions de Mike, si Simon le décide.

## Photos des extras (ADR-082)
- Migration `20261024001600_photos_extras.sql` :
  - bucket privé `extras-photos` ;
  - table `projet_extra_photos` ;
  - politiques RLS sur `storage.objects` (insertion et lecture) ;
  - fonctions `hvac_extra_photo_preparer`, `_confirmer`, `_retirer`, `hvac_extra_photos` ;
  - colonne `nb_photos` (extras_v, hvac_mes_projets).
- Mise en ligne : la migration crée le bucket. Vérifier dans le tableau de bord Supabase (Storage) qu'il est bien **privé**.
- Chez Mike, les fichiers sont déjà dans Supabase Storage (Friday) : à la greffe, déplacer le bucket ou le renommer selon ses conventions (à confirmer).
