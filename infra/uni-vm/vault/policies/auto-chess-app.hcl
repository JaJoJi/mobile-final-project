# Vault Agent for the app stack: read its own secrets, nothing else.
path "secret/data/auto-chess/prod/*" {
  capabilities = ["read"]
}
