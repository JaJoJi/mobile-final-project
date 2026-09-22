# Operations Runbook

> Written from what's actually built today. Sections marked **Not yet implemented**
> describe the design other open issues will land — don't treat them as
> working procedure until that issue merges and this doc is updated to match.

Related: [`docs/03-architecture.md`](./03-architecture.md) (topology) ·
[`docker-compose.yml`](../docker-compose.yml) ·
[`docker-compose.prod.yml`](../docker-compose.prod.yml) ·
[`.env.example`](../.env.example) · [`ansible/deploy.yml`](../ansible/deploy.yml)

## Contacts

2-3 person course team. Ping in whatever channel the team already uses (no
dedicated on-call tooling — that's disproportionate for this project's size).

| Area | Owner |
|---|---|
| Backend / infra | `@JaJoJi`, `@fiat222` |
| Mobile | `@JaJoJi`, `@fiat222` |

## 1. Deploy

**Local / dev**, from a clone:

```bash
cp .env.example .env      # fill in real values for anything beyond local dev
docker compose up -d --build
curl http://localhost/health/ready
```

`nest-1` runs migrations on boot (`RUN_MIGRATIONS=true` in
`docker-compose.yml`); `nest-2`/`nest-3` don't, to avoid three instances
racing the same migration.

**Production** ([#221](https://github.com/JaJoJi/mobile-final-project/issues/221)):
Jenkins CD stage runs `ansible-playbook ansible/deploy.yml -e
image_tag=<short SHA>` — the playbook syncs `docker-compose.prod.yml` +
nginx/vault/postgres files to the host, brings up Vault, fetches secrets
from it into a runtime-only `.env.runtime` (never committed, rewritten
every deploy), then `docker compose -f docker-compose.prod.yml --env-file
.env.runtime up -d`. pgadmin is excluded from prod (dev-only DB admin UI,
too risky to expose — the open decision from #221 resolved this way).

**Post-deploy check**, Jenkins runs this after the playbook, fails the
stage if it doesn't pass within 30s:

```bash
curl -f http://<host>/health/ready || echo "DEPLOY BAD — do not consider this live"
```

**Verified for real** (not just written): brought up the entire
`docker-compose.prod.yml` topology locally — vault, postgres-primary +
replica, redis, nest-1/2/3 (from a locally-built image tagged like a real
Docker Hub release), nginx+ModSecurity — and got a real `200
{"status":"ready"}` from `/health/ready` through nginx. Along the way found
and fixed a real bug: `postgres-primary` never actually received
`POSTGRES_REPLICATION_PASSWORD` as an env var in either compose file (dev
or prod), so `postgres/init-primary.sh` had silently hardcoded the
`replicator` role's password instead — meaning any deploy where Vault held
a different replication password than the hardcoded literal would have
broken replication with no obvious cause. Fixed in both compose files and
verified `postgres-replica` reaches `healthy` with a password sourced from
the env var, not the old hardcoded fallback.

## 2. Rollback

Mechanism: same image, different tag — no separate rollback tooling, just
rerun the deploy with an older `IMAGE_TAG`.

1. Identify the last-known-good tag: `git log --oneline` for the short SHA
   of the last good `main` build (that's the Docker Hub tag — #220 tags
   with the short commit SHA, not semver).
2. Rerun the Jenkins Deploy stage (or `ansible-playbook ansible/deploy.yml
   -e image_tag=<previous-sha>` directly) — this pulls the previous image
   and recreates the affected containers, nothing else.
3. Re-run the post-deploy check above.
4. If the bad deploy already ran a migration, rolling the *image* back does
   **not** roll the schema back — `npm run migration:revert` must be run
   manually before down-stepping the image, or the old code will hit a
   schema it doesn't understand. There is currently no automated migration
   rollback gate; treat every migrating deploy as effectively one-way until
   one exists.

**Drilled for real, locally** (#221): deployed `IMAGE_TAG=drill1`, confirmed
healthy; "deployed" `IMAGE_TAG=drill2` (same image, different tag —
standing in for a new release), confirmed `ac-nest-1`'s running image
actually changed tag and stayed healthy; rolled back to `IMAGE_TAG=drill1`
the same way, confirmed the container recreated with the old tag again and
`/health/ready` stayed 200 throughout. Not drilled: an actual bad release
(this only proves the tag-switch mechanism, not failure detection) or
anything against a real remote host — no deploy target exists yet.

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

**Production** ([#223](https://github.com/JaJoJi/mobile-final-project/issues/223)
— Vault, dev server mode, not the `.env` flow above): secrets
(`secret/auto-chess/db`, `secret/auto-chess/redis`, `secret/auto-chess/jwt`)
live in Vault's KV v2 engine, seeded by `vault/seed.sh`.

- **Reseed after any Vault container restart** — dev-mode Vault is
  in-memory, a restart wipes it:
  ```bash
  docker compose -f docker-compose.prod.yml up -d vault
  VAULT_TOKEN=<root token from vault/root_token.env> \
  DB_PASSWORD=... REDIS_PASSWORD=... JWT_SECRET=... \
    ./vault/seed.sh
  ```
- **Rotate a secret**: `vault kv put secret/auto-chess/jwt secret="$(openssl rand -base64 32)"`,
  then roll the app containers so they pick it up. Same "every session
  invalidated" caveat as the dev flow above until #139's
  `JWT_SECRET`/`JWT_SECRET_OLD` dual-verify lands.
- Vault's own KV v2 keeps prior versions automatically (`vault kv get -version=N ...`),
  useful for a quick rollback, but doesn't by itself solve dual-serving
  two live secrets to already-running app instances.

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

Controller install + webhook + credentials aren't repo-tracked — done by
hand on the target VM, documented here so it's repeatable.

1. **Install Jenkins** on the target VM, running on the built-in node —
   no separate Docker agent (devops-toolchain.md §1). Standard LTS
   package for the host OS; no Docker-in-Docker needed since `docker`
   CLI is invoked directly on the built-in node against the host's
   Docker daemon.
2. **Plugins:** GitHub Integration (webhook trigger), HTML Publisher
   (backend coverage report), JUnit (already core in modern Jenkins).
3. **Webhook:** GitHub repo → Settings → Webhooks → add
   `http://<jenkins-host>/github-webhook/`, content type
   `application/json`, event: `push`. Matches the Jenkinsfile's
   `triggers { githubPush() }`.
4. **Job:** create a Multibranch Pipeline job pointing at this repo —
   Jenkins auto-discovers `Jenkinsfile` per branch/PR.
5. **Credentials** (Jenkins → Credentials) — added as each backing issue
   lands, not needed for #218 itself:
   - `dockerhub-token` (#220 — Docker Hub push, Kind: Username+password,
     username = Docker Hub username, password = a Docker Hub access
     token, not the account password). Image name is
     `jajoji/auto-chess-backend`, tagged with the short commit SHA plus
     `latest` on every push to `main` — same tag Push builds and Deploy
     (#221) pulls, no separate rebuild.
   - SSH key for the deploy target (#221 — Ansible/CD over SSH)
6. **Verify:** push a commit, confirm the webhook fires a build, confirm
   `Backend coverage` (HTML Publisher) and the JUnit tab both populate
   after `Backend · unit test + coverage`.
7. **Known current blocker for #220's Push stage:** its Trivy image-gate
   will fail on real HIGH/CRITICAL transitive CVEs already in the
   dependency tree (lodash/multer/tar/js-yaml, verified via `npm ls
   --omit=dev` and a real Trivy scan — `npm audit fix` cannot resolve
   them without bumping `@nestjs/swagger`/`@nestjs/platform-express`/
   `bcrypt`). That's the gate working as intended, not a setup mistake —
   resolving it is a separate dependency-upgrade task before `main` can
   actually push an image.
