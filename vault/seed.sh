#!/usr/bin/env bash
# P3-DO-19 — seed Vault's KV v2 engine with production secrets.
#
# Dev-mode Vault (`vault server -dev`) keeps everything in memory: a
# container restart loses all of it. Rerun this after every
# `docker compose up -d vault` — the Ansible playbook (#222) calls this
# automatically as part of deploy, so this is also the manual fallback.
#
# Secret values come from the deploy operator's shell environment, never
# hardcoded here and never committed anywhere.
set -euo pipefail

: "${VAULT_ADDR:=http://127.0.0.1:8200}"
: "${VAULT_TOKEN:?VAULT_TOKEN must be set — see vault/root_token.env.example}"
: "${DB_PASSWORD:?DB_PASSWORD must be set}"
: "${DB_REPLICATION_PASSWORD:?DB_REPLICATION_PASSWORD must be set}"
: "${REDIS_PASSWORD:?REDIS_PASSWORD must be set}"
: "${JWT_SECRET:?JWT_SECRET must be set}"

export VAULT_ADDR VAULT_TOKEN

echo "[vault/seed.sh] waiting for Vault at $VAULT_ADDR..."
for _ in $(seq 1 30); do
  vault status >/dev/null 2>&1 && break
  sleep 1
done
vault status >/dev/null 2>&1 || {
  echo "[vault/seed.sh] Vault not reachable at $VAULT_ADDR after 30s" >&2
  exit 1
}

# KV v2 at secret/ is enabled by default in dev mode, but dev-mode state
# is wiped on restart, so re-enabling idempotently covers a fresh container.
vault secrets list -format=json | grep -q '"secret/"' || \
  vault secrets enable -path=secret -version=2 kv

vault kv put secret/auto-chess/db    password="$DB_PASSWORD" replication_password="$DB_REPLICATION_PASSWORD"
vault kv put secret/auto-chess/redis password="$REDIS_PASSWORD"
vault kv put secret/auto-chess/jwt   secret="$JWT_SECRET"

echo "[vault/seed.sh] seeded secret/auto-chess/{db,redis,jwt}"
