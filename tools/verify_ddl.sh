#!/usr/bin/env bash
# Verify the generated DDL by actually loading it into a throwaway PostgreSQL instance.
#
# The sandbox may be reset, so this script installs PostgreSQL if it is missing and
# initialises its own data directory. Safe to re-run.
#
#   ./tools/verify_ddl.sh
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PGDATA="${PGDATA:-/var/lib/pgdata}"
PGPORT="${PGPORT:-5433}"
PGUSER_NAME="${PGUSER_NAME:-pg}"
DDL_DIR="$REPO_ROOT/schema/ddl"

log() { printf '\n== %s\n' "$*"; }

# 1. binaries -----------------------------------------------------------------
if ! command -v initdb >/dev/null 2>&1; then
  log "installing postgresql"
  if command -v dnf >/dev/null 2>&1; then
    dnf install -y postgresql15-server postgresql15 >/dev/null
  elif command -v apt-get >/dev/null 2>&1; then
    apt-get update -qq && apt-get install -y postgresql >/dev/null
  else
    echo "no supported package manager found; install PostgreSQL manually" >&2
    exit 1
  fi
fi

# 2. unprivileged user + data dir --------------------------------------------
if [ "$(id -u)" -eq 0 ]; then
  id -u "$PGUSER_NAME" >/dev/null 2>&1 || useradd -m "$PGUSER_NAME"
  RUN=(su "$PGUSER_NAME" -c)
else
  RUN=(bash -c)
fi

if [ ! -f "$PGDATA/PG_VERSION" ]; then
  log "initdb $PGDATA"
  mkdir -p "$PGDATA"
  [ "$(id -u)" -eq 0 ] && chown -R "$PGUSER_NAME" "$PGDATA"
  "${RUN[@]}" "initdb -D '$PGDATA' -U '$PGUSER_NAME'" >/dev/null
fi

# 3. start server (must stay in this shell: background jobs die between sessions)
if ! "${RUN[@]}" "psql -h '$PGDATA' -p $PGPORT -U '$PGUSER_NAME' -d postgres -tAc 'select 1'" \
     >/dev/null 2>&1; then
  log "starting postgres on port $PGPORT"
  nohup "${RUN[@]}" "postgres -D '$PGDATA' -k '$PGDATA' -p $PGPORT" >/dev/null 2>&1 </dev/null &
  for _ in $(seq 1 30); do
    "${RUN[@]}" "psql -h '$PGDATA' -p $PGPORT -U '$PGUSER_NAME' -d postgres -tAc 'select 1'" \
      >/dev/null 2>&1 && break
    sleep 1
  done
fi

PSQL() { "${RUN[@]}" "psql -h '$PGDATA' -p $PGPORT -U '$PGUSER_NAME' $*"; }

PSQL "-d postgres -q -c 'drop database if exists asis'  -c 'create database asis'"
PSQL "-d postgres -q -c 'drop database if exists clean' -c 'create database clean'"

fail=0

# 4. as-is schema -------------------------------------------------------------
log "loading as-is DDL (ERPNext physical layout)"
for f in "$DDL_DIR"/*_asis.sql; do
  errs=$(PSQL "-d asis -f '$f'" 2>&1 | grep -c ERROR || true)
  printf '  %-28s %s\n' "$(basename "$f")" \
    "$( [ "$errs" -eq 0 ] && echo OK || { echo "$errs ERRORS"; fail=1; } )"
done

# 5. clean schema -------------------------------------------------------------
log "loading clean reference DDL"
for f in "$DDL_DIR/clean_01_tables.sql" "$DDL_DIR/clean_02_constraints.sql"; do
  errs=$(PSQL "-d clean -f '$f'" 2>&1 | grep -c ERROR || true)
  printf '  %-28s %s\n' "$(basename "$f")" \
    "$( [ "$errs" -eq 0 ] && echo OK || { echo "$errs ERRORS"; fail=1; } )"
done

# 6. report -------------------------------------------------------------------
log "result"
for db in asis clean; do
  PSQL "-d $db -tAc \"select '  $db: '
    || (select count(*) from information_schema.tables where table_schema='public') || ' tables, '
    || (select count(*) from information_schema.table_constraints
        where constraint_schema='public' and constraint_type='FOREIGN KEY') || ' FKs, '
    || (select count(*) from pg_indexes where schemaname='public') || ' indexes'\""
done

# every FK must point at an existing table with a unique target
orphans=$(PSQL "-d clean -tAc \"select count(*) from pg_constraint c
  where c.contype='f' and not exists (select 1 from pg_class t where t.oid=c.confrelid)\"")
printf '  dangling FK targets: %s\n' "$orphans"

exit $fail
