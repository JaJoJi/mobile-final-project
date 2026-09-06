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
# NOTE: heredoc delimiter is SINGLE-QUOTED ('EOSQL') to disable shell
# variable expansion. Otherwise `$$` in the PL/pgSQL DO block gets
# expanded by bash to the script's PID (e.g. `DO 128 ... 128`) and
# psql rejects the syntax.
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-'EOSQL'
DO $$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'replicator') THEN
    CREATE ROLE replicator WITH REPLICATION LOGIN ENCRYPTED PASSWORD 'replicator_secret';
  END IF;
END
$$;
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
