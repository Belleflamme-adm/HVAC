# Formats de l'app de Mike | Devis signé, bon de travail, bon de commande

> Analyse de deux PDF fournis par Simon le 22 oct. 2026 (un devis signé de la division Foyer et un BT généré par l'app de Mike).
> **Les PDF ne sont PAS versés au repo** : ils contiennent des renseignements personnels (Loi 25). Seule la **structure** est notée ici, et les exemples de noms sont fictifs.

## 1. Numérotation (règle la question de l'ADR-004)

| Élément | Format observé | Exemple fictif | Notes |
|---|---|---|---|
| Numéro de devis | Entier séquentiel global, 6 chiffres, affiché `#120815`, et `D#` dans les renvois | `#120815`, `D#122109` | Une seule série toutes divisions confondues (à confirmer). Environ 122 100 en octobre 2026. |
| Code projet | `[SUCC][DIV]-[3 lettres prénom]-[3 lettres nom]-[NNN]` | `DRF-JEA-TRE-001` (Jean Tremblay, Drummondville, Foyer) | Majuscules, sans accents. **4 segments**, et non 3 comme le disait `CLAUDE.md`. Le sens exact de `NNN` est à confirmer (compteur par client ?). |
| Numéro de BT | `BT#RV001 <code projet>` | `BT#RV001 DRF-JEA-TRE-001` | `RV` = BT « Vendu » (titre « BON DE TRAVAIL | VENDU »). `001` = 1er BT de ce type pour le projet. Les autres types (RO, BR ?) sont à confirmer. |
| Numéro de BC | `[SUCC][DIV]-[PRÉ]-[NOM]-[1NN]`, affiché `BC#...` | `BC#DRF-JEA-TRE-100` | Même préfixe que le code projet, mais la série commence à **100**. Probablement 101 pour le 2e BC du même préfixe (à confirmer). |

## 2. Devis (« commande » une fois signé)

**Page 1 | lettre de présentation**
- Logo, nom du représentant, date (JJ / MM / AAAA), nom du client, code projet.
- Message personnalisé du représentant, avec sa signature (courriel, téléphone avec poste).
- Rappel : « le lien de soumission reste valide 30 jours ».

**Pages de détail**
- En-tête : logo, adresse (175 chemin Jean-Adam #100, Saint-Sauveur), téléphone, `DEVIS #nnnnnn`, numéro de page.
- Bloc **Client** : nom, code projet, téléphone, courriel, adresse, date du devis.
- Bloc **Représentant des ventes** : nom et courriel. Bloc **Adresse du projet**.
- Tableau **Détails** : QTÉ | PHOTO | PRODUIT (SKU en gras et description) | RABAIS % | PRIX | TOTAL.
- **Sections nommées** (bandeau vert), par exemple :
  - « KIT-XXX / Ligne à gaz »
  - « CLAUSES INSTALLATION APPAREIL AU GAZ »
- **Clauses en lignes à 0,00 $** (visite pré-installation sans frais, garantie, pièces non utilisées créditées, clauses numérotées).
- **Installation en ligne de service**, par exemple :
  - `INS... / Installation foyer (Standard)`, avec en description « RAYON 30KM / 3$ KM Sup / Mise en marche / Certificat de conformité ».
  - Mike facture donc la distance **au km au-delà de 30 km**.
- **Ligne négative** « RABAIS SUPPLÉMENTAIRE -200,00 $ ».
- Totaux : Sous-total, T.P.S. (5 %) avec le numéro TPS, T.V.Q. (9,975 %) avec le numéro TVQ, TOTAL.
- **Modalités de paiement** : Dépôt 40 %, et 60 % 72 heures avant l'installation (confirme l'ADR-009).
- **Acceptation du devis** : signature électronique du représentant puis du client, avec la date et l'**adresse IP** du client.
- Pied de page : « VALIDE 30 JOURS », logo CMMTQ et licence RBQ.

**Dernière page | Conditions générales (12 articles), signées par les deux parties**
1. Réserve de propriété jusqu'au paiement complet
2. Documents (certificats, garanties) remis après le paiement final
3. Termes de paiement : intérêts de 1,5 %/mois (18 %/an) sur le solde dû
4. Annulation ou report à moins de 72 h : pénalité de 350 $
5. Vices cachés derrière les murs : avis de changement signé
6. Permis municipaux à la charge du client
7. Accès au chantier dégagé, prise 110 V
8. Délais de livraison estimés
9. Garantie du manufacturier
10. LPC : 10 jours pour annuler ; commande spéciale : pénalité de 25 %
11. Force majeure
12. Photos du chantier

> Les conditions générales sont un texte juridique : à recopier mot pour mot à partir du document officiel de Belleflamme, et à faire valider par un professionnel avant usage en HVAC.

## 3. Bon de travail

**Page 1 | page couverture** : « BON DE TRAVAIL », code projet en gros, devis source, client, adresse, **date prévue** (« Date à définir »), **techniciens assignés** (« Aucun technicien assigné »).

**Pages de détail** (« BON DE TRAVAIL | VENDU », `BT#RV001 <code projet>`)
- Bloc **Projet** : projet, devis source, adresse, courriel, date de création.
- Bloc **Préparation prévue** : date prévue, technicien(s), statut (« Nouveau »).
- Tableau : QTÉ | PHOTO | PRODUIT | **LOCALISATION** | **QUANTITÉ INSTALLÉE** (case à cocher).
  - Localisation = emplacements d'entrepôt, par exemple « St-Jérôme A-403 », « Réception », « Expédition », « Fournisseur ».
  - Statuts par ligne : « RÉSERVÉ | PAS EN STOCK ×n » et « À COMMANDER | aucun bon de commande relié ».
- Le BT reprend **toutes** les lignes du devis : produits, installation, lignes de service et visite pré-installation.
- **Information supplémentaire** : « Draft auto à l'acceptation du devis. À assigner (tech + date). » et « Bon de préparation pour l'équipe installation. Items à sortir du stock + inspecter avant chargement. »
- Pied de page : « DATE PRÉPARATION PRÉVUE ».

## 4. Bon de commande (captures d'écran fournies le 22 oct. 2026)

**Écran (mobile)**
- En-tête « BON DE COMMANDE », N° BC en gros.
- Cartes : **date de création**, **statut** (ex. « Reçu »), **projet** (`D#<devis> <code projet> <client>`), **fournisseur**, **contact** chez le fournisseur, **courriel** de l'employé qui commande.
- **Produits commandés (n)** : photo, SKU, description, quantité, **coût** (prix d'achat, pas le prix de vente).
- Totaux : sous-total, TPS 5 %, TVQ 9,975 %, total (taxes sur l'achat).
- Actions : **Envoyer par courriel** (au fournisseur), Voir le PDF, Régénérer le PDF, Voir dans Monday, Créer une autre commande, **Annuler ce bon de commande**.
- **Conversation avec le fournisseur**, propre à chaque BC (fil de discussion). Bouton « Chat équipe » global.

**PDF**
- En-tête Belleflamme (adresse de Saint-Sauveur), « BON DE COMMANDE #<n° BC> », page x/y.
- Bloc **Fournisseur** : nom, téléphone, adresse, courriel, date. Bloc **Adresse de livraison** : l'entrepôt de Saint-Jérôme.
- Tableau : QTÉ | PHOTO | PRODUIT (SKU et description) | RABAIS | **COÛT** | TOTAL.
- Totaux avec les numéros de TPS et de TVQ. Blocs « Information supplémentaire » et « Termes de paiement ».
- Bandeau **« DATE DE LIVRAISON : TBD »**, logo CMMTQ et licence RBQ.

## 5. Ce que ça change pour l'app HVAC

| Constat | Impact |
|---|---|
| Numéro de devis = entier global de 6 chiffres | Changer le format provisoire `D-AAAA-00001`. Le numéro de départ pour HVAC reste à choisir (collision avec la série de Mike lors de la greffe). |
| Code projet à 4 segments, dérivé du nom du client | Mettre à jour `bfProjectCodeOf` et la base. Le format provisoire `ROV-001-26` est faux. |
| BT créé automatiquement à l'acceptation | Le BT HVAC suit le même principe : brouillon à l'acceptation, puis assignation au sous-traitant et date. |
| Localisations et réservations de stock sur le BT | Dépend du module inventaire (pas encore construit). En attendant, le BT indique « Entrepôt Saint-Jérôme » ou « Fournisseur ». |
| Ligne « Rabais supplémentaire » négative | Notre base refuse les prix négatifs (ADR-032). Il faut une ligne de rabais global soumise à l'approbation de Simon ou Mike. |
| Clauses en lignes à 0 $, sections nommées, photos | Le devis HVAC devra gérer les sections, les clauses types et les photos de produits. |
| Signature électronique avec IP | Il manque une page publique « accepter le devis », avec signature, date et IP. |
| BC numéroté sur le préfixe du code projet, série 100 | Reproduire `[préfixe]-100`, `-101`... avec un compteur sans trou par préfixe. |
| BC au **coût**, avec taxes, envoyé par courriel au fournisseur | Le BC HVAC part du BT : les produits « à commander » deviennent des lignes au coût du catalogue. Envoi courriel : service à choisir (ADR-038). |
| Adresse de livraison = entrepôt | En HVAC, ajouter un choix : **livraison à l'entrepôt** ou **ramassage chez le fournisseur par le sous-traitant X** (ADR-037). |
| Conversation par BC | Fil de messages par BC (Belleflamme ↔ fournisseur). À prévoir en Lot B ou plus tard. |
| Distance : 3 $/km au-delà de 30 km (Mike) | Simon a choisi un supplément par ville pour les sous-traitants (ADR-038). Les deux modèles diffèrent : à trancher pour HVAC. |
