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

# 4. Deploy the latest release (tag = short commit of the Jenkins main build)
sudo auto-chess-deploy d5ec4c4
curl -s http://127.0.0.1/health | head -c 300
```

## Day to day

| What | Command |
|---|---|
| Deploy a release | `sudo auto-chess-deploy <tag>` |
| What's running | `sudo auto-chess-deploy --status` |
| Deploy history | `cat /var/lib/auto-chess/deploy.log` |
| Roll back by hand | `sudo auto-chess-deploy <previous tag>` |
| Logs | `docker compose -p auto-chess logs -f nest-1` |
| Update scripts/config | `git pull && sudo ansible-playbook -i localhost, -c local infra/uni-vm/site.yml` |

## Notes

- **Secrets** stay in `/etc/auto-chess/app.env` (root, 0600) until Vault (#223)
  takes over. `POSTGRES_*` are only read the first time the database
  volume is created; changing them later doesn't change the DB.
- **Data** lives in the Docker volumes `auto-chess_pg_primary_data` /
  `auto-chess_pg_replica_data`. `docker compose down` keeps them;
  `down -v` deletes the database.
- **Port 80** is the only published port. Who can reach it depends on the
  campus network (ask IT if it must be reachable from outside PSU).
