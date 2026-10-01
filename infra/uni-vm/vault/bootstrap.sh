#!/usr/bin/env bash
# One-time Vault setup on the university VM (#223). Run once, as root,
# from the repo root, after `docker compose ... up -d vault`:
#
#   sudo infra/uni-vm/vault/bootstrap.sh
#
#  1. init (3 Shamir keys, threshold 2) + unseal
#  2. KV v2 at secret/, audit log to stdout (-> Alloy -> Loki)
#  3. policies + AppRoles: auto-chess-app (agent, read-only on its path),
#     backup (raft snapshots only); credentials to root-only files
#  4. move the secrets out of /etc/auto-chess/app.env into
#     secret/auto-chess/prod/app (generates any that are missing)
#  5. revoke the root token
#
# Prints the unseal keys + root token ONCE. Give each key to a different
# team member (password manager / offline), then delete the init file.
set -euo pipefail

[[ $EUID -eq 0 ]] || { echo "run with sudo"; exit 1; }
cd "$(dirname "$(readlink -f "$0")")/../../.."

ENV_FILE=/etc/auto-chess/app.env
INIT_FILE=/root/vault-init.json
AGENT_DIR=/etc/auto-chess/vault-agent
BACKUP_DIR=/etc/auto-chess/vault-backup
C=(docker compose -f infra/uni-vm/app/compose.yml)

# vault CLI inside the vault container, talking to itself over TLS.
# VAULT_TOKEN is passed by name (-e VAULT_TOKEN), never on a command line.
v() {
  "${C[@]}" exec -T -e VAULT_ADDR=https://127.0.0.1:8200 \
    -e VAULT_CACERT=/vault/tls/vault.crt -e VAULT_TOKEN vault vault "$@"
}
json() { python3 -c "import json,sys; print(json.load(sys.stdin)$1)"; }

status=$(v status -format=json 2>/dev/null || true)
if [[ -z $status ]]; then
  echo "Vault isn't running -- start it first:"
  echo "  docker compose -f infra/uni-vm/app/compose.yml up -d vault"
  exit 1
fi
if [[ $(json "['initialized']" <<<"$status") == True ]]; then
  echo "Vault is already initialized -- bootstrap runs only once."
  echo "Unseal after a restart: sudo auto-chess-vault-unseal"
  exit 1
fi

echo "== 1. init + unseal"
umask 077
v operator init -key-shares=3 -key-threshold=2 -format=json > "$INIT_FILE"
for i in 0 1; do
  json "['unseal_keys_b64'][$i]" < "$INIT_FILE" \
    | "${C[@]}" exec -T -e VAULT_ADDR=https://127.0.0.1:8200 -e VAULT_CACERT=/vault/tls/vault.crt \
        vault sh -c 'read -r k; vault operator unseal "$k" >/dev/null'
done
VAULT_TOKEN=$(json "['root_token']" < "$INIT_FILE")
export VAULT_TOKEN

echo "== 2. KV v2 + audit log"
v secrets enable -path=secret kv-v2
v audit enable file file_path=stdout

echo "== 3. policies + AppRoles"
v policy write auto-chess-app /vault/policies/auto-chess-app.hcl
v policy write backup /vault/policies/backup.hcl
v auth enable approle
v write auth/approle/role/auto-chess-app token_policies=auto-chess-app \
  token_ttl=1h token_max_ttl=24h secret_id_ttl=0
v write auth/approle/role/backup token_policies=backup token_ttl=10m secret_id_ttl=0

mkdir -p "$AGENT_DIR" "$BACKUP_DIR"
chmod 700 "$AGENT_DIR" "$BACKUP_DIR"
v read -field=role_id auth/approle/role/auto-chess-app/role-id > "$AGENT_DIR/role_id"
v write -f -field=secret_id auth/approle/role/auto-chess-app/secret-id > "$AGENT_DIR/secret_id"
v read -field=role_id auth/approle/role/backup/role-id > "$BACKUP_DIR/role_id"
v write -f -field=secret_id auth/approle/role/backup/secret-id > "$BACKUP_DIR/secret_id"
chmod 600 "$AGENT_DIR"/* "$BACKUP_DIR"/*

echo "== 4. secrets: app.env -> Vault"
get() { grep -E "^$1=" "$ENV_FILE" 2>/dev/null | tail -1 | cut -d= -f2- | tr -d "'\""; }
secret() { local val; val=$(get "$1"); [[ -n $val && $val != CHANGE_ME ]] && echo "$val" || openssl rand -hex 32; }
# Values travel through the environment, not argv (no `ps` exposure).
export S_PG S_REPL S_JWT S_GF
S_PG=$(secret POSTGRES_PASSWORD); S_REPL=$(secret POSTGRES_REPLICATION_PASSWORD)
S_JWT=$(secret JWT_SECRET); S_GF=$(secret GRAFANA_ADMIN_PASSWORD)
python3 - <<'PY' | v kv put secret/auto-chess/prod/app -
import json, os
print(json.dumps({
    "POSTGRES_PASSWORD": os.environ["S_PG"],
    "POSTGRES_REPLICATION_PASSWORD": os.environ["S_REPL"],
    "JWT_SECRET": os.environ["S_JWT"],
    "GRAFANA_ADMIN_PASSWORD": os.environ["S_GF"],
}))
PY
cp -p "$ENV_FILE" "$ENV_FILE.pre-vault"
sed -i -E '/^(POSTGRES_PASSWORD|POSTGRES_REPLICATION_PASSWORD|JWT_SECRET|GRAFANA_ADMIN_PASSWORD)=/d' "$ENV_FILE"

echo "== 5. revoke root token"
v token revoke -self
unset VAULT_TOKEN

cat <<EOF

Vault is initialized, unsealed and holding the app secrets.

  !! Unseal keys + root token are in $INIT_FILE -- shown ONCE:
$(python3 -c "import json;d=json.load(open('$INIT_FILE'));[print('     key',i+1,':',k) for i,k in enumerate(d['unseal_keys_b64'])]")
     (root token already revoked; regenerate with 2 keys if ever needed)

  1. Give each key to a different team member (password manager), then:
       sudo shred -u $INIT_FILE
  2. Start the rest:  docker compose -f infra/uni-vm/app/compose.yml up -d
  3. When the app is healthy, delete the old secrets file:
       sudo shred -u $ENV_FILE.pre-vault
EOF
