#!/usr/bin/env bash
# Applique les migrations sur des bases Postgres locales JETABLES et lance les tests SQL.
# Ne touche à aucun projet Supabase. Usage : tests/sql/run.sh
# Connexion : variables PG* standard (PGHOST, PGUSER, PGPASSWORD...) ou socket local.
set -euo pipefail
export PGOPTIONS="${PGOPTIONS:-} -c client_min_messages=warning"
cd "$(dirname "$0")/../.."
DB="${HVAC_TEST_DB:-hvac_test}"

nouvelle_base() {
  dropdb --if-exists "$1"
  createdb "$1"
  psql -X -q -v ON_ERROR_STOP=1 -d "$1" -f tests/sql/00_supabase_stub.sql
  for f in supabase/migrations/*.sql; do
    psql -X -q -v ON_ERROR_STOP=1 -d "$1" -f "$f"
  done
}

lancer() {
  psql -X -q -v ON_ERROR_STOP=1 -P tuples_only=on -P format=unaligned -d "$1" -f "$2" 2>&1 \
    | sed 's/^psql:[^ ]* NOTICE:  //' | grep -v '^$'
}

echo "== Tests du schéma"
nouvelle_base "$DB"
for t in tests/sql/*.test.sql; do lancer "$DB" "$t"; done

echo "== Seed de démo"
nouvelle_base "${DB}_seed"
psql -X -q -v ON_ERROR_STOP=1 -d "${DB}_seed" -f supabase/seed.sql
lancer "${DB}_seed" tests/sql/seed_check.sql

dropdb --if-exists "$DB"
dropdb --if-exists "${DB}_seed"
echo "SQL : OK"
