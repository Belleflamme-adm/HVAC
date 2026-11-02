# Mapping | Tables HVAC <-> boards Monday de Mike

> **Statut : ébauche Phase 1.** Les colonnes des boards Monday sont **inconnues** (scan du 16 oct. 2026 sans accès aux boards privés). Tout ce qui n'a pas été vu est marqué **à confirmer**. Rien n'est inventé : une ligne « à confirmer » veut dire qu'on ne sait pas.
>
> Source des noms de boards : `CLAUDE.md`, section 3.

## Colonnes de migration communes

Chaque table qui a un équivalent chez Mike porte ces colonnes nullables, ajoutées par `app.preparer_table()` :

| Colonne | Rôle |
|---|---|
| `monday_board_id` | ID du board Monday d'origine |
| `monday_item_id` | ID de l'item Monday (unique quand présent). Équivaut à `user.itemId` du contrat d'auth de Mike pour `employes`. |
| `source` | `hvac` (créé ici), `monday` (importé), `friday` (miroir Supabase de Mike) |
| `synced_at` | Dernière synchro |

Tables **avec** ces colonnes : `succursales`, `divisions`, `employes`, `fournisseurs`, `clients`, `leads`, `inspections`, `marques`, `produits`, `kits`, `devis`, `projets`, `equipements_installes`, `appels_service`, `bons_travail`, `factures`, `paiements`, `subventions`.

## Table par table

| Table HVAC | Board Monday (Mike) | ID board | Correspondance des colonnes |
|---|---|---|---|
| `succursales` | BD - Divisions ? | à confirmer | à confirmer. Codes HO, ST, RO, DR, GA connus. Saint-Jérôme = HO (ADR-003). |
| `divisions` | BD - Divisions | à confirmer | `nom` = valeur du champ `division` de Mike (Foyer, Foyer-Gaz, Gaz, Ventilation, Climatisation). `lettre`, `code_generique` : connus (CLAUDE.md §3). |
| `employes` | BD - Employés | à confirmer | `id` / `monday_item_id` / `email` / `prenom`+`nom` / `role` = contrat `session-me` de Mike (`id, itemId, email, name, role`). Libellés des rôles autres que « Admin tout » : à confirmer. |
| `communications` | (téléphonie, textos et courriels de l'app de Mike ; Twilio chez Mike) | à confirmer | à confirmer. `externe_id` = identifiant de l'appel ou du message chez Mike. `enregistrement_ref` = référence de l'audio chez Mike (jamais une URL publique). `transcription`, `resume` : produits par Mike (AssemblyAI, Whisper). Durée de conservation : règle de Mike, à confirmer (ADR-067). |
| `fournisseurs` | BD - Fournisseurs | à confirmer | à confirmer. Fiche sous-traitant (ADR-064) : `nom`, `licence_rbq` (format 1234-5678-90), `neq`, `telephone`, `courriel`, `adresse`, `responsable_nom`, `responsable_telephone`, `responsable_courriel`, `proprietaire_nom`, `actif`. Colonnes équivalentes chez Mike : à confirmer. |
| `clients` | BD - Clients | à confirmer | à confirmer. Champs LogisVert (`est_proprietaire`, `nom_preuve_propriete`, numéros HQ) : probablement absents chez Mike. |
| `sites` | (aucun board connu) | | Adresses probablement dans BD - Clients ou Ventes et Devis 2.0 : à confirmer |
| `leads` | Lead Réseaux Ventilation (180 items) ; Lead Réseaux | à confirmer | à confirmer. `source` et `statut` : valeurs Monday à confirmer. |
| `campagnes_marketing` (à créer) | Lead Réseaux (colonne campagne ?) | à confirmer | Tableau marketing (ADR-072) : code, source, nom de la campagne Facebook ou Google, pour relier chaque lead à sa campagne. Dépenses, clics et auditoires agrégés : rapports Facebook (Meta) et Google Ads, jamais au dossier du lead (Loi 25). |
| `inspections` | Rapport inspection pré-installation (1175) ; Bot - Rapport pré-install Ventilation (5) ; Rapport d'inspection Ventilation/Climatisation (0) | à confirmer | Colonnes inconnues : tout le formulaire va dans `donnees` (jsonb) en attendant. |
| `marques` | (dans Catalogue ?) | à confirmer | `escompte_fournisseur_bp`, `plafond_rabais_exception_bp` : source chez Mike à confirmer |
| `produits` | Catalogue (~29,7k items) | 9677840877 | à confirmer. Champs HVAC (`ahri`, `energy_star`, `btu_nominal`, `btu_moins8`) : à confirmer. |
| `kits`, `kit_items` | Kits | à confirmer | à confirmer. Les kits de thermopompes existent déjà chez Mike (selon Simon). |
| `types_travaux`, `tarifs_sous_traitants` | BD - Fournisseurs ? (grilles de sous-traitants) | à confirmer | à confirmer. Chez Mike, les prix des sous-traitants sont peut-être dans des factures payables ou des documents, pas dans un board. |
| `municipalites` | (aucun board connu) | | Nouveau. Source : Découpages administratifs, MRNF (CC-BY 4.0). |
| `territoires_sous_traitants`, `principaux_municipalites`, `disponibilites_sous_traitants` | (aucun board connu) | | Nouveau (Lot A). À confirmer : Mike gère-t-il les disponibilités dans Pointage (`belleflammetime`) ? |
| `devis`, `devis_lignes` | Ventes et Devis 2.0 | à confirmer | à confirmer. Format du numéro de devis de Mike : à confirmer (ADR-004). |
| `approbations_rabais`, `delegations_rabais` | (aucun board connu) | | Probablement nouveau. À confirmer : comment Mike trace les approbations aujourd'hui. |
| `projets` | Plan de charge - Macro | à confirmer | `code_projet` = code Macro `[SUCC][DIV]-[PRÉ]-[NOM]-[NNN]` (ADR-040), identique à celui du devis d'origine. Autres colonnes : à confirmer. |
| `equipements_installes` | Section équipements HVAC du détail Macro | à confirmer | Numéros de série int./ext./thermopompes poussés vers LogisVert : noms de champs à confirmer. |
| `bons_travail`, `bt_lignes` | BT | à confirmer | à confirmer |
| `appels_service` | Appels de service V2 ; Service App | à confirmer | à confirmer. Code générique ASV. |
| `contrats_entretien` | (aucun board connu) | | Probablement nouveau (ADR-012) |
| `factures`, `facture_lignes` | FR Factures Recevables Bot | à confirmer | à confirmer. Méthode de facturation progressive de Mike : à confirmer (ADR-009). |
| `paiements` | Rapport de paiements | à confirmer | à confirmer. Webhook `paiement-cascade` chez Mike. |
| `financements` | (aucun board connu) | | Financeit : processus à confirmer |
| `subventions` | Bot - Demandes Subvention (25) | à confirmer | à confirmer |
| `documents` | Fichiers Monday / Supabase Storage (Friday) | | Chemins à confirmer |
| `journal_audit` | (aucun) | | Nouveau |
| `formats_numerotation`, `compteurs` | (aucun board connu) | | Chez Mike, la logique est dans le code (`bf-project-code.js`) : à confirmer |

## Boards HVAC connus, sans table dédiée

| Board | Items | Hypothèse |
|---|---|---|
| Mélissa (ventilation) | 115 | Pipeline personnel d'une employée ? À confirmer avant de mapper. |
| Ventilation / À finaliser | 16 | Projets ou devis en suspens ? À confirmer. |

## Mes jobs (ADR-080)
- `projets.sous_traitant_id` : champ du devis de Mike qui désigne l'installateur (sous-traitant) : à confirmer.
- `projet_lignes` : lignes du devis de Mike (machines, installation). Noms des colonnes et façon de distinguer une machine d'une ligne d'installation : à confirmer. Le prix client des lignes n'est **pas** repris.

## Feuille d'extra (ADR-081)
- `projet_extras` : aucun board connu chez Mike pour les extras des sous-traitants : à confirmer (« Factures payables Bot » pour la facture finale ?).
- `projets.facture_st_total_cents` : montant de la facture payable du sous-traitant chez Mike : champ à confirmer.

## Dossier de job LogisVert (ADR-084)
- `projets.numero_ahri` : champ AHRI du Macro de Mike ou de la demande LogisVert : à confirmer.
- `equipements_installes` (rôle, marque, modèle, numéro de série) : section « équipements HVAC » du détail Macro de Mike (numéros de série des unités intérieures, extérieures, thermopompes) : noms de champs à confirmer.
- `projet_photos` : fichiers dans Supabase Storage chez Mike (Friday) : convention à confirmer.

## Automatisations (ADR-090)
- `communications` (messages automatiques, statut `en_file`) : file d'envoi de l'app de Mike (Twilio, courriel) : format à confirmer.
- `consentements` et `desabonnements` : aucun équivalent connu chez Mike. À confirmer : où Mike garde les « STOP » de Twilio.
- `succursales.lien_avis_google` : liens des fiches Google des succursales (à fournir).
- `regles` : les automatisations codées une par une chez Mike (63 crons) pourront devenir des règles.

## Comment compléter ce document

Une fois que Claude aura un accès en lecture seule à Monday (exception dans `CLAUDE.md` §2) :
1. Lister les colonnes (id, titre, type) de chaque board ci-dessus.
2. Remplir la colonne « Correspondance » colonne par colonne.
3. Ne jamais copier de données réelles dans le repo : seulement la structure.
