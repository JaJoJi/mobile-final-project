# P3-DO-04 — Strong secrets, HTTPS, pgBouncer, backups (plan)

Issue: [#139](https://github.com/JaJoJi/mobile-final-project/issues/139) · Size **XL** · area:devops

> **This branch (`P3-DO-04`) is the plan only — no implementation.**
> Nothing here is "done". Do not tick the issue checklist.

---

## 1. Blocker map

| Workstream | Can start now (offline) | Blocked on |
|---|---|---|
| A. JWT secret + rotation | ✅ code + docs | — (deploy rollout needs #193) |
| B. pgBouncer | ✅ compose + `DATABASE_URL` rewire | — |
| C. Daily `pg_basebackup` | ✅ script + compose sidecar | off-box storage target |
| D. HTTPS at nginx | ⚠️ config + self-signed only | real domain + cert (**#193**) |
| E. Runbook (`docs/08-runbook.md`) | ✅ | — |

**Hard blocker:** [#193 — Deploy target + staging](https://github.com/JaJoJi/mobile-final-project/issues/193)
is OPEN and unassigned. "nginx serves HTTPS on 443 with a valid cert" and
"HTTP → HTTPS redirect verified" cannot be truly satisfied without a
domain + a place to run it. Everything else lands independently.

Recommended split: ship A + B + C + E now as `P3-DO-04a` (safe, no infra),
leave D (+ the cert automation) as `P3-DO-04b` riding on #193.

---

## 2. Workstream A — Strong `JWT_SECRET` + rotation

**Goal:** production secret is 32-byte random; a rotation can roll out
with zero forced logout by accepting the previous secret for a grace
window.

**Current state:**
- `backend/src/common/jwt-auth.module.ts` — `JwtModule` with a single
  `secret: process.env.JWT_SECRET`, HS256.
- Verify call sites: `auth/guards/jwt-access.guard.ts:42`,
  `auth/auth.service.ts:90` (refresh). Both `this.jwt.verify(token)`.

**Design decisions:**
- **Grace mechanism:** add `JWT_SECRET_OLD` (optional). On verify, try
  current secret; on `JsonWebTokenError` (bad signature) retry with
  `JWT_SECRET_OLD` if set. Signing always uses `JWT_SECRET`.
- **Where the fallback lives:** a small `TokenVerifierService` in
  `common/` wrapping `JwtService`, so the guard and `AuthService` share
  one implementation instead of duplicating the try/catch.
- **Grace length:** 7 days (≥ access-token TTL of 7d so no valid access
  token is orphaned; refresh tokens that outlive it force one re-login,
  acceptable).
- **Rotation cadence:** `JWT_SECRET` every 90 days; PG password every 180.
  Documented, not automated.

**Commits (small):**
1. `feat(auth): TokenVerifierService wrapping JwtService` — no behaviour
   change, both call sites routed through it, unit test for the happy path.
2. `feat(auth): accept JWT_SECRET_OLD during verify` — fallback + tests
   (valid-new, valid-old, invalid-both, old-unset).
3. `chore(config): document JWT_SECRET_OLD` — `.env.example` comment,
   `docker-compose.yml` passes `JWT_SECRET_OLD: ${JWT_SECRET_OLD:-}` to
   nest-1/2/3.
4. `docs(runbook): JWT secret rotation procedure` (see E).

**Files:** `backend/src/common/token-verifier.service.ts` (new),
`backend/src/common/jwt-auth.module.ts`, `backend/src/auth/guards/jwt-access.guard.ts`,
`backend/src/auth/auth.service.ts`, `backend/src/**/*.spec.ts`,
`.env.example`, `docker-compose.yml`.

**Acceptance mapping:**
- "Production `JWT_SECRET` is 32-byte random" → generation documented
  (`openssl rand -base64 32`); enforced at deploy, not in code.
- "Secret rotation documented" → runbook section (E).
- "All secrets from env vars, none hardcoded" → grep gate already added
  by P3-DO-07 (gitleaks); add a test asserting `jwt-auth.module` throws
  if `JWT_SECRET` is unset in `NODE_ENV=production`.

---

## 3. Workstream B — pgBouncer

**Goal:** Nest talks to Postgres through a transaction-pooled pgBouncer.

**Design decisions:**
- Image: `edoburu/pgbouncer` (env-configured, no config file to mount).
- Pool mode: `transaction` (TypeORM opens a connection per query batch;
  no session-level features like `LISTEN/NOTIFY` are used on the ORM
  path — Redis Pub/Sub carries those). `POOL_SIZE=20`,
  `MAX_CLIENT_CONN=1000`.
- **TypeORM + transaction pooling caveat:** disable prepared statements
  (`extra: { prepare: false }` / `?prepared_statements=false`) or set
  pgBouncer `server_reset_query`. Confirm the current `pg` driver
  version's behaviour before merge.
- Migrations (`RUN_MIGRATIONS=true` on nest-1) should point at
  **postgres-primary directly**, not pgBouncer — DDL + advisory locks
  want a stable session. Use a separate `MIGRATION_DATABASE_URL`.

**Commits:**
1. `feat(devops): add pgbouncer service to compose`.
2. `refactor(devops): route nest DATABASE_URL through pgbouncer:6432`,
   keep `MIGRATION_DATABASE_URL` → primary; update `data-source.ts` to
   read it with a fallback to `DATABASE_URL`.
3. `test(devops): smoke — 3 nest instances + pgbouncer under load` (reuse
   an existing smoke; assert no "too many clients" from PG).

**Files:** `docker-compose.yml`, `backend/src/data-source.ts`,
`backend/src/app.module.ts` (only if prepared-statements flag needed),
`.env.example`, `docs/observability.md` note.

**Acceptance:** "pgBouncer runs in front of Postgres, pool_size=20,
max_client_conn=1000" → compose env; verified by the load smoke.

---

## 4. Workstream C — Daily `pg_basebackup`

**Goal:** a daily physical backup of the primary, retained N days, with a
tested restore path.

**Design decisions:**
- **Mechanism:** a small `pg-backup` sidecar container (alpine + `postgres16`
  client) running `cron`, not a cron *inside* postgres-primary (keeps the
  DB image stock). It runs
  `pg_basebackup -h postgres-primary -U replicator -D /backups/$(date +%F) -Ft -z -Xs -P`.
- The `replicator` role + `pg_hba` entry already exist (used by
  postgres-replica) — reuse them, no new grants.
- **Storage:** local named volume `pg_backups` for now; **off-box is a
  follow-up** — parametrise the destination so an `aws s3 cp` / `rclone`
  step can be appended. This is the one item with an unresolved
  dependency (where do backups live in prod).
- **Retention:** keep 7 daily; prune older in the same script.
- **Restore drill:** documented monthly manual procedure in the runbook;
  not automated.

**Commits:**
1. `feat(devops): pg-backup sidecar — daily pg_basebackup + prune`
   (`docker/pg-backup/Dockerfile`, `docker/pg-backup/backup.sh`,
   `docker/pg-backup/crontab`, compose service + `pg_backups` volume).
2. `docs(runbook): backup contents, restore drill, RPO/RTO notes`.

**Files:** `docker/pg-backup/*` (new), `docker-compose.yml`,
`docs/08-runbook.md`.

**Acceptance:** "Daily `pg_basebackup` … to a separate volume (or S3)" →
sidecar + `pg_backups` volume; S3 left as a documented TODO with the hook
in place.

---

## 5. Workstream D — HTTPS at nginx  *(blocked on #193)*

**Goal:** 443 with a valid cert, 80 → 443 redirect, modern TLS only.

**Design decisions:**
- **Cert source:** Let's Encrypt via a `certbot` companion container
  (webroot or DNS-01), renew via its own cron; cert on a shared volume
  nginx reads. Alternative if the deploy target sits behind Cloudflare:
  origin cert + "Full (strict)" — decide with #193.
- **Config shape:** split `nginx.conf` into a redirect `server {}` on 80
  and the real `server {}` on 443 (`ssl_protocols TLSv1.2 TLSv1.3`,
  `ssl_ciphers HIGH:!aNULL:!MD5`, HSTS header). The existing CORS +
  `/socket.io/` + `/health` blocks move into the 443 server verbatim.
- **What is doable now, behind a flag:** land the 443 server block +
  a `make certs-selfsigned` helper that drops a self-signed pair into
  `nginx/certs/` (gitignored) so `docker compose up` works locally over
  https://localhost. Real ACME wiring is `P3-DO-04b`.

**Commits (04b):**
1. `feat(nginx): self-signed cert helper + 443 server block (dev)`.
2. `feat(devops): certbot companion + renewal cron` (needs domain).
3. `feat(nginx): HSTS + 80→443 redirect; drop plain-80 proxy`.

**Files:** `nginx/nginx.conf`, `nginx/Dockerfile`, `nginx/certs/.gitignore`,
`docker-compose.yml`, `Makefile`/`scripts/`, `docs/08-runbook.md`.

**Acceptance:** fully satisfiable only once #193 provides a domain + host.

---

## 6. Workstream E — Runbook (`docs/08-runbook.md`)

New sections:
- **Secret rotation** — JWT (`JWT_SECRET` + `JWT_SECRET_OLD` two-phase,
  rolling restart, 7-day window, then drop OLD), PG password, cadence
  table.
- **Backups** — what `pg_basebackup` captures, where it lands, retention,
  the monthly restore drill (spin a throwaway PG, `-Ft` extract, start,
  `SELECT count(*)` sanity), RPO ≈ 24 h / RTO target.
- **Cert renewal** — certbot cron, manual renew command, what breaks if
  it lapses (90-day expiry).
- **Incident response** — leaked secret → rotate now (skip grace),
  invalidate refresh tokens.

---

## 7. Sequencing

```
P3-DO-04a  (no infra dependency, ship first)
  A JWT rotation ─┐
  B pgBouncer  ───┼─► one PR into dev, each workstream its own commits
  C backups    ───┤
  E runbook    ───┘   (A/C/E runbook bits fold into E)

P3-DO-04b  (after #193)
  D HTTPS + certbot + redirect
  E cert-renewal runbook section
```

## 8. Open questions (need an answer before 04b)

1. Deploy target for #193 — single VM (Compose) or managed (k8s)? Changes
   how certs + pgBouncer + backup storage are wired.
2. Backup storage — is there an S3/GCS bucket, or object storage on the
   provider? Blocks the "off-box" half of C.
3. Is the app fronted by Cloudflare? If yes, D uses an origin cert, not
   certbot.
4. Refresh-token store — are refresh tokens stateless JWTs only, or is
   there a revocation list? Affects the "invalidate on leak" step in E.
