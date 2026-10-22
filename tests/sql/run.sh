#!/usr/bin/env bash
# Applique les migrations sur une base Postgres locale JETABLE et lance les tests SQL.
# Ne touche à aucun projet Supabase. Usage : tests/sql/run.sh
set -euo pipefail
cd "$(dirname "$0")/../.."
DB="${HVAC_TEST_DB:-hvac_test}"
PSQL=(psql -X -q -v ON_ERROR_STOP=1 -P tuples_only=on -P format=unaligned -d "$DB")
dropdb --if-exists "$DB"
createdb "$DB"
"${PSQL[@]}" -f tests/sql/00_supabase_stub.sql
for f in supabase/migrations/*.sql; do
  echo "migration : $f"
  "${PSQL[@]}" -f "$f"
done
"${PSQL[@]}" -f tests/sql/10_phase1.test.sql 2>&1 | sed 's/^psql:[^ ]* NOTICE:  //' | grep -v '^$'
