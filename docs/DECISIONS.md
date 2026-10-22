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
