# Runbook — university VM (copy-paste commands)

Run everything **on the VM**, from the repo root (`/home/mobile-final-project`).
Shorthand used below:

```bash
C="sudo docker compose -f infra/uni-vm/app/compose.yml"
```

More detail: [infra/uni-vm/README.md](infra/uni-vm/README.md) · CI/Jenkins: [docs/08-runbook.md](docs/08-runbook.md)

---

## 1. First-time setup

```bash
sudo apt-get update && sudo apt-get install -y ansible-core git
git clone https://github.com/JaJoJi/mobile-final-project.git && cd mobile-final-project

sudo ansible-playbook -i localhost, -c local infra/uni-vm/site.yml   # safe to re-run

sudo nano /etc/psu-autologin.env            # PSU username / password
sudo systemctl start psu-autologin.service
sudo docker login -u fiatthanapon           # READ-ONLY Docker Hub token

$C up -d vault                              # Vault starts sealed
sudo infra/uni-vm/vault/bootstrap.sh        # ONCE: init, unseal, secrets -> Vault
#   -> prints 3 unseal keys ONCE. One key per teammate, then:
sudo shred -u /root/vault-init.json

$C pull && $C up -d
curl -s http://127.0.0.1/health
```

## 2. Update scripts / config

```bash
git pull
sudo ansible-playbook -i localhost, -c local infra/uni-vm/site.yml
$C up -d
```

## 3. Deploy a release

```bash
# newest main build
$C pull && $C up -d

# a specific release, with health check + auto-rollback (tag = commit from the Jenkins main build)
sudo auto-chess-deploy <tag>
sudo auto-chess-deploy --status
tail -n 30 /var/lib/auto-chess/deploy.log
```

Roll back by hand: set `IMAGE_TAG=<old-commit>` in `/etc/auto-chess/app.env`, then `$C pull && $C up -d`.

## 4. Status and logs

```bash
$C ps
$C logs -f nest-1
$C logs -f nginx                  # WAF + access log
$C logs --tail 50 vault-agent
curl -s http://127.0.0.1/health
curl -s http://127.0.0.1/health/ready
```

## 5. Vault

```bash
sudo auto-chess-vault-unseal                      # after EVERY VM/container restart (2 of 3 keys)

# status
$C exec -e VAULT_ADDR=https://127.0.0.1:8200 -e VAULT_CACERT=/vault/tls/vault.crt vault vault status

# backup now (also runs daily 03:30 via auto-chess-vault-backup.timer)
sudo infra/uni-vm/vault/backup.sh
ls -l /var/backups/vault                           # copy these OFF the VM
systemctl list-timers auto-chess-vault-backup.timer
```

Rotate a secret (needs a token from `vault operator generate-root`, 2 unseal keys):

```bash
$C exec -e VAULT_ADDR=https://127.0.0.1:8200 -e VAULT_CACERT=/vault/tls/vault.crt -e VAULT_TOKEN vault \
  vault kv patch secret/auto-chess/prod/app JWT_SECRET=<new>
$C restart nest-1 nest-2 nest-3                    # Agent re-renders within 5 min
```

Restore a snapshot: see header of `infra/uni-vm/vault/backup.sh`.

## 6. Monitoring

- Grafana: `http://<vm-ip>:3000`, user `admin`, password = `GRAFANA_ADMIN_PASSWORD` in Vault.
- Dashboard: *Auto Chess overview* (host, RED metrics, WAF hits, errors, logs).
- Metrics targets: `$C exec prometheus wget -qO- http://localhost:9090/api/v1/targets | head -c 600`

## 7. WAF (ModSecurity)

```bash
# attacks seen (JSON audit records)
$C logs nginx | grep -i '"messages"'

# test: SQLi probe must be logged (DetectionOnly: still passes; On: 403)
curl -s -o /dev/null -w '%{http_code}\n' "http://127.0.0.1/?id=1%27%20OR%201=1--"

# block mode / back to log-only
sudo nano /etc/auto-chess/app.env      # MODSEC_RULE_ENGINE=On | DetectionOnly
$C up -d nginx
```

## 8. Restart test (issue checklist)

```bash
sudo reboot
# after boot:
sudo auto-chess-vault-unseal
$C ps                                  # everything Up / healthy
curl -s http://127.0.0.1/health
```

## 9. Stop / wipe

```bash
$C down            # keep data
$C down -v         # DELETES database, Vault data, dashboards (needs re-bootstrap)
```

## 10. Troubleshooting

| Symptom | Check |
|---|---|
| nest "waiting for Vault secrets" | Vault sealed → `sudo auto-chess-vault-unseal`; `$C logs vault-agent` |
| `password authentication failed` | DB volume has an old password → `$C down -v`, redeploy (fresh data only) |
| No internet on VM | `sudo systemctl start psu-autologin.service`; `journalctl -u psu-autologin -n 30` |
| Grafana empty | `$C logs alloy`, `$C logs prometheus`; targets page (section 6) |
| Disk filling | `docker system df`; `docker image prune -f` |

## 11. Mobile app (APK for the emulator)

The repo has **no `mobile/android` folder** (only `lib/`, `web/`, ...), so the
Android project is generated on your machine first. The backend URL is baked
in at build time (`--dart-define`, see `mobile/lib/core/config/app_config.dart`);
use the VM's address (`<vm-ip>` = the one you open Grafana on), so the
emulator must run on a machine that is on the PSU network.

```bash
cd mobile
flutter create --platforms=android --project-name auto_chess_mobile --org th.ac.psu .   # once: generates android/
# release builds need the INTERNET permission, and the backend is plain http:
sed -i 's#<application#<uses-permission android:name="android.permission.INTERNET"/>
    <application android:usesCleartextTraffic="true"#' android/app/src/main/AndroidManifest.xml
flutter pub get
flutter build apk --release   --dart-define=API_BASE_URL=http://<vm-ip>   --dart-define=WS_BASE_URL=ws://<vm-ip>
# -> build/app/outputs/flutter-apk/app-release.apk
adb install -r build/app/outputs/flutter-apk/app-release.apk     # emulator running
```

Check the app reaches the backend: `curl http://<vm-ip>/health` from the same
machine first. Not verified end to end yet (generated Android project, not
committed): if `flutter create` complains about the package name, check
`name:` in `pubspec.yaml` and pass that to `--project-name`.


## 12. Production hardening: HTTPS, pgBouncer, DB backup, secret rotation (#139)

### HTTPS

nginx (ModSecurity) also listens on **443**. `site.yml` creates a
self-signed cert in `/etc/auto-chess/tls/` (the VM is behind the campus NAT,
no public name for Let's Encrypt).

```bash
curl -sk https://127.0.0.1/health                       # -k: self-signed
echo | openssl s_client -connect 127.0.0.1:443 2>/dev/null | openssl x509 -noout -subject -dates

# real cert: put fullchain at /etc/auto-chess/tls/server.crt and the key at
# server.key (key owner uid 101, mode 600), then
$C up -d nginx

# redirect HTTP -> HTTPS (leave OFF while the mobile app uses http://<vm>)
sudo nano /etc/auto-chess/app.env      # HTTPS_REDIRECT=on
$C up -d nginx
curl -sI http://127.0.0.1/ | head -3   # 301 -> https://...
```

### pgBouncer

`pgbouncer` (primary) and `pgbouncer-replica` sit between nest and Postgres:
transaction pooling, `DEFAULT_POOL_SIZE=20`, `MAX_CLIENT_CONN=1000`. nest's
`DATABASE_URL` / `DATABASE_REPLICA_URL` (rendered by Vault Agent) point at
them (`pgbouncer:6432`).

```bash
$C logs --tail 20 pgbouncer
$C exec pgbouncer sh -c 'psql -h 127.0.0.1 -p 6432 -U "$POSTGRES_USER" pgbouncer -c "SHOW POOLS;"'   # if psql exists in the image
curl -s http://127.0.0.1/health/ready                    # postgres up through the pooler

# bypass the pooler (debug / rollback): in app.env set
#   DB_PRIMARY_HOST=postgres-primary DB_PRIMARY_PORT=5432
#   DB_REPLICA_HOST=postgres-replica DB_REPLICA_PORT=5432
$C up -d vault-agent && $C up -d --force-recreate nest-1 nest-2 nest-3
```

### Daily database backup

`pg-backup` runs `pg_basebackup` against the primary at start and then every
day at 03:00 UTC into the `auto-chess_pg_backups` volume (last 7 kept).

```bash
$C logs --tail 5 pg-backup                               # "backup ok: /backup/base-<date> (<size>)"
$C exec pg-backup ls -lh /backup                         # the base-* directories (base.tar.gz + pg_wal.tar.gz)

# copy the newest backup off the VM
d=$($C exec -T pg-backup sh -c 'ls -1dt /backup/base-* | head -1' | tr -d '\r')
sudo docker cp "$($C ps -q pg-backup):$d" ./pg-backup-latest
```

**Restore drill** (into a throwaway volume, never over the live one):

```bash
sudo docker volume create restore_test
sudo docker run --rm -v restore_test:/var/lib/postgresql/data -v "$PWD/pg-backup-latest":/b:ro postgres:16-alpine \
  sh -c 'tar xzf /b/base.tar.gz -C /var/lib/postgresql/data && mkdir -p /var/lib/postgresql/data/pg_wal && tar xzf /b/pg_wal.tar.gz -C /var/lib/postgresql/data/pg_wal && chown -R postgres:postgres /var/lib/postgresql/data && chmod 700 /var/lib/postgresql/data'
sudo docker run --rm -d --name pg_restore_test -v restore_test:/var/lib/postgresql/data postgres:16-alpine
sleep 8; sudo docker exec pg_restore_test psql -U auto_chess -d auto_chess -c '\dt'      # tables are back
sudo docker rm -f pg_restore_test && sudo docker volume rm restore_test
```

### Secret rotation (no secret is hardcoded: all come from Vault via Vault Agent)

| Secret | When | How |
|---|---|---|
| `JWT_SECRET` | every 6 months, or if leaked | `vault kv patch secret/auto-chess/prod/app JWT_SECRET=$(openssl rand -hex 32)` (needs a token: `vault operator generate-root`, 2 unseal keys), wait for Agent (<= 5 min) or `$C restart vault-agent`, then restart nest **one at a time**: `$C restart nest-1; sleep 20; $C restart nest-2; sleep 20; $C restart nest-3`. All users are signed out (the app has no dual-secret support), and for the ~1 min of mixed instances some requests may get 401 and retry. |
| `POSTGRES_PASSWORD` | yearly / if leaked | `ALTER ROLE auto_chess PASSWORD '<new>'` on the primary **and** `vault kv patch ...POSTGRES_PASSWORD=<new>`, then `$C restart vault-agent pgbouncer pgbouncer-replica nest-1 nest-2 nest-3` |
| `POSTGRES_REPLICATION_PASSWORD` | yearly | `ALTER ROLE replicator PASSWORD '<new>'`, `vault kv patch`, restart `vault-agent pg-backup postgres-replica` (the replica re-reads it) |
| Grafana admin | on staff change | Grafana UI, or `vault kv patch ...GRAFANA_ADMIN_PASSWORD=` + `grafana cli admin reset-admin-password` |
| TLS cert | before expiry (825 days for the self-signed one) | replace files, `$C up -d nginx` |
