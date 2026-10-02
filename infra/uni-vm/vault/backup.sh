#!/usr/bin/env bash
# Daily Raft snapshot of Vault (#223), run by auto-chess-vault-backup.timer.
# Logs in with the `backup` AppRole (snapshot-only policy), saves to
# /var/backups/vault and keeps the last 7. Copy them off the VM too:
# losing the Raft data = losing every secret.
#
# Restore (needs a root token: `vault operator generate-root` with 2 keys):
#   docker compose -f infra/uni-vm/app/compose.yml cp <file>.snap vault:/tmp/r.snap
#   docker compose ... exec -e VAULT_TOKEN vault vault operator raft snapshot restore -force /tmp/r.snap
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")/../../.."
C=(docker compose -f infra/uni-vm/app/compose.yml)
E=(-e VAULT_ADDR=https://127.0.0.1:8200 -e VAULT_CACERT=/vault/tls/vault.crt)
CREDS=/etc/auto-chess/vault-backup
OUT=/var/backups/vault
mkdir -p "$OUT" && chmod 700 "$OUT"

ROLE_ID=$(cat "$CREDS/role_id") SECRET_ID=$(cat "$CREDS/secret_id")
export ROLE_ID SECRET_ID
VAULT_TOKEN=$("${C[@]}" exec -T "${E[@]}" -e ROLE_ID -e SECRET_ID vault sh -c \
  'vault write -field=token auth/approle/login role_id="$ROLE_ID" secret_id="$SECRET_ID"')
export VAULT_TOKEN

name="vault-$(date +%Y%m%d-%H%M).snap"
"${C[@]}" exec -T "${E[@]}" -e VAULT_TOKEN vault vault operator raft snapshot save "/tmp/$name"
"${C[@]}" cp "vault:/tmp/$name" "$OUT/$name"
"${C[@]}" exec -T vault rm -f "/tmp/$name"
chmod 600 "$OUT/$name"

ls -1t "$OUT"/vault-*.snap | tail -n +8 | xargs -r rm -f
echo "saved $OUT/$name"
