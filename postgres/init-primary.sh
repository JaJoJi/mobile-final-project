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
: "${POSTGRES_REPLICATION_PASSWORD:?POSTGRES_REPLICATION_PASSWORD must be set}"

# ---- 1. replicator role ----
# NOTE: heredoc delimiter is UNQUOTED (EOSQL) so $POSTGRES_REPLICATION_PASSWORD
# expands — `$$` in the PL/pgSQL DO block is escaped as \$\$ so bash doesn't
# expand it to the script's PID first (that used to be why this heredoc was
# single-quoted, which also silently prevented the password from expanding —
# found the hard way: this role's password was hardcoded to
# 'replicator_secret' regardless of POSTGRES_REPLICATION_PASSWORD, so any
# deploy where that env var held a different value broke replication).
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
DO \$\$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'replicator') THEN
    CREATE ROLE replicator WITH REPLICATION LOGIN ENCRYPTED PASSWORD '$POSTGRES_REPLICATION_PASSWORD';
  END IF;
END
\$\$;
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
