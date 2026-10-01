# University VM — app + monitoring host

The game backend runs here: nginx → nest ×3 → Redis + Postgres
primary/replica. ModSecurity (#224), Vault (#223) and the Grafana stack
(#225) are added later on the same VM.

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
| `app/compose.yml` | production stack, using the Docker Hub image + pinned Postgres/Redis |
| `app/deploy.sh` | `auto-chess-deploy <tag>`: pull → up → health check → keep or roll back |
| `app/app.env.example` | template for the production secrets |
| `psu-autologin/` | captive-portal auto-login ([README](psu-autologin/README.md)) |

## First-time setup

```bash
# 0. Get online once by hand (portal), then:
sudo apt-get update && sudo apt-get install -y ansible-core git
git clone https://github.com/JaJoJi/mobile-final-project.git
cd mobile-final-project

# 1. Configure the VM (safe to re-run)
sudo ansible-playbook -i localhost, -c local infra/uni-vm/site.yml

# 2. Secrets -- replace every CHANGE_ME (openssl rand -hex 32)
sudo nano /etc/auto-chess/app.env
sudo nano /etc/psu-autologin.env          # PSU username / password
sudo systemctl start psu-autologin.service

# 3. Docker Hub: create a READ-ONLY access token for this VM
#    (hub.docker.com → Account settings → Personal access tokens → Read-only)
sudo docker login -u fiatthanapon         # paste the token as the password

# 4. Deploy (from the repo root; .env next to compose.yml -> /etc/auto-chess/app.env)
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
| Stop (keep data) / wipe DB | `... down` / `... down -v` |
| Update scripts/config | `git pull && sudo ansible-playbook -i localhost, -c local infra/uni-vm/site.yml` |

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

- **Secrets** stay in `/etc/auto-chess/app.env` (root, 0600) until Vault (#223)
  takes over. `POSTGRES_*` are only read the first time the database
  volume is created; changing them later doesn't change the DB.
- **Data** lives in the Docker volumes `auto-chess_pg_primary_data` /
  `auto-chess_pg_replica_data`. `docker compose down` keeps them;
  `down -v` deletes the database.
- **Port 80** is the only published port. Who can reach it depends on the
  campus network (ask IT if it must be reachable from outside PSU).
