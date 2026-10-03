# Operations Runbook

> Written from what's actually built today. Sections marked **Not yet implemented**
> describe the design other open issues will land — don't treat them as
> working procedure until that issue merges and this doc is updated to match.

Related: [`docs/03-architecture.md`](./03-architecture.md) (topology) ·
[`docker-compose.yml`](../docker-compose.yml) · [`.env.example`](../.env.example)

## Contacts

2-3 person course team. Ping in whatever channel the team already uses (no
dedicated on-call tooling — that's disproportionate for this project's size).

| Area | Owner |
|---|---|
| Backend / infra | `@JaJoJi`, `@fiat222` |
| Mobile | `@JaJoJi`, `@fiat222` |

## 1. Deploy

**Today**: there is no deployed environment. The only way to run the stack
is local, from a clone:

```bash
cp .env.example .env      # fill in real values for anything beyond local dev
docker compose up -d --build
curl http://localhost/health/ready
```

`nest-1` runs migrations on boot (`RUN_MIGRATIONS=true` in
`docker-compose.yml`); `nest-2`/`nest-3` don't, to avoid three instances
racing the same migration.

**Not yet implemented**: a real staging/production target, `docker-compose.prod.yml`,
and a deploy step in CI ([#193](https://github.com/JaJoJi/mobile-final-project/issues/193)).
Once that lands, this section becomes: pull the tagged image, `docker compose
-f docker-compose.prod.yml pull && up -d`, then the post-deploy check below.

**Post-deploy check** (works today against local, will work against a real
host once #193 exists):

```bash
curl -f http://<host>/health/ready || echo "DEPLOY BAD — do not consider this live"
```

## 2. Rollback

**Not yet implemented** — no deployed environment to roll back yet. Designed
mechanism, once [#137](https://github.com/JaJoJi/mobile-final-project/issues/137)
(GHCR publish) and #193 (deploy target) exist:

1. Identify the last-known-good tag: `git tag --sort=-creatordate | head -5`
   or check the GHCR package page for the previous `vX.Y.Z`.
2. On the host: `docker compose -f docker-compose.prod.yml pull
   ghcr.io/jajoji/auto_chess-backend:<previous-tag>` then `up -d`.
3. Re-run the post-deploy check above.
4. If the bad deploy already ran a migration, rolling the *image* back does
   **not** roll the schema back — `npm run migration:revert` must be run
   manually before down-stepping the image, or the old code will hit a
   schema it doesn't understand. There is currently no automated migration
   rollback gate; treat every migrating deploy as effectively one-way until
   one exists.

This has not been drilled against a real deploy yet — do a real rollback
drill the first time #193 lands, and update this section with what actually
happened.

## 3. Backup & Restore Drill

**Today**: `docker-compose.yml` runs `postgres-primary` with a streaming
`postgres-replica` (WAL streaming, `pg_basebackup -R`). This protects against
losing the primary container, **not** against data loss, corruption, or a
bad migration — the replica faithfully replicates those too.

There is no scheduled `pg_basebackup` snapshot and no off-site copy yet
([#139](https://github.com/JaJoJi/mobile-final-project/issues/139)). Until
that lands, the only "backup" is whatever's in the `pg_primary_data` /
`pg_replica_data` Docker volumes on one machine — losing that machine loses
the data.

**Manual snapshot** (do this before anything risky — a schema migration, a
Postgres major-version bump):

```bash
docker exec ac-postgres-primary pg_dump -U ${POSTGRES_USER} -d ${POSTGRES_DB} \
  -Fc -f /tmp/manual-snapshot.dump
docker cp ac-postgres-primary:/tmp/manual-snapshot.dump ./manual-snapshot.dump
```

**Restore a snapshot** (into a scratch container — never test-restore onto
the running primary):

```bash
docker run -d --name pg-restore-check -e POSTGRES_PASSWORD=scratch postgres:16-alpine
docker cp ./manual-snapshot.dump pg-restore-check:/tmp/snapshot.dump
docker exec pg-restore-check pg_restore -U postgres -d postgres --create /tmp/snapshot.dump
docker rm -f pg-restore-check
```

Once #139's scheduled backup exists, replace this section with the real
cadence and run the restore drill above against an actual scheduled backup
file at least once before calling it done — a backup nobody has ever
restored is a hope, not a backup.

## 4. Secret Rotation

**Today's secrets** (from `.env.example`): `POSTGRES_PASSWORD`,
`POSTGRES_REPLICATION_PASSWORD`, `PGADMIN_PASSWORD`, `JWT_SECRET`. All are
dev-default placeholder values in `.env.example` — never commit a real
`.env`.

**Rotating `JWT_SECRET` today** (no dual-secret support yet — this
invalidates every live session):

```bash
openssl rand -base64 32          # new secret
# put it in .env as JWT_SECRET, then:
docker compose up -d --build nest-1 nest-2 nest-3
```

Every logged-in user's next request fails auth and they're bounced to
login. Acceptable for a course project's dev/staging use; **not** acceptable
once real users exist without the dual-secret rollover
([#139](https://github.com/JaJoJi/mobile-final-project/issues/139) — verify
against both `JWT_SECRET` and `JWT_SECRET_OLD` for a rollover window).

**Rotating Postgres passwords**: update `.env`, then `docker compose up -d`
(Postgres re-reads env on container recreation — the volume/data isn't
affected, only the container's auth).

## 5. Incident Response

No metrics/log aggregation exists yet
([#225](https://github.com/JaJoJi/mobile-final-project/issues/225) —
Beyla + mtail + Loki + Tempo → Prometheus/Loki/Tempo → Grafana). Until
then, first three things to check when something's wrong:

1. **Is it up?** `curl http://<host>/health/ready` — checks DB + Redis
   reachability from the app's perspective (see `backend/src/common/health.controller.ts`).
2. **What are the containers doing?**
   ```bash
   docker compose ps
   docker compose logs --tail=200 nest-1 nest-2 nest-3
   docker compose logs --tail=100 redis postgres-primary
   ```
3. **Which instance?** Logs include `HOSTNAME` (`nest-1`/`nest-2`/`nest-3`)
   — useful since `nginx` load-balances across all three and a bad node can
   hide behind two healthy ones.

Once #225 lands, step 2/3 become "open the Grafana dashboard" instead of
grepping `docker compose logs` by hand — update this section then.

## 6. Jenkins CI Setup

Jenkins runs on the Azure VM `mfp-jenkins`, bound to `127.0.0.1:8080` and
published over HTTPS by Caddy at https://mfp-jenkins-psu.malaysiawest.cloudapp.azure.com (since
2026-09-30; SSH only from known IPs). GitHub starts builds through a
signed webhook, Jenkins posts ✅/❌ back to commits/PRs and emails results
with the log. Hardening checklist: #288.

1. **Host:** created + configured by Ansible — `infra/ansible/`
   (`provision.yml` makes the VM, `jenkins-host.yml` installs Docker +
   Jenkins; see its README). Every build tool (Node, Flutter, Gitleaks,
   Semgrep, Trivy, Checkov, ZAP, Postgres, Redis) runs as a container
   pinned by version + digest in the `Jenkinsfile` (`IMAGES` map). Keep
   **≥ 30 GB free disk** and **≥ 4 GB RAM**.
2. **Open the UI:** https://mfp-jenkins-psu.malaysiawest.cloudapp.azure.com (Caddy + Let's Encrypt in
   front of Jenkins on loopback; log in with your Jenkins account).
   Keep **anonymous read** and **Allow users to sign up** off in
   Manage Jenkins → Security — `jenkins-host.yml` won't publish Jenkins
   otherwise. SSH (admin only) still needs your IP in `admin_cidrs`.
3. **Plugins:** Pipeline, Pipeline: Multibranch, Git, **GitHub Branch
   Source**, **Docker Pipeline**, JUnit, **HTML Publisher**, Timestamper,
   Credentials Binding, **Email Extension**.
4. **Credentials** (Manage Jenkins → Credentials → Global):
   | ID | Kind | What |
   |---|---|---|
   | `github-token` | Username with password | GitHub username + **classic** PAT with `repo:status` + `public_repo` (classic because the repo belongs to another user; fine-grained tokens can't reach collaborator repos). Used to scan the repo and post commit statuses. |
   | `notify-email` | Secret text | Recipient address(es), comma-separated — a credential because the repo is public |
   | `smtp-gmail` | Username with password | Gmail address + **App Password** (Google Account → Security → App passwords; needs 2-Step Verification). Never the real Gmail password. |
   | `dockerhub-token` | Username with password | Docker Hub user `fiatthanapon` + PAT (Read & Write). Pushes `fiatthanapon/mobile-final-project` (private) on `main`. |
5. **SMTP** (Manage Jenkins → System → *Extended E-mail Notification*):
   SMTP server `smtp.gmail.com`, port `465`, *Use SSL*, credentials
   `smtp-gmail`, Default Content Type *plain text*. Use *Test
   configuration* before relying on it. `ENABLE_NOTIFICATIONS` is on by
   default, so both email credentials must exist or builds fail in `post`.
6. **Job:** New Item → **Multibranch Pipeline** `mobile-final-project`
   - Branch source **GitHub**, credentials `github-token`, URL
     `https://github.com/JaJoJi/mobile-final-project`
   - Behaviours: discover branches (all); discover PRs from origin
     (merge with target); discover PRs from forks — trust **From users
     with Admin or Write permission**; **Filter by name (with
     wildcards)** include `dev main PR-*` (the repo has ~40 stale
     feature branches; without the filter each gets built)
   - **Scan Multibranch Pipeline Triggers → Periodically if not otherwise
     run: 1 hour** (fallback only; the webhook below starts builds)
   - Orphaned items: discard after 7 days
7. **Webhook** (builds start seconds after a push/PR instead of polling):
   - Jenkins: Manage Jenkins → Credentials → add **Secret text**
     `github-webhook-secret` (random: `openssl rand -hex 32`). Manage
     Jenkins → System → **GitHub** → Advanced → *Shared secrets* → pick
     it. Leave "Manage hooks" off (the token can't admin the repo).
   - GitHub (repo admin): Settings → Webhooks → Add webhook — Payload URL
     `https://mfp-jenkins-psu.malaysiawest.cloudapp.azure.com/github-webhook/` (trailing slash), Content type
     `application/json`, Secret = the same value, events **Pushes** +
     **Pull requests**, SSL verification on.
   - Check: Recent Deliveries shows `200`; pushing to a PR starts its
     build within seconds. Requests with a wrong/missing signature are
     rejected by Jenkins.
   The `Jenkinsfile` scopes stages: cheap scans on every discovered
   branch; full build/test/image/ZAP on PRs into `dev`/`main` and on
   `dev`/`main`; Docker Hub push on `main` only.
7. **Verify:** push to a PR branch → build starts within ~1 min → the PR
   shows the Jenkins status check → email arrives; JUnit, `Backend
   coverage`, `ZAP` reports and `sbom.cdx.json` present on the build.

**Disk (61 GB):** builds share one dependency cache at
`/var/lib/jenkins/ci-cache` (npm, pub, Trivy DB) and delete their
workspace when they finish; `jenkins-disk-cleanup.timer` (daily 04:00)
prunes Docker leftovers, workspaces untouched for 3 days and an oversized
cache. Every build starts with *Preflight · disk*, which fails below 5 GB
free. If it trips: `df -h`, `sudo systemctl start jenkins-disk-cleanup`,
`journalctl -u jenkins-disk-cleanup`.

**Running pieces outside Jenkins** (from repo root, needs Docker + bash):
build the image, then `CI_ID=local IMAGE=<image:tag> PG_IMAGE=postgres:16-alpine
REDIS_IMAGE=redis:7-alpine bash ci/scripts/stack-up.sh`, run smoke / ZAP
(`ZAP_IMAGE=zaproxy/zap-stable:2.17.0 bash ci/scripts/zap-scan.sh`), and
`CI_ID=local bash ci/scripts/stack-down.sh` to clean up.

## 7. Jenkins controller hardening (#288)

Decisions and routines for the Azure Jenkins (`mfp-jenkins`). What is
enforced by Ansible (`infra/ansible/jenkins-host.yml`) vs. set in the UI.

| Area | Decision | Where |
|---|---|---|
| Execution isolation | **Keep the built-in node, 1 executor** (4 GB VM, one build at a time). Every tool runs in a pinned Docker container (version + digest), never directly on the controller. Accepted risk: a PR build runs `npm`/`flutter` scripts with the host's Docker. Mitigated by the next two rows. | Jenkinsfile |
| Fork PRs | Multibranch source → *Discover pull requests from forks* → trust **Nobody** (or *users with Admin/Write permission*). Only team members' branches are built. | UI, per job |
| Credentials | Only two exist in the job: `dockerhub-token` (publish stage, `main` only) and `notify-email` (post step). Fork/PR code never reaches the publish stage. | Jenkinsfile |
| Access | Anonymous read off, sign-up off, team accounts only (checked by `jenkins-host.yml` before it exposes the UI). | UI + Ansible assert |
| Webhook | GitHub webhook signed with a shared secret (`github-webhook-secret`). | UI + GitHub |
| TLS | **Caddy** on 443 with a Let's Encrypt cert it obtains and renews itself; Jenkins itself only on `127.0.0.1:8080`. | Ansible |
| Network | NSG: 443 + 80 (ACME/redirect) open, 22 limited to `admin_cidrs`, 8080 never public. | `provision.yml` |
| Plugins | Minimal set. Pin it in git: run `infra/jenkins/export-plugins.sh` (needs an API token) and commit `infra/jenkins/plugins.txt`; reinstall with `jenkins-plugin-cli --latest=false -f plugins.txt`. | `infra/jenkins/` |
| Budget | Azure Cost Management budget is **alert-only**, not a cap; the VM (B2als_v2) stays on 24/7 for the webhook. | `provision.yml` |

**Backup (`jenkins-backup.timer`, daily 03:15):** `/var/backups/jenkins/jenkins-home-*.tar.gz`,
root-only, last 7 kept. Contains `credentials.xml` and `secrets/master.key`
(together they decrypt every credential) -- treat the archives as secrets
and copy them off the VM. Workspaces, build logs, caches, the war and
plugins are excluded (rebuildable).

```bash
sudo systemctl start jenkins-backup && sudo ls -lh /var/backups/jenkins   # backup now
```

**Restore drill** (do once, on a scratch VM or after a controller rebuild):

```bash
./run.sh ansible-playbook jenkins-host.yml                 # fresh Jenkins
ssh azureuser@<vm>
sudo systemctl stop jenkins
sudo tar xzf /var/backups/jenkins/jenkins-home-<stamp>.tar.gz -C /var/lib/jenkins
sudo chown -R jenkins:jenkins /var/lib/jenkins
sudo systemctl start jenkins
# reinstall plugins from infra/jenkins/plugins.txt, then log in with the
# restored accounts; credentials must show up and decrypt (run a build)
```

**Patch routine (monthly, first week):** Manage Jenkins → *Plugins* →
update; apply the new LTS (`sudo apt-get update && sudo apt-get install --only-upgrade jenkins`);
`sudo systemctl start jenkins-backup` first; run one PR build afterwards;
re-run `export-plugins.sh` and commit the new `plugins.txt`.
