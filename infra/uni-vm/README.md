# University VM — app + monitoring host

The game backend runs here: nginx → nest ×3 → Redis + Postgres
primary/replica, behind ModSecurity (#224), with secrets in Vault (#223)
and the Grafana stack (#225) on the same VM.

```
 Jenkins (Azure) ── release on main ──► Docker Hub  fiatthanapon/mobile-final-project:<commit>
                                              ▲
 University VM (behind campus NAT) ── pulls ──┘   sudo auto-chess-deploy <commit>
   ├─ psu-autologin.timer  keeps the internet session alive (PSU portal)
   └─ docker compose: nginx :80 → nest-1/2/3 → redis, postgres-primary → replica
```

**Pull-based on purpose.** Jenkins can't reach a VM behind the campus NAT,
and doesn't need to. It stops at "image passed every gate and is on
Docker Hub". The VM pulls that exact image (no rebuild), checks
`/health/ready`, and rolls back to the previous tag if the new one isn't
healthy.

| Path | What |
|---|---|
| `site.yml` | Ansible, run **on the VM itself**: auto-login, Docker Engine + compose, log rotation, `/etc/auto-chess/app.env`, `auto-chess-deploy` command |
| `app/compose.yml` | production stack: app + WAF + Postgres/Redis + Vault + monitoring |
| `vault/` | Vault config, policies, `bootstrap.sh` (one-time), `unseal.sh`, `backup.sh` |
| `monitoring/` | Prometheus, Loki, Tempo, Alloy config + Grafana provisioning/dashboard |
| `app/deploy.sh` | `auto-chess-deploy <tag>`: pull → up → health check → keep or roll back |
| `app/app.env.example` | template for the non-secret settings (secrets live in Vault) |
| `psu-autologin/` | captive-portal auto-login ([README](psu-autologin/README.md)) |

## First-time setup

```bash
# 0. Get online once by hand (portal), then:
sudo apt-get update && sudo apt-get install -y ansible-core git
git clone https://github.com/JaJoJi/mobile-final-project.git
cd mobile-final-project

# 1. Configure the VM (safe to re-run)
sudo ansible-playbook -i localhost, -c local infra/uni-vm/site.yml

# 2. PSU portal credentials
sudo nano /etc/psu-autologin.env          # PSU username / password
sudo systemctl start psu-autologin.service

# 3. Docker Hub: create a READ-ONLY access token for this VM
#    (hub.docker.com → Account settings → Personal access tokens → Read-only)
sudo docker login -u fiatthanapon         # paste the token as the password

# 4. Vault first (production mode, starts sealed)
sudo docker compose -f infra/uni-vm/app/compose.yml up -d vault
sudo infra/uni-vm/vault/bootstrap.sh      # ONCE -- see "Vault" below

# 5. Everything else
sudo docker compose -f infra/uni-vm/app/compose.yml pull
sudo docker compose -f infra/uni-vm/app/compose.yml up -d
curl -s http://127.0.0.1/health | head -c 300
```

## Day to day

| What | Command |
|---|---|
| Deploy the newest release | `sudo docker compose -f infra/uni-vm/app/compose.yml pull && sudo docker compose -f infra/uni-vm/app/compose.yml up -d` |
| Pin / roll back to a release | set `IMAGE_TAG=<commit>` in `/etc/auto-chess/app.env`, then `pull` + `up -d` |
| Deploy with health check + auto-rollback | `sudo auto-chess-deploy <tag>` (history: `/var/lib/auto-chess/deploy.log`) |
| What's running | `sudo docker compose -f infra/uni-vm/app/compose.yml ps` |
| Logs | `sudo docker compose -f infra/uni-vm/app/compose.yml logs -f nest-1` |
| After a VM reboot | `sudo auto-chess-vault-unseal` (2 of 3 keys), the rest comes up by itself |
| Stop (keep data) / wipe DB | `... down` / `... down -v` |
| Update scripts/config | `git pull && sudo ansible-playbook -i localhost, -c local infra/uni-vm/site.yml` |

## Vault (#223)

Production mode: Raft storage on a volume, TLS listener, **no published
port**, sealed after every restart. Secrets (Postgres + replication
passwords, JWT secret, Grafana admin password) live at
`secret/auto-chess/prod/app`. Vault Agent logs in with an AppRole
(read-only policy) and renders them into an **in-memory volume**; nest,
Postgres and Grafana read them from there, nothing secret is on disk or in
`app.env`.

- `vault/bootstrap.sh` (once): init with 3 key shares / threshold 2, KV v2,
  audit log (stdout → Alloy → Loki), policies + AppRoles, moves the secrets
  from `app.env` (generates any that are missing), revokes the root token.
  It prints the unseal keys **once** -- give each to a different teammate,
  then `shred -u /root/vault-init.json`.
- Reboot: `sudo auto-chess-vault-unseal`; Vault Agent retries, the app starts.
- Rotate a secret: `vault kv patch secret/auto-chess/prod/app JWT_SECRET=...`
  (needs a token; Agent re-renders within 5 min, restart nest to pick it up).
  Changing the Postgres password also needs `ALTER ROLE`.
- Backup: `auto-chess-vault-backup.timer` takes a daily Raft snapshot into
  `/var/backups/vault` (last 7). Copy them off the VM.

## Monitoring (#225)

| Service | Role |
|---|---|
| Beyla | eBPF auto-instrumentation → RED metrics of nest + nginx |
| Alloy | the one agent: container logs → Loki, host metrics → Prometheus |
| Prometheus / Loki / Tempo | metrics (7 d) / logs / traces |
| Grafana | `http://<vm>:3000`, user `admin`, password from Vault (`GRAFANA_ADMIN_PASSWORD`) |

Datasources and the *Auto Chess overview* dashboard are provisioned from
`monitoring/`. nest sends traces through the OTel SDK
(`OTEL_EXPORTER_OTLP_ENDPOINT`); log lines carry `trace_id`, so Grafana
jumps from a log line to its trace. ModSecurity audit records and Vault
audit records arrive in Loki with `log_type=modsec_audit` / `vault_audit`.

## WAF (nginx + ModSecurity, #224)

The `nginx` service is the official `owasp/modsecurity-crs` image (LTS,
pinned) with our server block (`nginx/modsec/default.conf.template`, same
least_conn / WebSocket / `/health` routing as dev) and a **curated** CRS
rule list (`nginx/modsec/setup.conf.template`), paranoia level 1.

It starts in **DetectionOnly**: suspicious requests are logged, not blocked.

```bash
# Watch what it would block (JSON audit records)
sudo docker compose -f infra/uni-vm/app/compose.yml logs -f nginx | grep -i '"messages"'
# Quick check it sees attacks (should log a 942 SQLi hit, still 200/404 in DetectionOnly)
curl -s -o /dev/null -w '%{http_code}
' "http://127.0.0.1/?id=1%27%20OR%201=1--"
```

After a day of normal use with no false positives, set
`MODSEC_RULE_ENGINE=On` in `/etc/auto-chess/app.env` and run `up -d`.
The same curl then returns `403`. To roll back, set it back to `DetectionOnly`.

## Notes

- **Secrets** are in Vault; `/etc/auto-chess/app.env` has only non-secret
  settings. `POSTGRES_*` user/db are only read the first time the database
  volume is created.
- **Data** lives in the Docker volumes `auto-chess_pg_primary_data` /
  `auto-chess_pg_replica_data`. `docker compose down` keeps them;
  `down -v` deletes the database.
- **Ports 80 (app) and 3000 (Grafana)** are the only published ports. Who can reach it depends on the
  campus network (ask IT if it must be reachable from outside PSU).
