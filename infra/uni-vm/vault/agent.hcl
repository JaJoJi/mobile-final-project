# Vault Agent (#223): logs in with the app's AppRole and renders the
# secrets the stack needs into the `vault_secrets` tmpfs volume. Nothing
# secret is written to the VM disk or kept in app.env.
#   app.env                  -> nest-1/2/3 (sourced at container start)
#   pg_password / repl_password -> Postgres primary/replica (*_FILE)
#   grafana_admin_password   -> Grafana (GF_SECURITY_ADMIN_PASSWORD__FILE)
# Non-secret names (POSTGRES_USER / POSTGRES_DB) come from the agent's env.

pid_file = "/tmp/vault-agent.pid"

vault {
  address = "https://vault:8200"
  ca_cert = "/vault/tls/vault.crt"
}

auto_auth {
  method "approle" {
    config = {
      role_id_file_path                   = "/vault/approle/role_id"
      secret_id_file_path                 = "/vault/approle/secret_id"
      remove_secret_id_file_after_reading = false
    }
  }
}

template_config {
  # Keep retrying while Vault is sealed (after a reboot) instead of exiting.
  exit_on_retry_failure         = false
  static_secret_render_interval = "5m"
}

template {
  destination = "/vault/secrets/app.env"
  perms       = "0444"
  contents    = <<EOT
{{ with secret "secret/data/auto-chess/prod/app" -}}
JWT_SECRET={{ .Data.data.JWT_SECRET }}
DATABASE_URL=postgres://{{ env "POSTGRES_USER" }}:{{ .Data.data.POSTGRES_PASSWORD }}@postgres-primary:5432/{{ env "POSTGRES_DB" }}
DATABASE_REPLICA_URL=postgres://{{ env "POSTGRES_USER" }}:{{ .Data.data.POSTGRES_PASSWORD }}@postgres-replica:5432/{{ env "POSTGRES_DB" }}
{{- end }}
EOT
}

template {
  destination = "/vault/secrets/pg_password"
  perms       = "0444"
  contents    = "{{ with secret \"secret/data/auto-chess/prod/app\" }}{{ .Data.data.POSTGRES_PASSWORD }}{{ end }}"
}

template {
  destination = "/vault/secrets/repl_password"
  perms       = "0444"
  contents    = "{{ with secret \"secret/data/auto-chess/prod/app\" }}{{ .Data.data.POSTGRES_REPLICATION_PASSWORD }}{{ end }}"
}

template {
  destination = "/vault/secrets/grafana_admin_password"
  perms       = "0444"
  contents    = "{{ with secret \"secret/data/auto-chess/prod/app\" }}{{ .Data.data.GRAFANA_ADMIN_PASSWORD }}{{ end }}"
}
