# Journal des décisions (ADR courts)

Format : contexte | décision | conséquences. Statut : `Acceptée`, `À confirmer`, `Remplacée`.

---

## ADR-001 | Compte GitHub du projet
- **Date** : 2026-10-22 | **Statut** : Acceptée
- **Contexte** : le repo `Belleflamme-adm/HVAC` porte un nom proche de l'org Supabase de Mike (`Belleflamme-adm's Org`).
- **Décision** : Simon confirme que le compte GitHub `Belleflamme-adm` est son compte perso. Le repo fait partie de l'infra perso autorisée.
- **Conséquences** : on peut pousser sur ce repo. La confusion de nom avec l'org de Mike reste un risque : il faut toujours vérifier le compte actif avant de provisionner.

## ADR-002 | Connecteurs Netlify et Supabase de la session
- **Date** : 2026-10-22 | **Statut** : Acceptée
- **Décision** : Simon confirme que les connecteurs sont reliés à ses comptes perso.
- **Conséquences** : la règle 3 tient toujours. Avant chaque provisionnement, on vérifie le compte ou l'org actif et on attend l'OK de Simon.

## ADR-003 | Code de succursale de Saint-Jérôme
- **Date** : 2026-10-22 | **Statut** : Acceptée
- **Décision** : Saint-Jérôme (succursale et entrepôt central) utilise le code `HO`. Code projet HVAC : `HOV-...`.
- **Conséquences** : pas de code de succursale distinct. Il faut quand même pouvoir distinguer la succursale de Saint-Jérôme de l'entrepôt pour l'inventaire, au moyen d'un emplacement plutôt que d'un code projet.

## ADR-004 | Numérotation des devis, factures et projets
- **Date** : 2026-10-22 | **Statut** : À confirmer (format exact de Mike)
- **Décision** : on reproduit le format de Mike. En attendant de l'avoir, le format est **configurable** (préfixe, année, padding, portée du compteur). La numérotation se fait côté base, dans une table de compteurs verrouillée dans la même transaction (pas de `SEQUENCE`, qui crée des trous). Aucun décrément, aucune réutilisation de numéro. Une annulation se fait par note de crédit numérotée.
- **Conséquences** : quand on recevra de vrais exemples, il faudra seulement changer la config, sans migration de données.

## ADR-005 | Installation
- **Date** : 2026-10-22 | **Statut** : Acceptée
- **Décision** : l'installation est faite par des employés **et** par des sous-traitants.
- **Conséquences** : un BT ou une installation peut être assigné à un employé ou à un sous-traitant (fournisseur). Il faut suivre les coûts de sous-traitance dans la rentabilité du projet.

## ADR-006 | Visibilité des vendeurs
- **Date** : 2026-10-22 | **Statut** : Acceptée
- **Décision** : un vendeur voit les clients, leads et devis de **sa succursale**. Les politiques RLS sont basées sur la succursale.

## ADR-007 | Inspection pré-installation
- **Date** : 2026-10-22 | **Statut** : Acceptée
- **Décision** : l'inspection se fait **avant** le devis et sert à le monter. Flux : lead > inspection > devis.

## ADR-008 | Subvention LogisVert
- **Date** : 2026-10-22 | **Statut** : Acceptée
- **Décision** : dans la majorité des cas, c'est le client qui dépose la demande, à l'aide d'un document HTML créé par Simon. Pour les clients qui ont besoin d'aide (souvent des clients âgés), le représentant des ventes les accompagne.
- **Conséquences** : le guide client de Simon est copié dans `docs/reference/logisvert-guide-client.html` (source : https://claude.ai/artifact/WRNh66LK6or389XJa166Bg, liste HQ du 16-10-2026). La facture HVAC doit **obligatoirement** contenir : numéro et date de facture, date d'installation, nom du client identique à la preuve de propriété, adresse d'installation, TPS/TVQ et RBQ de Belleflamme, description, **numéro AHRI ou ENERGY STAR**, modèle et capacité (BTU), coût et mention « Payé ». L'app bloque l'envoi d'une facture HVAC finale s'il manque un de ces champs. On suit aussi la photo de la plaque de l'appareil extérieur (modèle + S/N), l'échéance de 9 mois après l'installation (avec alerte), un indicateur « accompagnement par le représentant » et le statut de la demande. Les règles du programme changent : on les revalide à chaque mise à jour de la liste d'Hydro-Québec.

## ADR-009 | Facturation et financement
- **Date** : 2026-10-22 | **Statut** : À confirmer (méthode de Mike)
- **Décision** : facturation progressive. Dépôt de **40 %** à l'acceptation, puis le solde de **60 %** à payer **72 h avant l'installation**. Une majorité de clients passera par du financement **Financeit**. On suit la méthode de facturation de l'app de Mike.
- **Conséquences** : il faut une échéance calculée à partir de la date d'installation, une alerte si le solde n'est pas payé à 72 h, et un statut de demande Financeit. La méthode exacte de Mike est inconnue : je dois l'obtenir. L'intégration avec Financeit est à vérifier dans leur doc officielle, avant de coder quoi que ce soit.

## ADR-010 | Approbation des rabais
- **Date** : 2026-10-22 | **Statut** : Acceptée
- **Décision** : plafond par défaut = escompte fournisseur moins 35 points, avec des exceptions par marque. Mike ou Simon peut accorder à un employé un **plafond de rabais personnel**. Au-delà de ce plafond, l'approbation de Mike ou de Simon est obligatoire. Chaque octroi, changement et approbation est tracé (qui, quand, combien).
- **Conséquences** : on prévoit une table des droits d'approbation par employé et un journal d'approbation. Le devis est bloqué tant qu'il est en attente d'approbation.

## ADR-011 | Usage terrain hors ligne
- **Date** : 2026-10-22 | **Statut** : Acceptée
- **Décision** : les techniciens utilisent l'app sur le chantier, **parfois sans réseau**. Le PWA doit gérer le hors ligne dès le départ pour les BT, les photos et les numéros de série.
- **Conséquences** : il faut une file de synchronisation côté client, stockée en IndexedDB plutôt qu'en `localStorage` à cause de la taille des photos, et des règles de conflit. Aucun identifiant n'est stocké côté client.

## ADR-012 | Contrats d'entretien (ASV)
- **Date** : 2026-10-22 | **Statut** : Acceptée
- **Décision** : contrats d'entretien annuels, avec rappels automatiques au client.

## ADR-013 | Premier module
- **Date** : 2026-10-22 | **Statut** : Acceptée
- **Décision** : après le squelette, on livre **Clients + Devis** en premier (numérotation, taxes, rabais, dépôt de 40 %).

## ADR-014 | Région Supabase
- **Date** : 2026-10-22 | **Statut** : Acceptée (hypothèse sur la région de Mike non vérifiée)
- **Décision** : Canada, `ca-central-1`. Simon croit que la région de Mike est aussi au Canada.
- **Conséquences** : on vérifie la disponibilité de la région au moment de créer le projet (Phase 2). Si la région de Mike s'avère différente, la migration passera par un dump/restore, sans impact sur le code.

## ADR-015 | Certifications des techniciens
- **Date** : 2026-10-22 | **Statut** : Acceptée
- **Décision** : on stocke les certifications (halocarbures, RBQ, etc.) avec leur numéro et leur date d'expiration. Rien n'est bloquant par défaut. Un réglage permet d'activer le blocage d'assignation si un certificat est expiré.

## ADR-016 | Exemptions de taxes
- **Date** : 2026-10-22 | **Statut** : Acceptée
- **Décision** : certains clients sont exemptés, à l'occasion. On prévoit un statut d'exemption par client (type, numéro, pièce justificative) qui s'applique au calcul de la TPS et de la TVQ.
- **Conséquences** : les règles exactes d'exemption sont à vérifier auprès de Revenu Québec et de l'ARC, et à valider par un professionnel.

## ADR-017 | Source du catalogue fictif
- **Date** : 2026-10-22 | **Statut** : À confirmer
- **Contexte** : Simon a demandé de prendre les produits et les kits dans Monday et dans l'app de Mike.
- **Décision** : en suspens. Simon a refusé de faire l'export lui-même et demande une lecture directe. Ça contredit les garde-fous 2 et 4 de `CLAUDE.md`. Il faut une levée écrite et limitée de ces garde-fous (lecture seule, boards Catalogue et Kits seulement), et un accès technique qui fonctionne : le connecteur Monday ne se connecte pas dans cette session, et l'app de Mike exige une session que Claude n'a pas.
- **Conséquences** : en attendant, le seed utilise des produits plausibles marqués FICTIF. Les kits de thermopompes existent déjà chez Mike : on les reprendra dès que l'accès sera réglé.

---

# Phase 1 | Modèle de données

## ADR-018 | Conventions numériques
- **Date** : 2026-10-22 | **Statut** : Proposée
- **Décision** : montants en cents (`bigint`), rabais en points de base (1 % = 100), taux de taxe en pcm (9,975 % = 9975). Aucun `float`. Arrondi des taxes au cent le plus proche, le demi-cent s'éloigne de zéro. TPS et TVQ calculées chacune sur le sous-total taxable du document.
- **Conséquences** : arrondis identiques côté base et côté JS. La méthode (par document ou par ligne) reste à confirmer avec Mike.

## ADR-019 | Moment d'attribution des numéros
- **Date** : 2026-10-22 | **Statut** : Proposée
- **Décision** : le devis reçoit son numéro à la création (un devis ne se supprime jamais, il passe à `annule`). La facture reçoit son numéro **à l'émission** : un brouillon abandonné ne consomme pas de numéro. Les notes de crédit ont leur propre série.
- **Conséquences** : la série des factures émises est continue, sans trou, ce qu'exige la règle de Mike (Revenu Québec).

## ADR-020 | Modèle de sécurité
- **Date** : 2026-10-22 | **Statut** : Proposée
- **Décision** : RLS sur les 35 tables. `anon` n'a aucun droit. Les fonctions serverless interrogent la base avec le JWT de l'utilisateur, donc la RLS s'applique aussi à elles. La clé `service_role` sert seulement aux tâches système. Les techniciens voient seulement ce qui leur est assigné (minimisation, Loi 25). Aucune politique DELETE, sauf les lignes de brouillon. Les règles critiques (numéros, rabais, factures figées, LogisVert) sont des triggers en base, pas seulement du code JS.
- **Conséquences** : un bogue du front ou d'une fonction ne peut pas contourner ces règles. Pas de `FORCE ROW LEVEL SECURITY`, pour que les fonctions `security definer` lisent sans récursion.

## ADR-021 | Tests du schéma
- **Date** : 2026-10-22 | **Statut** : Proposée
- **Décision** : `tests/sql/run.sh` applique les migrations sur un Postgres 16 local jetable, avec une imitation minimale de Supabase (`tests/sql/00_supabase_stub.sql` : rôles et `auth.uid()`), puis lance les tests SQL (`tests/sql/10_phase1.test.sql`). Docker n'est pas disponible dans le conteneur cloud.
- **Conséquences** : en Phase 2, la CI GitHub Actions lancera le même script, avec un service Postgres.

## ADR-022 | Formats de numéros provisoires
- **Date** : 2026-10-22 | **Statut** : À confirmer
- **Décision** : formats provisoires dans `formats_numerotation` : `D-AAAA-00001`, `F-AAAA-00001`, `NC-AAAA-00001`, `BT-`, `ASV-`, `CE-`. Projet : `ROV-001-26`, qui ne respecte pas encore le format `XXX-XXX-XXX` de Mike.
- **Conséquences** : on passera aux vrais formats en modifiant la configuration, sans migration de données. Il faut 3 vrais exemples de chaque type.

---

# Phase 2 | Squelette

## ADR-023 | Jeton de session en cookie HttpOnly
- **Date** : 2026-10-23 | **Statut** : Proposée
- **Contexte** : le contrat de Mike retourne `token` + `user`, mais la règle interdit de mettre des identifiants dans `localStorage` ou `sessionStorage`.
- **Décision** : `session-login` pose deux cookies HttpOnly, Secure, SameSite=Lax : `bf_session` (jeton d'accès) et `bf_refresh` (limité à `/.netlify/functions`). Le corps renvoie quand même `{ token, user }` pour respecter le contrat. Le front garde le jeton en mémoire seulement. `session-me` rafraîchit la session quand le jeton est expiré.
- **Conséquences** : le front est greffable tel quel. Si Mike stocke son jeton autrement, on adapte seulement `lib/session.js`.

## ADR-024 | Format des Netlify Functions
- **Date** : 2026-10-23 | **Statut** : À confirmer
- **Décision** : modules ESM `.mjs` qui exportent `handler(event, context)` (format classique, réponse `{ statusCode, headers, body }`). Les dépendances sont injectables en 3e argument, pour les tests.
- **Conséquences** : le format exact des fonctions de Mike (v1 `handler` ou v2 `Response`) est inconnu. La conversion serait mécanique.

## ADR-025 | Impersonation
- **Date** : 2026-10-23 | **Statut** : Proposée
- **Décision** : `session-me?impersonate=<employe_id>`, réservé à « Admin tout » et journalisé dans `journal_audit`. L'interface prend l'identité de la cible (`masterImpersonation` renseigné), mais les données restent lues avec le JWT de l'admin.
- **Conséquences** : c'est une vue « comme si », pas un vrai changement de droits. Un vrai test de la vue d'un vendeur demande un compte de test.

## ADR-026 | Liaison des comptes
- **Date** : 2026-10-23 | **Statut** : Proposée
- **Décision** : un admin crée la fiche `employes` (courriel réel), puis invite le courriel dans Supabase Auth. Au premier login, `hvac_session()` lie le compte à la fiche par courriel. Aucune clé `service_role` n'est nécessaire.

## ADR-027 | Données de démo
- **Date** : 2026-10-23 | **Statut** : Acceptée
- **Décision** : `supabase/seed.sql` contient 10 employés (Simon et Mike en « Admin tout », les autres FICTIFS), 6 clients, des marques et des produits **inventés** (Boréal Climat, Nordika, Ventimax) pour qu'aucun prix ne soit confondu avec un vrai prix fournisseur, 2 kits, 2 devis (un accepté, un en attente d'approbation), un projet, un BT, une facture de dépôt payée et un contrat d'entretien. Courriels en `@exemple.invalid`, à remplacer avant d'inviter les gens.
- **Conséquences** : les devis et la facture de démo consomment de vrais numéros de séquence (exigence « numérotés dès le départ »).

## ADR-028 | CI
- **Date** : 2026-10-23 | **Statut** : Proposée
- **Décision** : GitHub Actions lance `npm test` (36 tests) et `tests/sql/run.sh` sur un service `postgres:16` (schéma, session, seed). Aucun secret n'est nécessaire.

## ADR-029 | Org Supabase de Simon
- **Date** : 2026-10-22 | **Statut** : Acceptée
- **Contexte** : `CLAUDE.md` désignait `Belleflamme-adm's Org` comme l'org de Mike. Le connecteur Supabase de la session ne voit que cette org (plan Free, projets « Belleflamme-adm's Project » et « Signature-courriel », tous deux en `us-east-1`).
- **Décision** : Simon confirme que `Belleflamme-adm's Org` lui appartient. `CLAUDE.md` est corrigé. Le nom de l'org Supabase de Mike reste à confirmer.
- **Conséquences** : le plan Free permet seulement 2 projets actifs (doc Supabase, Billing FAQ), et la limite est déjà atteinte. Pour créer le projet HVAC dédié, il faut mettre un projet en pause ou passer à un plan payant. C'est la décision de Simon.

## ADR-030 | Pas de projet Supabase pour l'instant
- **Date** : 2026-10-22 | **Statut** : Acceptée
- **Décision** : Simon préfère attendre. Le développement continue sur le Postgres local et la CI. Aucun projet n'est mis en pause et aucun plan n'est acheté.
- **Conséquences** : les modules de la Phase 3 sont testés en local et en CI. Le projet `ca-central-1` sera créé plus tard, après une nouvelle vérification du compte et l'OK de Simon.

---

# Phase 3 | Module Clients + Devis

## ADR-031 | Règles du devis confirmées par Simon
- **Date** : 2026-10-22 | **Statut** : Acceptée
- **Décision** :
  1. **Rabais sur un kit** : aucun plafond automatique ni délégué. Simon ou Mike décide au cas par cas (approbation obligatoire dès 0,01 %).
  2. **Taxes** : calculées sur le montant global du devis (confirme ADR-018).
  3. **Validité** : 30 jours à partir de l'**envoi** (paramètre `validite_devis_jours`). Ensuite, le devis est expiré : impossible de l'accepter, il faut le renouveler (nouveau numéro, mêmes lignes, rabais hors plafond à réapprouver).
- **Conséquences** : l'expiration est calculée à la lecture (vue `devis_v`, colonne `statut_effectif`), sans tâche planifiée ni clé `service_role`.

## ADR-032 | Prix imposé par le catalogue
- **Date** : 2026-10-22 | **Statut** : Acceptée
- **Contexte** : si le vendeur peut saisir le prix d'un produit, il peut baisser le prix au lieu de donner un rabais, et contourner le plafond.
- **Décision** : pour une ligne liée à un produit ou à un kit, la base impose le prix du catalogue (trigger). Seules les lignes libres ont un prix saisi.
- **Conséquences** : **risque résiduel** : une ligne libre peut servir à contourner le contrôle (ex. « crédit » saisi comme ligne libre). Le prix d'une ligne libre ne peut pas être négatif. À surveiller avec un rapport des lignes libres par vendeur. Plus tard, on pourra exiger une approbation pour les lignes libres au-dessus d'un montant.

## ADR-033 | Devis en PDF par le navigateur
- **Date** : 2026-10-22 | **Statut** : Proposée
- **Décision** : `/devis-imprimer?id=` produit une page imprimable que le navigateur enregistre en PDF. Aucune librairie PDF, aucune fonction serverless. Un bandeau « DOCUMENT DE DÉMONSTRATION » s'affiche tant que `MODE_DEMO` est vrai (`public/js/bf-entreprise.js`).
- **Conséquences** : l'envoi automatique du PDF par courriel n'est pas couvert. Chez Mike, il existe des fonctions `generate` (8) et des modèles de courriel : à réutiliser lors de la greffe.

## ADR-034 | Demandes d'approbation
- **Date** : 2026-10-22 | **Statut** : Acceptée
- **Décision** : le vendeur demande l'approbation ligne par ligne, avec un motif obligatoire. Le rabais et le plafond sont recopiés de la ligne par la base, jamais du formulaire. Simon et Mike voient les demandes en attente en haut de la page Devis.
- **Conséquences** : aucune notification push ni courriel pour l'instant (la cloche `notif-bell-unified` de Mike servira lors de la greffe).

## ADR-035 | Prix de l'installation : coût du sous-traitant + marge
- **Date** : 2026-10-22 | **Statut** : Acceptée (taux à fixer)
- **Décision** (Simon) :
  1. **Prix client = coût / (1 − marge)**, avec une marge sur le **prix de vente** et non une majoration du coût. Exemple : 1 000 $ à 30 % donne 1 428,57 $.
  2. **Coût** : la grille du sous-traitant par type de travail (`tarifs_sous_traitants`), ou une **soumission** propre au job (coût + numéro de soumission obligatoires).
  3. **Un taux de marge unique**, `marge_installation_bp`, modifiable par Simon ou Mike seulement. **Valeur provisoire : 30 %.**
  4. **Aucun rabais** sur l'installation sans l'approbation de Simon ou Mike (plafond 0 %).
- **Règles en base** : prix, coût (grille) et marge imposés par le trigger. La marge est figée sur la ligne à sa création : changer le taux ne touche pas les devis existants. Un tarif ne se modifie pas, on ajoute un tarif daté. Les techniciens ne voient pas la grille.
- **Conséquences** : les kits ne contiennent plus de main-d'oeuvre ; l'installation est une ligne séparée. Le coût et la marge s'affichent dans l'écran du devis (usage interne), jamais sur le PDF du client.
- **Risque** : une soumission saisie trop basse donne un prix trop bas. La vraie protection viendra en facturation : comparer la facture réelle du sous-traitant au coût du devis (rapport de marge réelle par projet).
- **À confirmer** : le taux réel de la marge ; le prix quand l'installation est faite par **nos employés** (ADR-005) plutôt que par un sous-traitant.

## ADR-036 | Marge par défaut de 25 % et installation par sous-traitants seulement
- **Date** : 2026-10-22 | **Statut** : Acceptée
- **Décision** (Simon) :
  1. Marge par défaut sur l'installation : **25 % du prix de vente** (remplace la valeur provisoire de 30 % de l'ADR-035). Mike et Simon la fixent et l'ajustent dans la page Grille d'installation. Exemple : un coût de 1 000 $ donne 1 333,33 $.
  2. **Aucun employé n'installe** : toute installation est faite par un sous-traitant. Le sous-traitant est obligatoire sur chaque ligne d'installation, même pour une soumission (contrainte en base).
- **Conséquences** : si Belleflamme engage un jour des installateurs, on créera une liste de prix interne (nouveau type de source de coût). Rien n'est à prévoir d'ici là.
- **Interprétation à confirmer** : « 25 % par-dessus » est lu comme une **marge de 25 % du prix de vente** (choix de Simon dans l'ADR-035). Une majoration de 25 % du coût donnerait plutôt 1 250 $.

---

# Phase 3 | Processus d'installation (méthode Belleflamme), en cours de définition

## ADR-037 | Flux devis -> commande -> installation par sous-traitant
- **Date** : 2026-10-22 | **Statut** : Acceptée (détails à préciser)
- **Flux décrit par Simon** :
  1. Visite pré-installation avec le formulaire existant de Mike, puis devis.
  2. Au devis, on attitre le sous-traitant du secteur : ses prix de grille (plus la marge) donnent le prix de l'installation.
  3. Le client accepte : le devis devient une commande, avec un projet, un **bon de travail** pour le sous-traitant et un **bon de commande** pour le matériel.
  4. Le sous-traitant inscrit **lui-même** ses disponibilités dans l'app. Belleflamme place la job dans une journée disponible, et le sous-traitant confirme.
  5. Le sous-traitant reçoit une alerte : date, client, produits.
  6. Matériel : ramassé chez le fournisseur (« Jayco », nom à confirmer) s'il est disponible, sinon à l'entrepôt de Saint-Jérôme.
- **Décisions** :
  - **Accès des sous-traitants** : un compte limité à l'app (rôle « Sous-traitant »), qui voit seulement ses jobs, ses disponibilités et ses produits. Une entente de confidentialité est requise (Loi 25), puisqu'il voit le nom, l'adresse et le téléphone du client. À valider par un professionnel.
  - **Secteurs** : chaque sous-traitant choisit, par ville du Québec, entre **accepte**, **accepte avec supplément** ou **refuse**.
  - **Planification** permise une fois le **dépôt payé** ou le **financement approuvé** (Financeit). Le solde reste dû 72 h avant l'installation.

## ADR-038 | Secteurs des sous-traitants, supplément, carte, alertes
- **Date** : 2026-10-22 | **Statut** : Acceptée
- **Décisions** (Simon) :
  1. **Ville acceptée par plusieurs sous-traitants** : Simon ou Mike désigne un **sous-traitant principal** par ville, les autres servent de remplacement. Le devis prend le principal par défaut.
  2. **Supplément de ville** : montant fixe par sous-traitant et par ville, **ajouté au coût avant la marge**. Le client paie le supplément et la marge dessus. Exemple : 650 $ + 150 $ = 800 $ de coût, donc 1 066,67 $ avec 25 %.
  3. **Carte cliquable du Québec dès la première version** (pas de liste d'abord).
  4. **Alertes** : notification de l'app, SMS et courriel.
- **Source des limites municipales** : jeu « Découpages administratifs » du MRNF sur Données Québec, licence CC-BY 4.0 (attribution obligatoire), offert en SHP, FGDB et GPKG, sans GeoJSON provincial. Il faudra le convertir et le simplifier pour le web. Le MRNF précise que ces limites n'ont pas de valeur légale. Vérifié le 22 oct. 2026.
- **Conséquences** : la carte est le morceau le plus long du module. Le SMS demande un compte payant (Twilio ou un autre fournisseur, prix à vérifier), au nom de Simon. Le courriel demande un service d'envoi, à choisir.

## ADR-039 | Formats réels de Mike (devis signé et BT)
- **Date** : 2026-10-22 | **Statut** : Constat (actions à confirmer)
- **Source** : 2 PDF fournis par Simon, analysés dans `docs/reference/FORMATS-MIKE.md`. Les PDF ne sont pas versés au repo : ils contiennent des renseignements personnels.
- **Constats** :
  - Numéro de devis : entier global à 6 chiffres.
  - Code projet : `[SUCC][DIV]-[PRÉ]-[NOM]-[NNN]`.
  - BT : `BT#RV001 <projet>`, créé en brouillon à l'acceptation, avec toutes les lignes du devis, la localisation en entrepôt et l'état de réservation.
  - Le devis compte une ligne « rabais supplémentaire » négative, des clauses en lignes à 0 $, une signature électronique avec IP et 12 conditions générales.
- **Remplace** : les formats provisoires de l'ADR-022, dès que Simon aura confirmé les points ouverts (sens de `NNN`, numéro de départ des devis HVAC).

## ADR-040 | Code projet Belleflamme
- **Date** : 2026-10-22 | **Statut** : Acceptée (remplace le format projet provisoire de l'ADR-022)
- **Décision** (Simon) : `[SUCC][DIV]-[3 lettres prénom]-[3 lettres nom]-[NNN]`, ex. `STV-JEA-TRE-001`. Le code est attribué à chaque **devis**, et `NNN` compte les devis : 001 pour le 1er, 002 pour le 2e, etc. Le projet issu d'un devis accepté reprend son code.
- **Règles techniques ajoutées par Claude** (à valider par Simon) :
  1. Le compteur est tenu **par préfixe** (ex. `STV-JEA-TRE`), et non par client : Jean et Jeanne Tremblay ne recevront jamais le même code. Pour un client seul, le résultat est identique (001, 002...).
  2. Les lettres sont en majuscules, sans accents ni tirets ni apostrophes (`Pierre-Luc` = PIE, `O'Brien` = OBR). Un nom de moins de 3 lettres est complété avec X (`Li` = LIX).
  3. Pour une entreprise sans prénom, le nom de l'entreprise remplace le prénom.
  4. Le client d'un devis ne peut plus être changé (le code en dépend) : on crée un nouveau devis.
  5. Un renouvellement de devis reçoit un nouveau code (002...), puisque c'est un nouveau devis.
- **Implémentation** : `app.code3`, `app.prochain_code_projet` (compteurs sans trou, jamais décrémentés), `public/js/bf-project-code.js` (mêmes règles, testées des deux côtés).

## ADR-041 | Extension d'un devis renouvelé (-E01)
- **Date** : 2026-10-22 | **Statut** : Acceptée (remplace le point 5 de l'ADR-040)
- **Décision** (Simon) : un devis renouvelé (souvent parce qu'il a expiré) **garde son code projet**, auquel on ajoute une extension : `STV-JEA-TRE-001-E01`, puis `-E02`.
- **Règles** :
  - Les extensions sont comptées par devis d'origine. Renouveler une extension donne l'extension suivante de l'origine (E02), jamais `-E01-E01`.
  - Chaque devis d'origine a sa propre série (`002-E01`).
  - Un nouveau devis qui n'est pas un renouvellement continue la série normale (`004`).
  - Le lien vers l'origine (`devis_origine_id`) ne se modifie pas. Maximum : 99 extensions par devis.
- **Note** : le **numéro** de devis (série globale) change quand même à chaque renouvellement. Seul le code projet est conservé.

## ADR-042 | Rabais global en $ ou en %
- **Date** : 2026-10-22 | **Statut** : Acceptée (le choix entre $ et % reste ouvert, les deux sont permis)
- **Décision** (Simon) : un rabais global sur le devis (comme le « RABAIS SUPPLÉMENTAIRE -200 $ » de l'app de Mike) peut être un **montant** ou un **pourcentage du sous-total**, et il est **toujours** approuvé par Simon ou Mike.
- **Règles en base** :
  - Ligne de type `rabais`, au plus une par devis dans l'écran. Le montant négatif est calculé par la base, jamais saisi.
  - En %, le rabais suit le sous-total quand les autres lignes changent.
  - Le rabais réduit le sous-total **avant** les taxes, comme chez Mike.
  - Le total ne peut pas devenir négatif.
  - Une approbation couvre le mode et la valeur approuvés, ou moins. Augmenter le rabais ou changer de mode ($ vers %) exige une nouvelle approbation.
  - Seule la ligne `rabais` peut être négative : une ligne libre négative (« crédit déguisé ») est refusée.
- **Conséquences** : la facture devra accepter cette ligne négative (module facturation).

## ADR-043 | Numéro de devis : la série de Mike
- **Date** : 2026-10-22 | **Statut** : Acceptée (remplace le format provisoire de l'ADR-022 pour les devis)
- **Décision** (Simon) : même série que l'app de Mike : un entier global, sans préfixe, affiché `#120815`.
- **Précaution de Claude** : tant que l'app HVAC est autonome et sur données fictives, le compteur commence à **900001**. Sinon, un devis de démonstration pourrait porter le même numéro qu'un vrai devis de Mike. À la greffe, le compteur est aligné sur le prochain numéro réel de Mike (sans jamais reculer).
- **Conséquences** : à la greffe, c'est l'app de Mike qui attribue les numéros. Les devis de démonstration (900001 et plus) ne migrent pas.

---

# Phase 3 | Lot A : sous-traitants

## ADR-044 | Compte sous-traitant, territoire, principal, disponibilités
- **Date** : 2026-10-22 | **Statut** : Livrée (en local)
- **Décisions d'implémentation** :
  - Nouveau rôle **« Sous-traitant »**, rattaché à un fournisseur. Il voit **seulement** sa fiche, son entreprise, sa grille de prix, les municipalités, son territoire et ses disponibilités. Il ne voit ni produits, ni coûts, ni marge, ni clients, ni devis, ni autres employés (RLS, testée).
  - **Territoire** : par municipalité, `accepte`, `supplement` (montant obligatoire) ou `refuse`. Le sous-traitant le remplit lui-même, et la coordination peut le corriger. Chaque changement est journalisé.
  - **Principal** par municipalité : désigné par la planification (Admin tout, Direction, Coordonnateur), seulement parmi les sous-traitants qui desservent la ville. Si le principal refuse ensuite la ville, la ville perd son principal et l'app le signale.
  - **Disponibilités** : par journée, saisies par le sous-traitant lui-même. Les journées passées ne se modifient pas. Les vendeurs et la planification les consultent.
  - **Devis** : la liste des sous-traitants est filtrée selon la municipalité du lieu d'installation, avec le principal en premier et sélectionné. Le **supplément de ville** est ajouté au coût avant la marge (grille seulement : une soumission inclut le déplacement). Un sous-traitant qui refuse la ville est bloqué par la base.
  - Le lieu d'installation a maintenant une **municipalité officielle** (`sites.municipalite_code`). Sans elle, le territoire ne peut pas être vérifié et l'app l'indique.
- **Création d'un compte sous-traitant** : la planification crée l'entreprise et la fiche du contact, puis Simon l'invite dans Supabase Auth (ADR-026). **Avant l'accès, une entente de confidentialité doit être signée (Loi 25)**, à valider par un professionnel.

## ADR-045 | Carte du territoire en SVG maison
- **Date** : 2026-10-22 | **Statut** : Livrée (en attente des données officielles)
- **Décision** : carte dessinée en SVG à partir d'un GeoJSON local (`public/data/municipalites.geojson`), avec zoom à la molette ou au pincement, déplacement, clic pour sélectionner et recherche d'une ville. **Aucune librairie ni tuile externe** : aucune donnée ne sort vers un tiers, la politique de sécurité du site (CSP) reste stricte, et la carte fonctionne hors ligne dans la PWA.
- **Données** : `scripts/municipalites/convertir.mjs` convertit la couche officielle (SHP, « Découpages administratifs », MRNF, CC-BY 4.0), la simplifie avec mapshaper 0.7.71 et produit le GeoJSON et une migration SQL des municipalités. Les champs sont détectés, sinon le script s'arrête et les affiche (on ne devine pas).
- **Blocage** : le réseau de l'environnement cloud refuse `www.donneesquebec.ca`. Il faut que Simon autorise ce domaine, ou qu'il fournisse le fichier SHP. Aucune limite inventée n'est versée au repo.
- **Conséquences** : la carte se teste aujourd'hui avec une grille synthétique (hors repo). L'attribution CC-BY est affichée sous la carte.

## ADR-046 | Format du bon de commande de Mike
- **Date** : 2026-10-22 | **Statut** : Constat (détails à confirmer)
- **Source** : captures d'écran fournies par Simon (BC d'un projet Foyer), analysées dans `docs/reference/FORMATS-MIKE.md` §4. Les adresses courriel des employés et les noms de clients ne sont pas notés.
- **Constats** :
  - N° BC = préfixe du code projet + série à partir de 100 (`BC#DRF-JEA-TRE-100`).
  - Le BC est au **coût**, avec TPS et TVQ.
  - Statuts observés : « Reçu » (les autres sont à confirmer).
  - Il est envoyé par courriel au fournisseur, avec son PDF, un fil de conversation et un bouton d'annulation.
  - Livraison à l'entrepôt de Saint-Jérôme, date de livraison « TBD » tant qu'elle n'est pas confirmée.
- **Pour le Lot B** : le BC HVAC reprend ce format, avec un choix de livraison de plus : entrepôt, ou **ramassage chez le fournisseur par le sous-traitant**.

## ADR-047 | Règles du Lot B (commande, BT, BC, planification)
- **Date** : 2026-10-22 | **Statut** : Acceptée
- **Décisions** (Simon) :
  1. **N° de BC** : préfixe du code projet + série 100, 101, 102..., avec un compteur sans trou par préfixe, distinct de celui des devis.
  2. **Création du BC** : un brouillon automatique est créé à partir du BT à l'acceptation du devis : les produits à commander, **au coût**, avec un BC par fournisseur. La coordination le vérifie, puis l'envoie.
  3. **Matériel** : choisi sur chaque BC, entre **ramassage chez le fournisseur par le sous-traitant** et **livraison à l'entrepôt de Saint-Jérôme** (le sous-traitant y ramasse alors le matériel).
  4. **Date d'installation** : placée par Belleflamme dans une journée **disponible** du sous-traitant, elle est **confirmée automatiquement**. Le sous-traitant reçoit seulement une alerte.
- **Rappels** :
  - La planification est permise une fois le dépôt payé ou le financement approuvé (ADR-037).
  - Le solde est dû 72 h avant l'installation (ADR-009).
  - Les alertes passent par l'app, le SMS et le courriel. Les fournisseurs de SMS et de courriel restent à choisir : en attendant, les envois sont mis en file sans être expédiés.

## ADR-048 | Lot B, partie base de données
- **Date** : 2026-10-22 | **Statut** : Livrée (en local), écrans à venir
- **À l'acceptation d'un devis**, la base crée elle-même, sans dépendre du front :
  - le **projet** ;
  - le **BT `RV001 <code projet>`** en brouillon : produits (kits dépliés en composantes), installation et services, avec le sous-traitant du devis ;
  - un **BC en brouillon par fournisseur** pour les produits à commander, au coût, avec le fournisseur du produit ou, à défaut, celui de sa marque. Le BC est en ramassage par le sous-traitant s'il y en a un, sinon livré à l'entrepôt.
- **BC** :
  - Numéro `préfixe-100`, puis 101..., attribué par un compteur sans trou.
  - Statuts permis : brouillon -> envoyé -> confirmé -> reçu, et annulation possible avant la réception.
  - Lignes figées dès l'envoi, totaux et taxes calculés par la base, aucune suppression.
- **Planification** (`hvac_planifier_bt`) : réservée à la planification. Elle exige un sous-traitant assigné, une journée **disponible** de ce sous-traitant, et un dépôt payé **ou** un financement approuvé. La date est confirmée automatiquement, le projet reçoit la date d'installation (le solde est dû 72 h avant), et une notification avec un courriel et un SMS est mise en file.
- **Jobs du sous-traitant** (`hvac_mes_jobs`) : seulement les jobs planifiées. Il voit le nom et le téléphone du client, l'adresse, les lignes, et où ramasser le matériel. Chaque accès est journalisé (Loi 25). Il fait passer la job à « en cours », puis « terminée ».
- **Fournisseurs** : ajout de l'adresse (lieu de ramassage).
- **Données de démo** : le devis accepté produit automatiquement le projet, le BT RV001 et le BC `ROV-JUL-TRE-100`.

## ADR-049 | Séquence HVAC confirmée : pré-installation avant le devis, BT et BC après le paiement
- **Date** : 2026-10-22 | **Statut** : Livrée (en local)
- **Séquence** (Simon, mot pour mot) : « Lead, visite/pré-installation, devis, acceptation, dépôt/financeit, BC, BT, cédule job, paiement finale 72h avant la job si dépot 40% et non financeit, installation, facturation, paiement sous-traitant ».
- **Décisions** :
  1. La visite de pré-installation est faite **par le vendeur, avant le devis** (confirme l'ADR-007, tranche le constat de `FORMATS-MIKE.md` §5). Un devis ne s'envoie pas sans visite réalisée et liée (`devis.inspection_id`). Paramètre `exiger_preinstallation`, à `true` par défaut.
  2. Le formulaire HVAC reprend les sections de Mike **sauf la section 8** (« pièces supplémentaires à apporter ») : la visite précède le devis, donc tout va directement au devis.
  3. **À l'acceptation**, la base crée seulement le projet, au statut `attente_paiement`.
  4. **Au dépôt payé** (facture de type dépôt) **ou au financement Financeit approuvé**, la base crée le BT `RV001` et les BC brouillons, une seule fois, et le projet passe à « à cédule ». Remplace le point 2 de l'ADR-047 et le premier point de l'ADR-048.
  5. **Solde 72 h avant** : seulement pour la voie dépôt 40 %. Un projet financé par Financeit n'a aucune date de solde.
- **Retour arrière** : la migration `20261024000200_sequence_hvac.sql` redéfinit les fonctions, on la retire et on rejoue les migrations en local. Pour garder l'ordre sans bloquer l'envoi, mettre `exiger_preinstallation` à `false`.

## ADR-050 | Carte du territoire : noms des régions, des MRC et des villes
- **Date** : 2026-10-22 | **Statut** : Livrée (en local)
- **Demande** (Simon) : afficher le nom du territoire et des villes, au moins les grandes villes connues, pour que le sous-traitant choisisse facilement.
- **Décisions** :
  1. L'affichage dépend du zoom. De loin, on voit les **régions administratives** (Laurentides, Lanaudière, Laval...) et les **villes repères**. En zoomant, on voit les **MRC**, puis le nom de chaque municipalité dès qu'il tient dans sa forme.
  2. Les étiquettes ne se chevauchent jamais. Ordre de priorité : grandes villes, régions, villes secondaires, MRC, autres municipalités. Une étiquette coupée par le bord n'est pas affichée.
  3. Un trait plus épais marque les frontières entre régions.
  4. Villes repères : `public/data/villes-reperes.json`, tenu à la main (1 = toujours nommée, 2 = en priorité). La couche officielle ne donne pas la population, d'où cette liste.
  5. Le GeoJSON garde la MRC et la région de chaque municipalité, tirées de la couche officielle. L'infobulle affiche « Ville (MRC, région) ».
- **À confirmer** : par « territoire », Simon voulait-il dire la région, la MRC, ou un nom de secteur propre au sous-traitant ?

## ADR-051 | Limites municipales officielles dans la carte du territoire
- **Date** : 2026-10-22 | **Statut** : Livrée (en local)
- **Source** : « Découpages administratifs 1/100 000 (SHP) », MRNF, Données Québec, licence CC-BY 4.0, version `V2026-09`, téléchargée le 22 oct. 2026. Couche `munic_s`, champs `MUS_CO_GEO` (code), `MUS_NM_MUN`, `MUS_NM_MRC` et `MUS_NM_REG`. Le zip et les SHP ne sont **pas** versés au dépôt.
- **Traitement** (`scripts/municipalites/convertir.mjs`) : reprojection WGS84 et simplification à 4 %, puis **fusion par code** (2 260 polygones donnent 1 331 municipalités, territoires non organisés et réserves compris). Résultat : `public/data/municipalites.geojson` (3,2 Mo) et la migration `20261024000201_municipalites_donnees.sql`.
- **Carte** : elle s'ouvre sur le sud du Québec, de l'Outaouais à Québec et à l'Estrie, et des boutons mènent au « Sud du Québec » ou à « Tout le Québec ». La recherche affiche « Nom (MRC) », parce que 56 noms reviennent plus d'une fois. Les 46 villes repères correspondent toutes aux noms officiels.
- **Mise à jour** : chaque automne, relancer le script sur la nouvelle version du MRNF. Les domaines `donneesquebec.ca` et `diffusion.mern.gouv.qc.ca` doivent être permis dans l'environnement.

## ADR-052 | La carte du territoire est un outil de saisie occasionnel
- **Date** : 2026-10-22 | **Statut** : Acceptée
- **Contexte** (Simon) : le sous-traitant indique sur la carte où il va, où il ne va pas, et où il demande un supplément. Il la modifie lui-même, de son bureau, environ 2 à 4 fois par année. Pour Belleflamme, c'est ensuite une référence qui sert à choisir le sous-traitant et à établir le prix au client.
- **Décisions** :
  1. On ne fait aucune optimisation de poids pour le téléphone : le fichier des limites (3,2 Mo) est acceptable pour un usage de bureau aussi rare.
  2. L'usage quotidien passe par le devis. Le supplément de la ville du chantier est appliqué automatiquement à la ligne d'installation, puis figé (ADR-035 et ADR-038). Une modification du territoire ne change donc pas les devis déjà faits.
  3. Chaque modification est déjà journalisée (`trg_audit`).

## ADR-053 | Est de l'Ontario dans la carte du territoire (150 km d'Ottawa)
- **Date** : 2026-10-22 | **Statut** : Livrée (en local)
- **Demande** (Simon) : couvrir l'Est ontarien, dans un rayon de 150 km autour d'Ottawa, avec un sous-traitant ontarien qui détient ses propres cartes TSSA et licences.
- **Source** : « Municipal Boundary - Lower and Single Tier », Land Information Ontario (service public `ws.lioservices.lrc.gov.on.ca`), sous la Licence du gouvernement ouvert de l'Ontario. Les noms sont pris en français quand le service les fournit. Le fichier de Statistique Canada a été écarté parce que son serveur bloque les téléchargements automatisés.
- **Traitement** (`scripts/municipalites/ontario.mjs`) :
  - Le script interroge le service par lots d'identifiants, fusionne les morceaux par `MUNID` et simplifie à 4 %.
  - Il garde les municipalités dont une partie est à moins de 150 km de la colline du Parlement : 66 municipalités, 0,05 Mo.
- **Modèle** :
  - Ajout de la colonne `municipalites.province` (`QC` ou `ON`).
  - Les codes ontariens sont préfixés `ON-`, ce qui rend toute collision avec un code québécois impossible ; une contrainte de la base le garantit.
  - Les comtés (Prescott et Russell, Renfrew...) tiennent lieu de MRC, et la région s'appelle « Est de l'Ontario ».
- **Carte** : elle charge les deux fichiers. La vue de départ va de Pembroke à Québec. 13 villes ontariennes sont ajoutées aux repères (Ottawa, Cornwall, Hawkesbury...).
- **Hors carte** (décidé par Simon, à faire) :
  - TVH 13 % par une case à cocher sur le devis.
  - Exemption autochtone par une case aussi, comme dans l'app de Mike.
  - LogisVert pour le Québec seulement, et les programmes ontariens s'il y en a.
  - App bilingue français-anglais pour les sous-traitants.

## ADR-054 | Taxes TVH Ontario et client autochtone (en veille)
- **Date** : 2026-10-22 | **Statut** : Livrée en local, **en veille** (ADR-055) : l'app de Mike a déjà ces deux cases sur son devis.
- Deux cases sur le devis, comme chez Mike :
  - « Vente Ontario », pour la TVH à 13 % (taux `TVH_ON` daté du 2010-07-01). Elle est précochée quand le chantier est en Ontario.
  - « Client autochtone », pour une vente sans taxes. Elle est précochée quand le client a l'exemption `autochtone`.
- Les taxes sont figées après le brouillon. Un devis n'est pas envoyé si la case Ontario ne correspond pas à la province du chantier. La facture reprend les cases du devis.
- **À valider par le comptable** : la TVH pour un client autochtone et les pièces à conserver.
- Migration `20261024000400_taxes_ontario_autochtone.sql`, tests `90_taxes.test.sql`.

## ADR-055 | Recentrage : CRM des leads et espace sous-traitants
- **Date** : 2026-10-22 | **Statut** : Acceptée (Simon)
- **Constat** : la soumission, le devis, les taxes (Québec, Ontario, autochtone), la facturation, le formulaire de pré-installation et le calendrier (Pointage) **existent déjà dans l'app de Mike**. On ne les refait pas.
- **Ce que NOTRE app construit** :
  1. **CRM des leads**. Parcours : Google ou Facebook, puis Monday (CRM actuel), puis notre app.
     - Le vendeur voit le lead arriver et le prend en charge.
     - Chaque contact est tracé (appel, courriel, texto) et la **rapidité d'exécution est mesurée** : délai avant la prise en charge, délai avant le premier contact, et canal de ce contact.
     - Après la conversation, le vendeur planifie la visite **dans Pointage de Mike**.
     - La suite se passe chez Mike : formulaire de pré-installation, devis, acceptation.
  2. **Espace sous-traitants**, géré par le directeur des opérations :
     - il crée les sous-traitants et leur donne accès ;
     - chaque sous-traitant a **sa carte** : villes acceptées, refusées, avec supplément ;
     - chaque sous-traitant a **sa liste de prix**. Simon définit les types de travaux, le sous-traitant remplit ses prix dans l'app, Simon approuve, et chaque version est conservée avec sa date.
- **Modules en veille** : devis, pré-installation, projets, BT et BC, catalogue, appels de service, subventions, facturation, assistant, jobs du sous-traitant.
  - Ils restent **visibles, grisés et inactifs** (« En veille | app de Mike »), regroupés à la fin.
  - Leur code et leurs tests sont **conservés**. Pour en réactiver un, on remet `etat: 'actif'` dans `public/js/bf-tuiles.js`.
  - Rien n'est supprimé sans l'accord écrit de Simon (garde-fou 5).

## ADR-056 | CRM des leads : board principal, tour de rôle, rapidité et tableau de quantification
- **Date** : 2026-10-22 | **Statut** : Base de données livrée (en local), écrans à venir
- **Parcours** (Simon) : Google ou Facebook, puis Monday, puis le **board principal** de l'app.
  - Le board principal est la vérité. Le vendeur a **sa vue**, avec seulement ses leads (imposé par la RLS).
  - Le board principal est visible par Admin tout, Direction, Gérant et Coordonnateur.
- **Attribution** : à tour de rôle entre les vendeurs actifs du board (`crm_vendeurs`, par ordre). Un seul vendeur reçoit tout ; avec deux ou trois vendeurs, c'est 1, 2, 3, 1... Le pointeur est verrouillé à chaque attribution, et l'attribution est journalisée. Seul le board principal réattribue un lead.
- **Journal du vendeur** (`lead_activites`) : prise en charge, appel (joint, message laissé ou pas de réponse), courriel, texto, note, visite planifiée, perdu (avec raison), réouverture.
  - On ne fait qu'ajouter : rien ne se modifie ni ne se supprime.
  - **L'heure est celle de la base**, jamais celle du téléphone, et le vendeur ne peut pas antidater.
  - Le statut du lead avance tout seul : nouveau, pris en charge, contacté, visite planifiée.
- **Rapidité** (`leads_v`, `crm_rapidite_v`) : délai de prise en charge, délai du premier contact et canal utilisé, taux de leads contactés, taux de premiers contacts par appel, taux de visites.
- **Tableau de quantification** (`crm_objectifs`, demandé par Simon) :
  - Pour chaque indicateur, Simon et Mike inscrivent un seuil « bon » et un seuil « moyen ».
  - `crm_evaluation_v` compare chaque vendeur et le classe **bon**, **moyen** ou **à améliorer**.
  - Tant que les seuils sont vides, le vendeur est « non évalué » ; ils seront quantifiés au fil des semaines.
  - Un lead est « en retard » quand le seuil du premier contact est dépassé.
- **Visite** : planifiée dans **Pointage** (app de Mike) ; le CRM garde la date (lien `url_pointage`, aucune connexion).
- **Monday** : l'entrée des leads reste désactivée (`MONDAY_ENABLED=false`, garde-fou 4). Les colonnes du board « Lead » de Monday sont à confirmer (`docs/MAPPING.md`).
- **À noter** : les délais sont calculés en minutes réelles, sans tenir compte des heures d'ouverture. Un lead reçu à 23 h paraîtra lent le lendemain matin. À décider avec Simon (heures ouvrables ou non).

## ADR-057 | Style visuel calqué sur l'app de Mike
- **Date** : 2026-10-22 | **Statut** : Livrée (en local)
- **Demande** (Simon, avec des captures de l'app de Mike) : la portion HVAC doit avoir le même style que l'app de Mike.
- **Repris de l'app de Mike** :
  - un filet et un bandeau verts ;
  - à l'accueil, une couverture avec un logo rond au centre, un titre condensé vert et la date ;
  - un **ruban de stats** vert qui défile, avec des chiffres sur pastilles blanches : leads du jour, en attente, en retard, contactés, délai médian, visites ;
  - des **tuiles en liste** : icône sur fond menthe, titre condensé en majuscules, description et chevron ;
  - les groupes qui s'ouvrent en **fenêtre flottante** (comme « Opération ») : « Ventes HVAC », « Sous-traitants » et « Dans l'app de Mike » (en veille, grisée) ;
  - une **barre du bas** avec la recherche (les leads, pour l'instant) et une cloche rouge qui compte les leads en retard.
- **Polices** : Bebas Neue pour les titres et DM Sans pour le texte (Google Fonts, déjà permis par la CSP). Les polices exactes de Mike restent à confirmer ; leur apparence est très proche.
- **Couverture** : un dégradé vert en attendant une vraie photo (`bf-entete-photo` chez Mike). Aucune photo de personne n'est versée au dépôt.
- **Pas repris** : la météo (Open-Meteo, bloquée par la CSP `connect-src 'self'`), le bouton téléphone (Twilio) et le punch in/out (Pointage).

## ADR-058 | Types de demande et qualifications des vendeurs
- **Date** : 2026-10-22 | **Statut** : Livrée (en local)
- **Demande** (Simon) : certains vendeurs ne sont ni à l'aise ni qualifiés pour certaines demandes, et il ne faut pas « brûler » le client. Simon choisit quels types chaque vendeur peut prendre.
- **Types de demande** : thermopompe murale simple, murale multi, système central, biénergie (`leads.type_demande`).
- **Qualifications** (`crm_vendeur_types`) : une case par vendeur et par type, dans « Rapidité des vendeurs ». Un nouveau vendeur est coché pour tout, et Simon décoche ce qu'il ne doit pas prendre. Ajouts et retraits sont journalisés.
- **Attribution** :
  - Le tour de rôle se fait **entre les seuls vendeurs qualifiés** pour le type, avec **un tour de rôle distinct par type**.
  - Si aucun vendeur n'est qualifié, le lead reste **non attribué** dans le board principal, et Simon choisit.
  - Si le type est inconnu, le lead va à tous les vendeurs actifs. **Comportement à confirmer par Simon.**
- **Board principal** : il corrige le type et réattribue. Le vendeur ne peut faire ni l'un ni l'autre. Une attribution hors compétence reste possible, mais elle est signalée (« vendeur non qualifié »).
- **Technique** : `leads_v` gagne la colonne `vendeur_qualifie`. Les vues `leads_v`, `crm_rapidite_v` et `crm_evaluation_v` sont recréées à l'identique ; ce sont des vues, aucune donnée n'est touchée.

## ADR-059 | HTML de test après chaque modification
- **Date** : 2026-10-22 | **Statut** : Acceptée (Simon)
- `npm run demo` (`scripts/demo/construire.mjs`) emballe les **vraies pages** de `public/` (esbuild) avec un **faux serveur en mémoire** (`scripts/demo/faux-serveur.js`) dans un seul fichier, `demo-build/hvac-test.html`, ignoré par git.
- **La barre de test permet de** :
  - changer d'utilisateur (Simon, vendeurs, sous-traitant) ;
  - avancer l'heure simulée ;
  - faire arriver un lead de Monday.
- **Le faux serveur** imite les règles de la base (tour de rôle par type, horodatage, cotes, visibilité). Les vraies règles restent celles de la base, couvertes par les tests SQL. Le faux serveur sert seulement à tester les écrans.
- Après chaque modification, on le régénère et on le republie au même lien.

## ADR-060 | Liste de prix des sous-traitants : tous les travaux à chiffrer
- **Date** : 2026-10-22 | **Statut** : Livrée (en local)
- **Contexte** : la liste de prix de Mike (section « HVAC | Installation ») ne contient qu'un seul item, `INST-TETE-MULTI`, l'installation additionnelle par tête multizone (prix client de 800 $). Simon veut chaque travail énuméré un par un, avec un prix au bout de la ligne.
- **Liste** : 68 travaux dans 13 catégories, avec une source unique, `scripts/reference/types-travaux.mjs`. Elle génère la migration `20261024000700` et alimente le HTML de test. Les catégories :
  - Thermopompe murale : 1 tête (3 tailles), multizone 2 à 5 têtes, tête additionnelle.
  - Têtes spéciales : cassette, console, gainable.
  - Système central neuf, add-on, climatiseur central.
  - Remplacements : murale, multizone, centrale, fournaises.
  - Biénergie : remplacement d'une fournaise au gaz avec add-on, add-on sur gaz, huile ou propane, contrôle biénergie.
  - Conversion de l'huile, avec retrait du réservoir.
  - Ventilation : échangeur d'air.
  - Extras : ligne au pied, couvre-ligne, supports, pompe, percements, hauteur, accès difficile, thermostat.
  - Conduits : sorties, retours, plenum.
  - Électricité (licence CMEQ) et gaz (licence gaz).
  - Retrait et récupération du réfrigérant.
  - Service et entretien.
- **Unités** : forfait, par tête, par pied, par sortie, par heure, par unité, par livre.
- **Code repris de Mike** : `INST-TETE-MULTI`, pour la correspondance à la greffe.
- **Écran** (Grille d'installation) :
  - On choisit le sous-traitant. Chaque ligne affiche le code, le nom et ce qui est inclus, avec le **coût du sous-traitant au bout** et le **prix client calculé** : coût / (1 - marge).
  - Une recherche filtre les travaux.
  - « Enregistrer les prix » ajoute des tarifs datés, et l'historique est conservé.
  - Simon et Mike peuvent ajouter un travail, avec sa catégorie et son unité.
- **À valider par un professionnel** : ce qui est réservé aux licences (électricité, gaz, halocarbures) et ce qui est inclus dans chaque forfait.
- **Suite prévue** : le sous-traitant remplira lui-même sa liste dans son portail (« Ma liste de prix »), et Simon approuvera.

## ADR-061 | Demande de prix par lien, signée par le sous-traitant, valide un an
- **Date** : 2026-10-22 | **Statut** : Livrée (en local)
- **Demande** (Simon) :
  - On coche les travaux à faire chiffrer par un sous-traitant, sans liste complète obligatoire.
  - Chaque ligne se modifie dans l'app : titre, description, unité.
  - On crée un lien à envoyer. Le sous-traitant le remplit, met son nom, sa signature électronique et la date, et ses prix sont **valides un an complet à partir de la date de signature**.
- **Parcours** :
  1. Dans « Listes de prix des sous-traitants », on choisit le sous-traitant, on coche les travaux (une case par ligne, « tout cocher » par catégorie), on ajoute un message au besoin, puis « Créer la demande de prix ». Admin et planification.
  2. **Le lien est affiché une seule fois** : `…/prix#<jeton>`. Boutons Copier, Courriel (mailto) et Texto (sms).
  3. Le sous-traitant ouvre le lien **sans compte**. Pour chaque ligne, il inscrit son prix ou coche « Je n'offre pas ce service », avec une note s'il le veut. Il inscrit son nom, signe dans le cadre (souris ou doigt) et coche l'attestation de validité d'un an. La date est celle du serveur.
  4. Simon et Mike reçoivent une notification. Sur la page de révision, ils voient les prix donnés, les prix clients calculés, l'écart avec le prix en vigueur, la signature, la date et l'échéance. Ils peuvent **approuver** ou refuser.
  5. À l'approbation, chaque prix devient un **tarif daté du jour de la signature, valide jusqu'à l'échéance d'un an**. La grille affiche l'échéance, en rouge une fois dépassée.
- **Sécurité** :
  - Le jeton fait 64 caractères. **La base n'en garde que l'empreinte SHA-256.** Il voyage dans le fragment `#`, donc il n'apparaît dans aucun journal de serveur, puis dans l'en-tête `X-Jeton`.
  - Le lien expire après 30 jours et ne sert qu'une fois. Une demande annulée désactive le lien.
  - Le public passe seulement par les fonctions de la base `hvac_demande_prix_lire` et `hvac_demande_prix_soumettre`, avec la clé publique. Aucune table n'est ouverte à `anon` et la clé `service_role` n'est pas utilisée.
  - Une fois signée, une demande ne se modifie plus. Les lignes envoyées gardent le texte d'origine même si la liste change ensuite.
  - Tout est journalisé : création, ouverture, signature avec l'adresse IP si elle est disponible, approbation.
- **Envoi automatique par courriel** : plus tard, quand le fournisseur de courriel sera choisi (ADR-038). Pour l'instant, Simon envoie le lien lui-même.
- **Valeur légale** : une signature dessinée avec nom, date et adresse IP est une preuve raisonnable de l'accord sur les prix. Son poids juridique au Québec est **à valider par un professionnel** (Loi concernant le cadre juridique des technologies de l'information).

## ADR-062 | Liste de prix dans le portail du sous-traitant, engagements et renouvellement
- **Date** : 2026-10-22 | **Statut** : Livrée (en local)
- **Demande** (Simon) : oublier le lien HTML. La liste de prix vit dans le dossier de la compagnie de ventilation, et le sous-traitant la modifie quand il veut.
- **ADR-061 en veille** : le parcours par lien signé reste dans le code (`DEMANDES_PAR_LIEN = false` dans la grille), rien n'est effacé.
- **Travaux confiés** : dans la grille, les cases cochées veulent maintenant dire « travaux confiés à ce sous-traitant » (table `travaux_sous_traitants`, admin et planification). Les travaux déjà tarifés sont confiés d'office. Le sous-traitant ne voit et ne chiffre que ses travaux confiés.
- **Portail « Ma liste de prix »** (`/mes-prix`) :
  - Le sous-traitant modifie ses prix. Le nouveau prix est un tarif daté du jour et s'applique aux **nouveaux devis**. Deux changements le même jour remplacent le prix du jour ; l'historique des jours précédents reste intact.
  - Avant d'enregistrer, un panneau montre les **soumissions actives touchées** : numéro, ville, vendeur, travail, prix à honorer et échéance. Après l'enregistrement, le même rapport s'affiche.
  - Une section « Tes soumissions actives » liste tous ses engagements.
  - Soumission active = envoyée et non expirée (à honorer jusqu'à l'échéance), ou acceptée dont le projet n'est pas terminé.
  - Aucun nom de client n'est montré au sous-traitant (Loi 25) : numéro de devis et ville seulement.
- **Avis** : le vendeur de chaque soumission touchée reçoit un avis (le devis garde l'ancien prix, le nouveau s'appliquera au renouvellement). Simon et Mike (Admin tout) reçoivent « Liste de prix modifiée ».
- **Renouvellement** : le devis renouvelé recalcule déjà l'installation au prix en vigueur du sous-traitant attitré. Un déclencheur avise le vendeur de chaque écart avec le devis d'origine pour qu'il le renvoie au client ; la vue `devis_ecarts_prix_v` montre les écarts.
- **Limite connue** : les devis vivent dans l'app de Mike (ADR-055). Le rapport des engagements s'appuie sur nos tables de devis (en veille) jusqu'à la greffe. Chez Mike, chaque ligne d'installation devra porter le type de travail et le sous-traitant pour que ce rapport fonctionne.
- **À décider** : les prix changent tout de suite, sans approbation. Simon est avisé. Une approbation pourra être ajoutée si Simon le demande.

## ADR-063 | Carte comparative des sous-traitants : une couleur chacun, rayures quand ils se chevauchent
- **Date** : 2026-10-22 | **Statut** : Livrée (en local)
- **Demande** (Simon) : en mode « Sous-traitants principaux », voir tous les sous-traitants en même temps, chacun dans sa couleur. Une municipalité desservie par plusieurs est divisée par le nombre de couleurs.
- **Affichage** :
  - Le 2e menu affiche « Tous » par défaut. Choisir un sous-traitant n'affiche que lui.
  - Couleurs automatiques, bien distinctes, sans vert, orange ni rouge (réservés à accepte, supplément, refuse). Elles suivent l'ordre de la liste des sous-traitants (par nom) : un nouveau sous-traitant peut décaler les couleurs des suivants.
  - Plusieurs sous-traitants : **rayures diagonales égales**, une bande par sous-traitant, toujours dans le même ordre. Les bandes gardent la même largeur à l'écran quel que soit le zoom. Un vrai découpage de la forme a été écarté : illisible sur les petites municipalités.
  - « Accepte » : couleur pleine. « Avec supplément » : même teinte, pâle. « Refuse » : n'apparaît pas.
  - Le principal désigné : contour épais, version foncée de sa couleur.
  - Légende : chaque sous-traitant, sa couleur, son nombre de municipalités, et le nombre de municipalités desservies par 2 sous-traitants ou plus.
  - Clic sur une municipalité : liste des sous-traitants qui la desservent, avec leur couleur ; un clic choisit le principal.
- **Données** : `GET territoire?tous=1` rend tous les territoires desservis. Réservé à Belleflamme : un sous-traitant reçoit un refus (403) et la RLS ne lui montrerait que le sien de toute façon.
- **Limite** : vue à l'échelle du Québec, les rayures des petites municipalités de la couronne de Montréal ne se voient qu'en zoomant.

## ADR-064 | Fiche du sous-traitant, modifiable
- **Date** : 2026-10-22 | **Statut** : Livrée (en local)
- **Demande** (Simon) : dans Sous-traitants, cliquer sur un sous-traitant pour ouvrir sa fiche et la modifier au besoin.
- **Champs** :
  - La compagnie : nom, licence RBQ (si disponible), NEQ, téléphone, courriel, adresse.
  - Propriétaire et responsable : nom du propriétaire, nom, téléphone et courriel du responsable.
  - Actif ou non.
- **Règles** :
  - Page `/sous-traitant?id=`. Seuls les champs changés partent au serveur (`PATCH sous-traitant`).
  - Modification réservée à la planification (Simon, Mike, coordination), par la RLS existante. Un vendeur ou le sous-traitant lui-même ne modifie pas la fiche.
  - Licence RBQ : 10 chiffres, enregistrée au format 1234-5678-90, vérifiée par le serveur et par la base. La contrainte ne s'applique qu'aux nouvelles écritures (`not valid`) pour ne pas bloquer d'anciennes données.
  - Courriels vérifiés. Chaque modification est journalisée (Loi 25 : noms et coordonnées de personnes).
  - À la création, le contact qui reçoit l'accès devient le responsable par défaut.
- **Liste** : le nom est un lien vers la fiche, avec un bouton « Fiche ». La ligne montre le responsable, ses coordonnées et la licence RBQ (« RBQ à inscrire » si absente).

## ADR-065 | Registre des versions de la liste de prix, en PDF, avec alerte de fréquence
- **Date** : 2026-10-22 | **Statut** : Livrée (en local)
- **Demande** (Simon) : à chaque enregistrement de la liste de prix d'un sous-traitant, archiver un PDF de la liste complète. La plus récente en premier, avec la date, l'heure et l'auteur. Garder une trace pour discuter avec le sous-traitant s'il change sa liste trop souvent. Pour tous les sous-traitants.
- **Choix de Simon** :
  - Le registre est visible par Belleflamme (tous les sous-traitants) et par chaque sous-traitant (le sien seulement).
  - Une nouvelle version est créée quand un prix change (par le sous-traitant ou par Belleflamme) ET quand un travail confié est ajouté ou retiré.
  - Alerte quand le sous-traitant modifie sa liste 3 fois ou plus en 30 jours (paramètre `seuil_versions_liste_30j`). Simon et Mike reçoivent un avis.
- **Conception** :
  - Chaque version est une **copie figée** en base (`listes_prix_versions`) : toutes les lignes avec leur prix, les changements depuis la version précédente (ajout, retrait, prix avant et après), l'auteur, la date et l'heure, et une **empreinte SHA-256** des lignes.
  - Une version ne se modifie ni ne s'efface jamais (déclencheur), et personne n'y écrit directement (RLS) : seules les fonctions de la base en ajoutent.
  - Aucune version si rien n'a changé. Les modifications du même enregistrement font une seule version.
  - Le **PDF est produit dans le navigateur à partir de la copie figée** (pdf-lib 1.17.1, MIT, copiée dans le repo). La même version donne toujours le même contenu, et l'empreinte est imprimée au bas de chaque page. Stocker des fichiers PDF aurait demandé Supabase Storage pour la même preuve ; on pourra les y copier plus tard si un comptable ou un avocat l'exige.
  - Une version comptée pour l'alerte est une version faite par le sous-traitant. Celles faites par Belleflamme ne comptent pas.
  - Belleflamme qui met un prix sur un travail non confié le confie du même coup. La grille enregistre maintenant tous les prix en un seul appel (`mes-prix`), donc une seule version, et les vendeurs touchés sont avisés comme pour le sous-traitant.
- **Reprise** : la migration crée une première version pour chaque sous-traitant qui a déjà des travaux confiés.
- **À valider par un professionnel** : la valeur de preuve d'un PDF régénéré à partir d'une copie figée avec empreinte, par rapport à un fichier conservé tel quel.

## ADR-066 | Étampes sur les leads, « PERDU » en diagonale sur la fiche
- **Date** : 2026-10-22 | **Statut** : Livrée (en local)
- **Demande** (Simon) : des étampes comme le « ✓ PRÉPARÉ » de l'app de Mike pour le statut du lead et le type de système. Le lead perdu en rouge, gros, et en diagonale sur la fiche. Les emplacements restent les mêmes.
- **Étampes** (`etampe()` dans `bf-crm.js`) : icône SVG + texte en majuscules (Bebas Neue), fond plein, texte blanc.
  - Statuts : Nouveau (violet), Pris en charge (indigo), Contacté (bleu-vert), Qualifié (bleu), Visite planifiée (ambre), Vendu (vert), Perdu (rouge, plus grosse).
  - Types : Murale simple, Murale multi, Système central, Biénergie, Type à préciser, chacun avec son icône et sa couleur.
  - Couleurs foncées choisies pour que le texte blanc reste lisible (contraste 4,5:1). Le vert Belleflamme pâle de l'app ne passe pas ce seuil avec du texte blanc : « Vendu » utilise un vert plus foncé.
- **Fiche du lead perdu** : grande étampe « PERDU » rouge, inclinée, par-dessus la fiche. Le texte et les liens dessous restent lisibles et cliquables.
- Les étampes remplacent les pastilles aux mêmes endroits : liste des leads et titre de la fiche (où le type s'ajoute à côté du statut).

## ADR-067 | Contact du client et historique des communications (appels enregistrés, textos, courriels)
- **Date** : 2026-10-22 | **Statut** : Livrée (en local), branchement à l'app de Mike à faire à la greffe
- **Demande** (Simon) : sur la fiche client, en haut à droite comme chez Mike, des boutons téléphone, texto, courriel et carte (épingle). À la greffe, ils passent par la téléphonie, les textos, les courriels et la carte de l'app de Mike. Chaque appel, texto et courriel est inscrit dans la fiche, avec l'heure, la durée et l'enregistrement de l'appel.
- **Choix de Simon** :
  - Boutons et historique sur la fiche client ET la fiche lead. L'historique du client comprend les communications de ses leads.
  - Appels : enregistrement + transcription + résumé (produits par l'app de Mike).
  - Accès : tous les employés, sauf les sous-traitants. Chaque écoute est journalisée (qui, quand, quel appel).
  - Conservation des enregistrements : la même règle que l'app de Mike, à confirmer avec lui. Tant qu'elle n'est pas inscrite, rien n'est effacé.
- **Conception** :
  - Table `communications`, écrite seulement par le serveur (webhook de Mike), jamais par le navigateur. Vue `communications_v` : le lien lead -> client se résout même si l'employé ne voit pas ce lead, avec la même règle d'accès que la table.
  - L'audio reste chez Mike : on ne garde qu'une référence. L'écoute passe par `hvac_ecouter_enregistrement` (accès + journal), puis par une URL d'écoute de courte durée fournie par Mike.
  - Effacement selon la règle : la référence audio disparaît. L'heure, la durée, la transcription et le résumé restent.
  - Drapeau `MIKE_COMM_ENABLED=false` : les boutons ouvrent le téléphone, les textos ou le courriel de l'appareil (rien n'est enregistré), et le webhook répond 503.
  - Carte : lien Google Maps officiel (« Maps URLs », sans clé), avec la position exacte si connue, sinon l'adresse. Remplacée par la carte de Mike à la greffe.
  - HTML de test : simule l'app de Mike branchée. Un clic sur Appeler ajoute un appel simulé avec enregistrement (tonalités, aucune vraie voix) et transcription fictive, et compte pour la rapidité du vendeur sur un lead.
- **À valider par un professionnel** :
  - L'avis d'enregistrement au client (message au début de l'appel) et la façon d'informer le client des fins de la collecte (Loi 25).
  - La transcription par un fournisseur d'IA hors Québec (AssemblyAI, Whisper chez Mike) : évaluation des facteurs relatifs à la vie privée exigée pour une communication hors Québec.
  - La durée de conservation.

## ADR-068 | Tableau exécutif des machines HVAC (maquette, données fictives)
- **Date** : 2026-10-24 | **Statut** : Maquette à modeler avec Simon
- **Demande** (Simon) : un tableau comme la « vue exécutive » Monday qu'il a montrée, pour voir d'où viennent les machines, où elles sont vendues, quels modèles se vendent le plus et dans quel territoire. Chiffres fictifs pour commencer.
- **Page** `/tableau-machines` (direction, gérants, coordination), tuile « Tableau des machines » à l'accueil.
  - Panneau sombre lisible sur un téléviseur, bouton « Plein écran ».
  - Filtres : période (12 mois, 3 mois, le mois, l'année), succursale, type de système, marque. Tout se recalcule.
  - Tuiles : machines vendues, ventes avant taxes, prix moyen, municipalités desservies, part livrée de l'entrepôt, avec l'écart par rapport à la période précédente.
  - Graphiques : ventes par mois (colonnes par type), répartition par type (anneau), modèles les plus vendus, ventes par territoire, carte des ventes par municipalité (vraies limites municipales), provenance par fournisseur (entrepôt ou livraison directe, délai), matrice modèles par territoire.
  - Infobulle au survol et au clavier, données en tableau pour le graphique mensuel.
- **Couleurs** : 4 couleurs de catégorie pour les types et une échelle bleue pour les quantités, vérifiées avec l'outil de validation (daltonisme, contraste) sur le fond sombre.
- **Données** : générateur déterministe `public/js/bf-ventes-fictives.js` (marques, modèles et fournisseurs inventés). À la greffe : ventes réelles de l'app de Mike (devis acceptés, équipements HVAC du Macro, bons de commande et réceptions pour la provenance).

## ADR-069 | Tableau des machines : marge brute, stock et ventes par vendeur
- **Date** : 2026-10-24 | **Statut** : Maquette (données fictives)
- **Demande** (Simon) : ajouter la marge brute et les machines en stock dans les tuiles, et une section par vendeur : ce qu'il a vendu, et quel type de machine il a vendu dans chaque territoire.
- **Tuiles** :
  - Marge brute : pourcentage, montant en dollars, écart en points par rapport à la période précédente. Marge = prix de vente moins le coût de la machine et de l'installation (définition à confirmer avec Simon et la comptabilité de Mike).
  - Machines en stock : nombre au dernier jour du mois, couverture en semaines de ventes (moyenne des 3 derniers mois) et valeur au coût. Avec une succursale choisie : son stock plus celui de l'entrepôt central qui la sert.
- **Nouveau filtre** : vendeur.
- **Sections** :
  - Ventes par vendeur : barres empilées par type de système, ventes en dollars et marge de chacun.
  - Machines en stock : par lieu (entrepôt central et succursales), empilées par type.
  - Vendeurs par territoire et type de machine : chaque vendeur avec ses totaux, puis une ligne par territoire où il a vendu, avec les unités par type, les ventes et la marge.
- **À la greffe** : vendeurs et marges depuis les devis et factures de Mike ; stock depuis son module d'inventaire (relevé, réceptions, réservations).

## ADR-070 | Deux marges : avec installation (référence) et avant installation
- **Date** : 2026-10-24 | **Statut** : Maquette (données fictives)
- **Décision de Simon** : la marge brute de référence inclut l'installation, et on garde ça comme ça. On affiche aussi la marge avant installation (la machine seule).
- **Calcul** :
  - Marge avec installation = (prix total - coût de la machine - coût de l'installation) / prix total.
  - Marge avant installation = (prix de la machine - coût de la machine) / prix de la machine, sans la part installation du prix ni son coût.
  - Chaque vente porte donc son prix et son coût d'installation à part (`prix_installation_cents`, `cout_installation_cents`).
- **Où** : deux tuiles côte à côte, le tableau des vendeurs (colonnes « Marge totale » et « Marge avant inst. ») et les infobulles des vendeurs. Les tuiles passent en 2 rangées de 4.
- **À la greffe** : la part installation vient de la ligne d'installation du devis de Mike (coût du sous-traitant, prix client) ; à confirmer dans ses données.

## ADR-071 | Graphique de la marge brute par mois
- **Date** : 2026-10-24 | **Statut** : Maquette (données fictives)
- **Demande** (Simon) : un graphique de la marge par mois.
- **Forme** : deux lignes sur un seul axe en pourcentage, 12 derniers mois : marge avec installation (référence, violet) et marge avant installation (magenta). Couleurs distinctes de celles des types de système, validées sur le fond sombre. Valeur du dernier mois au bout de chaque ligne.
- **Lecture** : une ligne verticale suit le pointeur (ou les flèches du clavier) et l'infobulle donne, pour le mois, le nombre de machines, les deux marges et l'écart dû à l'installation. La période choisie est en surbrillance. Données en tableau sous le graphique.
- Suit tous les filtres (succursale, type, marque, vendeur).
