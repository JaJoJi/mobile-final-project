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

## 12. Match cleanup, retention and growth alerts (#388, #389, #390, #391)

Retention defaults are configured in `/etc/auto-chess/app.env`:

| Setting | Default | Effect |
|---|---:|---|
| `MATCH_EVENT_RETENTION_DAYS` | 90 | Clears detailed combat events from finished rounds after this many days, keeping round rows and match summaries. |
| `MATCH_HISTORY_RETENTION_DAYS` | 365 | Deletes finished/forfeited match summaries and their round rows after this many days. Must be at least the event retention period. |
| `MATCH_RETENTION_BATCH_SIZE` | 500 | Maximum rows updated/deleted by each database statement. |

Terminal matches now queue a one-shot Redis cleanup 30 seconds after the match row is saved. The worker confirms the row is terminal on the PostgreSQL primary, then removes only `match:<matchId>:*` runtime, shop, combat and action keys with Redis `SCAN` and `UNLINK`. It retries Redis failures up to five times. Room handoff already removes its code, membership and handoff keys when creating the match; its room hash remains for a five-minute retry tombstone. Existing Redis TTLs remain the fallback if enqueue or all retries fail. Inspect failed `match-cleanup` jobs and `match:<matchId>:*` keys if Redis memory remains high after games finish.

All BullMQ queues now remove completed jobs and keep at most 100 failed jobs for diagnosis. To clear previously retained jobs, build the backend and preview counts first:

```bash
$C exec nest-1 node dist/queue/queue-retention.cli.js
$C exec nest-1 node dist/queue/queue-retention.cli.js --apply
```

Each apply run removes at most 1,000 completed jobs older than one hour and 1,000 failed jobs older than seven days per queue. Run it again while old counts remain. It leaves waiting, active, delayed and repeat schedules intact. The Grafana BullMQ panel and `app_bullmq_jobs` metrics show retained completed and failed counts by queue.

The retention worker runs daily. Preview eligible rows and estimated event bytes before deletion:

```bash
$C exec nest-1 node dist/match/match-retention.cli.js
```

The command is dry-run by default. To apply the current policy immediately:

```bash
$C exec nest-1 node dist/match/match-retention.cli.js --apply
```

Review the JSON report in Nest logs for `eventRowsEligible`, `eventBytesEligible`, `matchesEligible`, `eventsCleared`, and `matchesDeleted`. Event cleanup nulls JSONB payloads but preserves round counts; match cleanup cascades to round rows. PostgreSQL reuses freed space internally; `VACUUM` reclaims it for reuse, while `VACUUM FULL` needs extra disk and an exclusive lock and should be scheduled separately. Daily Postgres backups retain the existing seven-day recovery window; restoring older detailed events requires a backup from before the retention run.

The Grafana dashboard **Auto Chess - Retention & Growth** shows database/table size history, Redis memory and namespace key counts, BullMQ state counts, and oldest waiting job age. Prometheus evaluates the thresholds in `infra/uni-vm/monitoring/alerts.yml`; alert states and firing details are visible at the Prometheus Alerts page and in Grafana's provisioned Prometheus data source.

| Alert | Threshold | Response |
|---|---|---|
| `HostDiskSpaceLow` / `HostDiskSpaceCritical` | Free host disk below 15% / 8% | `fiat222` (DevOps): check `docker system df`, database growth, and backup volume usage; expand disk or remove only reviewed artifacts. |
| `MatchTablesGrowingQuickly` / `MatchTablesGrowthCritical` | Match tables grow over 512 MiB / 1 GiB in 7 days | `fiat222` (DevOps): check the Grafana table trend and retention job logs. Run the dry-run report; confirm the retention settings are applied. |
| `RedisMemoryHigh` / `RedisMemoryCritical` | Redis exceeds 384 MiB / 512 MiB | `fiat222` (DevOps): inspect `app_redis_keys` by namespace in Grafana. Check stale match/room keys and cleanup failures before changing Redis memory limits. |
| `BullMQBacklogGrowing` / `BullMQJobsStale` | More than 100 waiting jobs / oldest waiting over 5 minutes | `fiat222` (DevOps): check worker logs and oldest waiting age for the queue; restore worker health and retry only after identifying the failure. |
| `MatchRetentionFailing` | One or more failed jobs on the `match-cleanup` queue | `fiat222` (DevOps): inspect the failed job name and Nest logs. Retry one-shot cleanup after fixing Redis or PostgreSQL; for the daily retention job, run the dry-run report first. |

The metrics endpoint is scraped by Prometheus over the private Compose network. Nginx returns 404 for public `/metrics` requests.

Not verified end to end yet: first `main` build with the stage (Gradle
download, ~10 min, cached in `/var/lib/jenkins/ci-cache/gradle` afterwards).
