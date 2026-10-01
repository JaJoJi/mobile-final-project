#!/bin/bash
set -e

# Runs once at first init of postgres-primary.
#
# Two responsibilities:
#   1. Create the `replicator` role used by postgres-replica for streaming.
#   2. Append a `host replication` rule to pg_hba.conf so the replica
#      (which lives on the docker network IP, NOT localhost) can connect.
#
# Without #2, pg_basebackup on the replica fails with:
#   "no pg_hba.conf entry for replication connection from host <ip>"

PGDATA="${PGDATA:-/var/lib/postgresql/data}"

# ---- 1. replicator role ----
# Password from POSTGRES_REPLICATION_PASSWORD (production sets it; the dev
# compose doesn't, so it keeps the old dev default). Passed as a psql
# variable and quoted with format(%L) -- never spliced into SQL by the
# shell. Heredoc delimiter is single-quoted so bash expands nothing.
# Production gets it as a file rendered by Vault Agent (*_FILE convention,
# same as the image's own POSTGRES_PASSWORD_FILE).
if [ -n "${POSTGRES_REPLICATION_PASSWORD_FILE:-}" ] && [ -r "$POSTGRES_REPLICATION_PASSWORD_FILE" ]; then
  POSTGRES_REPLICATION_PASSWORD="$(cat "$POSTGRES_REPLICATION_PASSWORD_FILE")"
fi
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" \
  -v repl_pw="${POSTGRES_REPLICATION_PASSWORD:-replicator_secret}" <<-'EOSQL'
SELECT format('CREATE ROLE replicator WITH REPLICATION LOGIN PASSWORD %L', :'repl_pw')
WHERE NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'replicator')
\gexec
EOSQL

# ---- 2. pg_hba.conf rule for replication from any docker-network host ----
HBA="$PGDATA/pg_hba.conf"
touch "$HBA"

if ! grep -q "^host replication replicator " "$HBA"; then
  echo "host replication replicator 0.0.0.0/0 md5" >> "$HBA"
  echo "host replication replicator ::/0      md5" >> "$HBA"
  echo "[primary] appended replication HBA rule for replicator"
else
  echo "[primary] replication HBA rule already present"
fi

echo "[primary] init done (replicator + HBA ready)"
