#!/bin/bash
# Teste toutes les migrations sur un PostgreSQL local qui imite Supabase,
# sans toucher à la base de production.
#   PGHOST=/chemin/socket PGPORT=5432 ./supabase/tests/run_local.sh
# Crée (et remplace) la base locale « mn_test ».
set -euo pipefail
D=$(cd "$(dirname "$0")" && pwd)
M="$D/../migrations"
H="-U ${PGUSER:-postgres}"
psql $H -qc "drop database if exists mn_test" -c "create database mn_test" >/dev/null
P="psql $H -d mn_test -v ON_ERROR_STOP=1 -q"
$P -f "$D/stub_supabase.sql"
for f in "$M"/0*.sql; do
  case "$(basename "$f")" in
    0005_cron.sql) $P -c "select cron.schedule('expire-stale-bookings','* * * * *','select public.expire_stale_bookings()')" >/dev/null ;;
    *) echo "→ $(basename "$f")"; $P -f "$f" ;;
  esac
done
echo "→ scénario de sécurité"
$P -f "$D/security_scenario.sql"
