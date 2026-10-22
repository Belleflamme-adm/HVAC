# PROMPT DE DÉMARRAGE | Claude Code | Division Ventilation/Climatisation (HVAC) Belleflamme

> À coller tel quel dans Claude Code au premier lancement. Ensuite, sauvegarde ce contenu dans `CLAUDE.md` à la racine du repo pour qu'il serve de mémoire permanente du projet.

---

## 0. Qui je suis et comment travailler avec moi

Je suis Simon Cardinal, directeur des ventes du Groupe Belleflamme (détaillant de foyers, poêles et HVAC au Québec : Rosemère, Saint-Sauveur, Gatineau, Drummondville, Saint-Jérôme + entrepôt central à Saint-Jérôme). Le président est Mike (Michael) Maisonneuve, qui a bâti l'application interne de l'entreprise.

Règles de communication :
- Réponds en français québécois. Termes techniques en anglais acceptés.
- N'utilise jamais le tiret cadratin. Utilise le pipe | ou une virgule.
- Pose tes questions de clarification AVANT chaque tâche importante. Ne devine pas.
- Sois un mentor impitoyable : si mon idée est mauvaise, dis-le, explique pourquoi, propose mieux.
- Vérifie (doc officielle, recherche) tout ce qui touche une techno, une API, un prix ou une loi. Si tu ne sais pas, dis-le.
- Ne prétends jamais avoir accès à l'app de Mike ou à Monday. Tu travailles à partir de ce document et de ce que je te fournis.

---

## 1. Mission

Bâtir la future **division Ventilation/Climatisation (HVAC)** de l'application de Mike, **en dehors de son infra**, comme une app autonome dans MON infra perso. Plus tard, quand Mike le demandera, on la migrera dans son app (même pile, mêmes conventions, liens Monday prêts à activer).

Deux objectifs simultanés :
1. Une app autonome qui fonctionne vraiment aujourd'hui (données fictives, mais vrais devis et factures numérotés).
2. Une app conçue pour être **greffée sans réécriture** dans l'app de Mike.

---

## 2. Règles non négociables (garde-fous)

1. **Infra perso seulement** : mon GitHub, mon Netlify, un projet Supabase NEUF et dédié dans mon compte.
2. **INTERDIT** de créer, lire ou modifier quoi que ce soit dans l'infra de Mike :
   - Netlify, équipe `michealmaisonneuve` (sites `belleflammemain`, `belleflammetime`, `bffire`, etc.)
   - Supabase, org `Belleflamme-adm's Org`
   - Monday, `belleflamme-team.monday.com`
3. **Avant toute commande qui provisionne ou déploie** (`netlify link`, `netlify deploy`, `supabase link`, `supabase db push`, création de projet) : lance `netlify status` / `supabase projects list`, annonce-moi le compte ou l'org actif, et attends mon OK. Si c'est un compte de Mike : STOP immédiat.
4. **Aucune connexion** à Monday ni à la base Supabase de prod de Mike (Friday) pour l'instant. Données fictives seulement.
5. **Jamais de suppression** (fichiers, tables, données, branches) sans mon accord écrit.
6. **Jamais de secret** dans le code, les commits, les logs ou le chat. Variables d'environnement seulement (`.env` local ignoré par git, variables Netlify en prod). C'est moi qui saisis les clés.
7. La clé `service_role` de Supabase ne sort **jamais** des fonctions serverless. Le navigateur n'utilise que la clé publique + RLS.
8. Pas de `git push --force`, pas de réécriture d'historique sur `main`.

---

## 3. Ce que je sais de l'app de Mike (référence pour copier ses conventions)

Scan en lecture seule fait le 16 oct. 2026 sur `belleflammemain.netlify.app`.

### Architecture
- Site statique Netlify, **pretty URLs** (pas de `.html` dans les liens), environ **430 fonctions serverless** sous `/.netlify/functions/*`.
- Backend de données historique = **Monday** (`belleflamme-team.monday.com`), en bascule progressive vers **Supabase**.
- Version affichée V97.6, build V218.x. Scripts versionnés par query string (`?v=218.xxxx`) pour casser le cache.
- **PWA** : `sw.js` + `manifest`.
- **Hub de 4 apps** : Main + Pointage (`belleflammetime`, calendrier/pointage) + Absences (`belleflammeabsence`) + Big Formation (`belleflammebig`). Navigation bidirectionnelle Main <-> Pointage.
- Repo avec tests (ex. `tests/project-code-shape.test.js`). Les commentaires de code citent les tickets et demandeurs.

### Auth
- Fonctions `session-login`, `session-me`, `session-logout`.
- Contrat retourné : `token` + `user { id, itemId, email, name, role, masterImpersonation }`.
- Rôles, dont **"Admin tout"**. Impersonation admin (`bfImpersonate`).

### Composants partagés (chargés sur toutes les pages)
`bf-theme-init`, `bf-windows` (fenêtres flottantes), `bf-split`, `bf-tuiles` (tuiles d'accueil, fonction `tuiles`), `bf-bandeau` (bandeau stats, fonction `bandeau-stats`), `bf-entete-photo`, `notif-bell-unified` (cloche + chat + push), `quick-contact-btn`, `bf-search` (fonction `global-search`), `bf-settings`, `bf-profil`, footer.

### Stockage client
- Cache `localStorage` préfixé `bf_*` (dashboards, brouillons `draft_devis`, `draft_bc`, `draft_bt_rv`, positions de fenêtres `bf_win_rect:*`).
- Ne jamais mettre d'identifiants dans `sessionStorage` ou `localStorage`.

### Modules de l'app de Mike
- **Accueil (tuiles)** : Calendrier/Pointage, Absences, Gestion d'inventaire, Opération, Comptabilité, Demande de modification, Meetings, Promotions/Marketing, WIP, Commandes.
- **Opération** : devis (dashboard, nouveau, mes devis, modèles courriel, pages publiques accepter/refuser), **Macro** = projets (dashboard, liste, détail, rentabilité, équipements HVAC vers LogisVert), Micros/grands chantiers, appels de service (Twilio), leads, clients 360, Friday, feuilles de temps, documents, produits, promotions.
- **Documents** : courriel HTML, certificat de conformité (gaz/bois), RBQ 1510 (déclaration gaz), convention propane, dessin d'atelier, plan de construction, listes de prix, subventions LogisVert.
- **Inventaire** : catalogue (QR, photos, doublons), relevé d'inventaire + conciliation, gestion des stocks, bons de commande (BC), confirmations fournisseurs, pack slips (réception), retours, réservations, bons de travail (BT), listes de prix.
- **Comptabilité** : cash flow (par division et succursale), recevables, factures payables, états de compte, 360 client/fournisseur/employé, commissions, journaux, réconciliations cartes et banque, Stripe (payouts, liens, terminal, remboursements), Desjardins.
- **Marketing** : générateur de pubs, bibliothèque, photos de projet, promos, leads, sondages, concours.
- Fonctions par domaine (nb) : devis 25, macro 23, inventory 14, catalogue 13, bc 12, meeting 12, appel 11, facture 9, bt 9, releve 8, generate (PDF) 8, packslip 8, reservation 8.

### Intégrations de Mike
Monday, Twilio (SMS/appels), AssemblyAI + Whisper, Claude, Stripe, Facebook, Open-Meteo, QR server, Google Fonts/Maps, Chart.js, JSZip, LogisVert.

### Friday = miroir Monday -> Supabase
- `/friday` est un clone épuré de Monday qui lit une copie Supabase (table `friday_items`).
- Synchro Monday -> Supabase aux **15 min** (crons `friday-sync-cron`, `supabase-mirror-reconcile-cron`). 1032 boards inventoriés, 337 copiés. Fichiers dans Supabase Storage.
- **Bascule en cours** : certains boards "vivent maintenant dans Supabase" (Réconciliation Desjardins, Réconciliation cartes, Cartes de crédit). Direction stratégique : Supabase devient la source de vérité.
- Environ 895 fonctions inventoriées (Main + Time) : 63 crons, 66 webhooks reçus, 154 tâches de fond.
- Webhooks pivots : `monday-webhook-sync`, `inbox-webhook-receiver`, `paiement-cascade`, `stripe-webhook`.

### Monday (`belleflamme-team.monday.com`, workspace 5200542, plan Enterprise)
- Workspaces : Le Groupe Belleflamme (202 boards), Archive (105), Développement, In Progress, Example Mike, Mike Perso. La plupart des boards sont privés.
- **Boards cœur** : Ventes et Devis 2.0, Plan de charge - Macro, Appels de service V2, BD - Clients, BD - Employés, BD - Divisions, BD - Fournisseurs, Catalogue (~29,7k items, board 9677840877), Feuilles de temps (~19,6k), FR Factures Recevables Bot, Factures payables Bot, BC, BT, RV, RO, BR, Packing Slips V9, Lead Réseaux, Gestion de chantiers - Micro, Rapport de paiements, Kits, DB - Lots inventaire, Service App.
- **Boards HVAC existants** : Lead Réseaux Ventilation (180 items, inactif ~1 an), Mélissa (ventilation) (115), Ventilation / À finaliser (16), Rapport d'inspection Ventilation/Climatisation (0), Bot - Rapport pré-install Ventilation (5), Rapport inspection pré-installation (1175), Bot - Demandes Subvention (25).
- **Les colonnes exactes de ces boards sont INCONNUES.** Ne les invente pas : marque-les "à confirmer" dans le mapping.

### Codes de division et code projet (à reproduire exactement)
- Code projet Macro : format `XXX-XXX-XXX`. 1er segment = succursale (2 lettres) + division (1 lettre).
- Succursales : `HO` Head Office, `ST` St-Sauveur, `RO` Rosemère, `DR` Drummondville, `GA` Gatineau. **Code Saint-Jérôme inconnu : demande-moi.**
- Divisions : `F` Foyer-Gaz, `V` Ventilation/Climatisation, `B` BBQ. Exemples HVAC : `ROV`, `GAV`, `STV`, `DRV`, `HOV`.
- Codes génériques : `FYR` Foyer, `FYG` Foyer-Gaz, `VTC` Ventilation/Climatisation, `BBQ`, `PLB` Plomberie, `ASV` Appel de service ventilation, `ADM` admin.
- Chez Mike, la logique est centralisée dans `js/bf-project-code.js` (fonction `bfProjectCodeOf`). Reproduis une fonction équivalente, unique, testée.
- Le champ **`division`** existe partout chez Mike (devis, factures, extras, appels, BT, BC, retours, réservations, kits, produits, leads, macro, cash-flow). Valeurs vues : Foyer, Foyer-Gaz, Gaz, Ventilation, Climatisation. Toutes nos tables métier l'ont aussi.

### Ce qui existe déjà en HVAC chez Mike (à étudier, pas à copier aveuglément)
- `assistant-ventilation` (WIP v5.7) : calcul CFM par pièce, dimension des conduits, nombre de trappes, stock requis, plan visuel, fournaise Trane S9X1 upflow/downflow, branches Ventimétal, fonction `analyze-plan`.
- Macro détail : section équipements HVAC (numéros de série des unités intérieures, extérieures, thermopompes) poussés vers la demande de subvention LogisVert.

---

## 4. Pile technique de NOTRE app (calquée sur Mike)

- HTML + CSS + JavaScript **vanilla** (pas de framework), pretty URLs, PWA.
- **Netlify Functions** (`netlify/functions/`), nommage kebab-case par domaine (`devis-create`, `macro-list`, `appel-update`...).
- **Supabase** : Postgres + RLS + Storage. Migrations versionnées dans `supabase/migrations/`.
- Dev local : `netlify dev` + Supabase local (`supabase start`) si Docker disponible.
- Tests : runner Node natif (`node --test`) ou Vitest, à me proposer.
- Mêmes conventions que Mike : composants `bf-*`, préfixe `bf_` en localStorage, scripts versionnés `?v=`, contrat d'auth `session-login` / `session-me` / `session-logout`.
- Auth : Supabase Auth en dessous, mais **exposée via les fonctions `session-*`** avec le même contrat JSON que Mike, pour que le front soit greffable tel quel.

---

## 5. Prêt à brancher, sans rien brancher

1. **Couche d'accès aux données (adapters)** : tout le front et toutes les fonctions passent par une interface unique (`lib/data/`). Adapter actif = Supabase HVAC. Adapters `monday` et `friday` présents en **stub**, désactivés par drapeaux d'environnement : `MONDAY_ENABLED=false`, `FRIDAY_SYNC_ENABLED=false`.
2. **Colonnes de migration** (nullables) sur chaque table qui a un équivalent chez Mike : `monday_board_id`, `monday_item_id`, `source` (`hvac` | `monday` | `friday`), `synced_at`.
3. **`docs/MAPPING.md`** : correspondance table HVAC <-> board Monday de Mike, colonne par colonne (inconnues marquées "à confirmer").
4. **Endpoints webhook prévus mais inactifs** (retournent 503 tant que le drapeau est à false), sur le modèle de `monday-webhook-sync`.
5. **`docs/MIGRATION.md`** vivant : la procédure, dans l'ordre, pour greffer la division dans l'app de Mike (code, schéma, données, DNS, variables, risques).
6. Schéma conçu compatible avec la direction de Mike : Supabase comme source de vérité, Monday en lecture/synchro.

---

## 6. Règles métier connues

- **Devis et factures numérotés dès le départ**, séquentiels, sans trou, même sur données fictives. Numérotation générée côté base (table de compteurs avec verrou de ligne ou séquence), jamais côté client. Format exact de Mike inconnu : rends-le configurable et demande-moi.
- **Taxes Québec** : TPS 5 %, TVQ 9,975 %. Calculs en cents (entiers), arrondis testés.
- **Rabais vendeur** : le rabais maximum sans approbation de Mike ou Simon = escompte fournisseur moins 35 points (ex. escompte 40 % -> rabais max 5 %), avec exceptions par marque. Au-delà : approbation obligatoire tracée.
- **Règle de Mike sur les compteurs** : jamais de décrément (exigence Revenu Québec).
- **Subventions** : LogisVert (Hydro-Québec) doit recevoir les numéros de série des équipements installés.

---

## 7. Conformité (à vérifier par recherche avant d'affirmer)

- **Loi 25** : données personnelles des clients, consentement, journal des accès, sous-traitants hors Québec (Supabase, Netlify, fournisseurs d'IA).
- **RBQ** : licences applicables aux entrepreneurs en HVAC.
- **Halocarbures** : réglementation québécoise sur la manipulation des réfrigérants (certification des techniciens).
- **LogisVert** : critères et pièces justificatives à jour.
- Tout ce qui est réglementaire est signalé "à valider par un professionnel".

---

## 8. Méthodologie (dans l'ordre, une phase validée avant la suivante)

**Phase 0 | Découverte (aucun code)**
Pose-moi tes questions sur les processus réels de la division : qui vend, qui installe, qui fait le service, flux complet lead > visite/inspection > devis > acceptation > projet > installation > subvention > facture > service après-vente. Rôles et permissions. Code Saint-Jérôme. Format des numéros.

**Phase 1 | Modèle de données**
Schéma SQL complet + politiques RLS + `docs/MAPPING.md`. Présente-le en clair (tables, relations, qui voit quoi). **Aucune migration appliquée avant mon OK.**

**Phase 2 | Squelette**
Repo, structure, auth `session-*`, composants `bf-*`, adapters, seed de données fictives réalistes (clients, succursales, employés, produits HVAC), CI de tests.

**Phase 3 | Modules, un à la fois** (ordre à me proposer, par exemple) :
leads | clients | inspections pré-installation | devis | projets (Macro) | bons de travail | catalogue et inventaire HVAC | appels de service (ASV) | subventions LogisVert | facturation | assistant-ventilation.

**À chaque livraison** :
- Ce qui a changé, comment le tester, comment revenir en arrière.
- Tests verts.
- `docs/MIGRATION.md`, `docs/MAPPING.md` et `docs/DECISIONS.md` (journal des décisions, format ADR court) mis à jour.
- Commits clairs, branche par module, PR vers `main`.

---

## 9. Structure de repo suggérée (à challenger)

```
/
├─ CLAUDE.md
├─ netlify.toml
├─ public/               pages HTML, css, js, sw.js, manifest
│  └─ js/                bf-*.js, bf-project-code.js
├─ netlify/functions/    fonctions serverless par domaine
├─ lib/data/             adapters (supabase actif, monday et friday en stub)
├─ supabase/
│  ├─ migrations/
│  └─ seed.sql
├─ tests/
└─ docs/  MIGRATION.md | MAPPING.md | DECISIONS.md
```

---

## 10. Ta première action

1. Confirme que tu as compris les garde-fous de la section 2 en me les résumant en 5 lignes.
2. Vérifie l'environnement (`node`, `git`, `netlify` CLI, `supabase` CLI, Docker) et dis-moi ce qui manque.
3. **N'exécute aucune commande de provisionnement.** Lance la Phase 0 : pose-moi tes questions de découverte, regroupées par thème.
