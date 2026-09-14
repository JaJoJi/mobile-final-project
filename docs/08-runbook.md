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
([#138](https://github.com/JaJoJi/mobile-final-project/issues/138) —
Prometheus + Grafana). Until then, first three things to check when
something's wrong:

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

Once #138 lands, step 2/3 become "open the Grafana dashboard" instead of
grepping `docker compose logs` by hand — update this section then.
