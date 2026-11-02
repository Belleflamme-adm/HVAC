# Installation de la base HVAC par copier-coller (ADR-098)

Le connecteur Supabase de Claude demande une autorisation pour les migrations qui contiennent `drop` ou `delete`,
et cette autorisation ne s'affichait pas sur l'appareil de Simon. Ces 6 parties regroupent les 47 migrations de
`supabase/migrations/` (commentaires retirés), dans l'ordre, testées sur Postgres 16 avec tous les tests SQL.

1. Supabase > projet `hvac-belleflamme` > SQL Editor > New query.
2. Coller `partie-1.sql`, Run (si Supabase avertit d'une opération destructive : confirmer, la base est neuve).
3. Recommencer avec les parties 2 à 6, dans l'ordre, une seule fois chacune.

Les migrations suivantes (après le 31 oct. 2026) s'appliqueront une à une, comme d'habitude.
