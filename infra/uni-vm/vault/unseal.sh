#!/usr/bin/env bash
# Unseal Vault after a VM / container restart (#223). Needs 2 of the 3
# unseal keys (typed, not echoed). Vault Agent retries on its own and the
# app comes up once the secrets render.
#
#   sudo auto-chess-vault-unseal
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")/../../.."
C=(docker compose -f infra/uni-vm/app/compose.yml)
E=(-e VAULT_ADDR=https://127.0.0.1:8200 -e VAULT_CACERT=/vault/tls/vault.crt)

sealed() {
  "${C[@]}" exec -T "${E[@]}" vault vault status -format=json 2>/dev/null \
    | python3 -c "import json,sys; print(json.load(sys.stdin)['sealed'])"
}

while [[ $(sealed) == True ]]; do
  read -r -s -p "Unseal key: " key; echo
  printf '%s\n' "$key" | "${C[@]}" exec -T "${E[@]}" vault \
    sh -c 'read -r k; vault operator unseal "$k" | grep -E "Sealed|Unseal Progress"'
done
echo "Vault is unsealed."
