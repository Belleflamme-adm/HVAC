# Belleflamme | Division HVAC

App autonome de la division Ventilation/Climatisation du Groupe Belleflamme, conçue pour être greffée plus tard dans l'app de Mike. Mémoire du projet : `CLAUDE.md`. Décisions : `docs/DECISIONS.md`.

## Structure

```
public/              pages (pretty URLs), css, js (bf-*), sw.js, manifest
netlify/functions/   session-login | session-me | session-logout | health | monday-webhook-sync | friday-sync
lib/data/            adapters : supabase (actif), monday et friday (stubs désactivés)
lib/                 config, http, session (contrat d'auth de Mike)
supabase/migrations/ schéma SQL + RLS (docs/SCHEMA.md)
supabase/seed.sql    données de démo FICTIVES
tests/unit/          node --test
tests/sql/           migrations + tests sur Postgres local jetable
docs/                SCHEMA | MAPPING | MIGRATION | DECISIONS | reference/
```

## Tester

```bash
npm ci
npm test            # tests unitaires
npm run test:sql    # Postgres 16 local requis (crée et détruit des bases hvac_test*)
```

## Lancer en local

1. `cp .env.example .env`, puis Simon saisit `SUPABASE_URL` et `SUPABASE_ANON_KEY` (projet HVAC dédié).
2. `npm run dev` (netlify-cli via npx), puis ouvrir http://localhost:8888

## Créer un compte

1. Ajouter ou modifier la fiche dans `employes` (courriel réel).
2. Supabase Dashboard > Authentication > invite ce courriel.
3. Au premier login, `hvac_session()` lie le compte à la fiche.

## Garde-fous

Voir `CLAUDE.md` §2. Résumé : rien dans l'infra de Mike, aucun secret dans le repo, pas de provisionnement sans OK de Simon.
