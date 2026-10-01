# HashiCorp Vault, production mode (#223) -- NOT `vault server -dev`.
# Single node with integrated (Raft) storage on a named volume, TLS on the
# listener, reachable only on the compose network (no published port).
# Sealed after every restart: unseal with 2 of the 3 Shamir keys
# (auto-chess-vault-unseal). The university VM has no cloud KMS for
# auto-unseal.

ui            = false
disable_mlock = true   # recommended with integrated storage (no swap of Raft data concerns here)

storage "raft" {
  path    = "/vault/data"
  node_id = "vault-1"
}

listener "tcp" {
  address         = "0.0.0.0:8200"
  cluster_address = "0.0.0.0:8201"
  tls_cert_file   = "/vault/tls/vault.crt"
  tls_key_file    = "/vault/tls/vault.key"
}

api_addr     = "https://vault:8200"
cluster_addr = "https://vault:8201"
