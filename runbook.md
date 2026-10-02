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


## 13. Load test (k6, #140 / #224)

`k6/load.js` proves the NFRs: p95 round-state event < 500 ms (NFR-2), p95
combat latency < 500 ms (NFR-14), >= 50 concurrent matches (NFR-3). Each
VU is one player; matchmaking pairs two VUs, so `MATCHES=50` = 100 VUs =
50 live matches, each playing `ROUNDS=3` rounds (buy -> ready -> battle ->
combat events -> combat_done). Latencies are measured on the client that
sent the request and are a conservative upper bound (see the file header).

**On the university VM** (through nginx + ModSecurity, so this is also the
#224 "WAF memory stays bounded" test):

```bash
# terminal 1: watch memory while it runs
watch -n 2 "sudo docker stats --no-stream --format '{{.Name}} {{.CPUPerc}} {{.MemUsage}}' | sort -k3 -h -r | head -8"

# terminal 2: the test (k6 prints the thresholds at the end; exit code 99 = an NFR failed)
sudo docker run --rm -i --network host -e TARGETS=http://127.0.0.1 -e MATCHES=50 \
  grafana/k6:1.3.0@sha256:3ddc8b1a33a2c3d8edc6e99b6a762ae36cba08788463458f5e6a7703e14eb77d run - < k6/load.js

# afterwards: no errors in the app / WAF logs, nginx memory still below its 512m cap
$C logs --since 10m nest-1 nest-2 nest-3 | grep -c '"level":50'
sudo docker stats --no-stream auto-chess-nginx-1

# remove the throwaway users (their matches stay in the history tables)
$C exec postgres-primary psql -U auto_chess -d auto_chess -c "DELETE FROM users WHERE email LIKE '%@load.test'"
```

Read the result: `round_state_latency_ms` and `combat_latency_ms` p(95) must be
< 500; `player_failed` must be 0 (a player that never got paired, a socket
that closed, or a missing event within 20 s counts as failed). Put the k6
summary + the `docker stats` lines in the issue as evidence.

**In Jenkins** (opt-in): tick `ENABLE_LOAD_TEST` on a `dev`/`main` build. It
runs 10 matches against the ephemeral 3-instance stack and fails the build
on the same thresholds; `reports/k6/summary.json` is archived. Default off:
the small Jenkins VM would be the bottleneck, not the app.
