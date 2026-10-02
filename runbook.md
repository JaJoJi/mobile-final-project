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

## 11. Mobile app (release APK, #194)

**Jenkins builds it**: every build of `main` (after the image is published)
runs *Mobile · build APK* and archives `apk/auto-chess-<commit>.apk`
(version `0.1.<build number>`, debug-signed release build: installable with
`adb` or "unknown sources", no Play Store key). The backend address is baked
in at build time from the job parameter `APK_API_BASE_URL` (default
`http://172.30.58.10`, the university VM; `WS_BASE_URL` is derived) -- change
it with *Build with Parameters* if the VM's address changes. Turn the stage
off with `ENABLE_APK_BUILD`.

```bash
# download from the Jenkins build page (Artifacts), then on the machine with the emulator:
adb install -r auto-chess-<commit>.apk
```

The emulator must be on a network that reaches the VM (PSU Wi-Fi/VPN):
`curl http://<vm-ip>/health` from the same machine first. Cleartext http and
the INTERNET permission are enabled in `mobile/android/app/src/main/AndroidManifest.xml`
(release builds don't get INTERNET from Flutter). Once the VM serves a real
HTTPS certificate, change `APK_API_BASE_URL` to `https://...`.

Local build (needs the Android SDK):

```bash
cd mobile
flutter build apk --release --dart-define=API_BASE_URL=http://<vm-ip> --dart-define=WS_BASE_URL=ws://<vm-ip>
# -> build/app/outputs/flutter-apk/app-release.apk
```

Not verified end to end yet: first `main` build with the stage (Gradle
download, ~10 min, cached in `/var/lib/jenkins/ci-cache/gradle` afterwards).
