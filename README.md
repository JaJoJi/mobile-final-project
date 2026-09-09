# Auto Chess Mobile — University Project

2-player auto-chess mobile game. Flutter client + Nest.js backend + PostgreSQL + Redis. **Stateless backend with horizontal scaling** behind an nginx load balancer, primary + read-replica Postgres, BullMQ-delayed jobs, and an authoritative-server combat engine.

> **Status**: Connectivity ✅ · Auth + User ✅ · WebSocket / Matchmaking / Combat / Shop / Match lifecycle ⏳. See [`docs/06-backlog.md`](./docs/06-backlog.md) for the 28-issue backlog and [GitHub Project #3](https://github.com/users/JaJoJi/projects/3) for the board.

---

## 1. Architecture at a glance

```
                        ┌─────────────┐
                        │    nginx    │      ← port 80 (HTTP for now)
                        │  least_conn │      ← least-connection across the 3 Nest instances
                        │ + CORS      │      ← CORS headers for Flutter web / mobile
                        └──┬─────┬────┬┘
                           │     │    │
                       ┌───▼┐ ┌─▼──┐ ┌▼───┐
                       │n1 │ │ n2 │ │ n3 │   3 NestJS instances (stateless)
                       └─┬─┘ └─┬─┘ └─┬─┘
                         └─────┼─────┘
                               │
                  ┌────────────┼─────────────┐
                  │                         │
                  │      ┌────────┐  ┌───────▼────────┐
                  │      │ redis  │  │  postgres-    │ ←─── primary (writes)
                  │      │ 7      │  │  primary      │       bitnami/postgresql-compatible
                  │      └────────┘  │  (16-alpine)  │
                  │                  └───────┬───────┘
                  │                          │ WAL streaming
                  │                  ┌───────▼───────┐
                  │                  │  postgres-    │  ←── replica (read-only, HA)
                  │                  │  replica      │
                  │                  └───────────────┘
                  │
                  └─ BullMQ delayed jobs (matchmaking, timers, cleanup)
```

**7 containers in `docker-compose.yml`**:
1. `postgres-primary` — Postgres 16, holds `auto_chess` DB
2. `postgres-replica` — async hot-standby, streams WAL from primary
3. `redis` — matchmaking queue, runtime state, pub/sub
4. `nest-1`, `nest-2`, `nest-3` — stateless NestJS instances
5. `nginx` — reverse proxy with `least_conn` + CORS
6. `pgadmin` — DB admin UI on port 5050

---

## 2. Prerequisites

| Tool | Required for | Where |
|---|---|---|
| **Docker Desktop** with WSL2 backend | the whole backend stack | <https://docs.docker.com/desktop/install/windows-install/> |
| **Git** | cloning the repo | any |
| **Flutter SDK** (≥ 3.10) | running the client | <https://docs.flutter.dev/get-started/install/windows/mobile> |
| **Android Studio + AVD** | Android emulator (optional) | <https://developer.android.com/studio> |
| **Physical Android device + USB cable** | real-device testing (optional) | enable USB debugging on device |

WSL2 users: ensure Docker Desktop's WSL integration is enabled in Docker Desktop → Settings → Resources → WSL Integration.

---

## 3. First-time setup

```powershell
# Clone (skip if you already have the repo)
git clone <your-repo-url> mobile-final-project
cd mobile-final-project

# Configure secrets
# .env is gitignored. Copy .env.example to .env and edit if you want to change defaults.
copy .env.example .env
```

Default `.env` has dev-friendly secrets:

```
POSTGRES_USER=postgres
POSTGRES_PASSWORD=postgres
POSTGRES_DB=auto_chess
POSTGRES_REPLICATION_PASSWORD=replicator_secret
PGADMIN_EMAIL=admin@local.dev
PGADMIN_PASSWORD=admin
PGADMIN_PORT=5050
JWT_SECRET=dev_jwt_secret_change_me_32_random_bytes_xxxxxxxxxxx
JWT_ACCESS_TTL=7d
JWT_REFRESH_TTL=30d
REDIS_URL=redis://redis:6379
NEST_PORT=3000
```

> **Production note**: change `JWT_SECRET` to a random 32-byte value, swap `POSTGRES_PASSWORD`, etc.

---

## 4. Run the stack

```powershell
cd D:\work\mobile-final-project

# Build images and start all 7 containers in the background
docker compose up -d --build
```

What happens, in order:

1. Pulls `postgres:16-alpine`, `redis:7-alpine`, `dpage/pgadmin4:latest`, `nginx:1.27-alpine`.
2. Builds 3 Nest images (`auto_chess-nest-1/2/3`) and the nginx image (binds `./nginx/nginx.conf`).
3. Starts **postgres-primary** → runs `postgres/init-primary.sh` on first init (creates `replicator` role + appends HBA rule).
4. Starts **postgres-replica** → waits for primary, takes base backup via `pg_basebackup`, runs as hot standby.
5. Starts **redis**, **pgadmin**.
6. Starts **nest-1/2/3** in parallel — each connects to primary + redis, exposes `/health` and `/health/whoami`.
7. Starts **nginx** on port 80.

First build takes ~3–5 min (Nest image builds: `npm install` × 3 in parallel). Subsequent starts are ~30 s.

---

## 5. Smoke tests

### 5.1 Connectivity (6 gates) — `docker compose up -d --build` finishes

```powershell
# GATE 1: all 7 containers healthy
docker compose ps
# Expected: 7/7 with STATUS = "Up (healthy)" or "Up"

# GATE 2: backend reachable through nginx
curl http://localhost/health
# Expected: {"status":"ok","postgres":"up","redis":"up","instance":"nest-1",...}

# GATE 3: Nest instance identity + pid + uptime
curl http://localhost/health/whoami
# Expected: {"instance":"nest-1","pid":1,"uptime":...,"timestamp":...}

# GATE 4: nginx least_conn distribution (12 sequential requests with Connection: close)
1..12 | ForEach-Object {
    (curl -s -H "Connection: close" http://localhost/health/whoami) -replace '"','' -split ',' |
    Where-Object { $_ -like '*instance*' }
} | Group-Object | Select-Object Count, Name
# Expected: nest-1, nest-2, nest-3 each appearing multiple times

# GATE 5: postgres-replica streaming WAL from primary
docker compose logs --tail=10 postgres-replica | Select-String "started streaming WAL"
# Expected: "started streaming WAL from primary at ..."

# GATE 6: pgadmin reachable on port 5050
curl -i -s http://localhost:5050/ -m 5 | Select-String "HTTP"
# Expected: HTTP/1.1 302 Found (redirect to /login)
```

### 5.2 Auth + User — full lifecycle (8 steps)

```powershell
# STEP 1: register
$R = (curl -s -X POST http://localhost/auth/register `
   -H 'Content-Type: application/json' `
   -d '{"email":"alice@example.com","username":"alice","password":"password123"}' | ConvertFrom-Json)
$TOKEN = $R.accessToken
$REFRESH = $R.refreshToken

# STEP 2: GET /user/me with access token
curl -s http://localhost/user/me -H "Authorization: Bearer $TOKEN"
# Expected: {"id":"...","email":"alice@example.com","username":"alice","rating":1000}

# STEP 3: 401 without token
curl -s http://localhost/user/me -w "`nHTTP %{http_code}`"
# Expected: HTTP 401

# STEP 4: 401 with refresh token (wrong type)
curl -s http://localhost/user/me -H "Authorization: Bearer $REFRESH" -w "`nHTTP %{http_code}`"
# Expected: HTTP 401 "access token required (got refresh?)"

# STEP 5: refresh
$R2 = (curl -s -X POST http://localhost/auth/refresh `
   -H 'Content-Type: application/json' `
   -d "{\"refreshToken\":\"$REFRESH\"}" | ConvertFrom-Json)
# Expected: new {userId, accessToken, refreshToken}

# STEP 6: new access token works
curl -s http://localhost/user/me -H "Authorization: Bearer $($R2.accessToken)"
# Expected: 200 with alice's data

# STEP 7: long-lived refresh (old token still valid)
curl -s -X POST http://localhost/auth/refresh `
   -H 'Content-Type: application/json' `
   -d "{\"refreshToken\":\"$REFRESH\"}" -w "`nHTTP %{http_code}`"
# Expected: HTTP 200 (long-lived refresh)

# STEP 8: rename
curl -s -X PATCH http://localhost/user/me `
   -H "Authorization: Bearer $TOKEN" `
   -H 'Content-Type: application/json' `
   -d '{"username":"alice2"}'
# Expected: 200 with username:alice2
```

If any step fails, see [§7 Troubleshooting](#7-troubleshooting).

### 5.3 pgadmin — connect (6 steps)

Browser → <http://localhost:5050> → login `admin@local.dev` / `admin` → right-click **Servers** → **Register** → **Server**:
- General → Name: `postgres-primary`
- Connection → Host: **`postgres-primary`** (Docker DNS, **not** localhost) · Port: `5432` · Maintenance DB: `auto_chess` · Username: `postgres` · Password: `postgres`

Repeat for `postgres-replica` (read-only). Browse `Databases → auto_chess → Schemas → public → Tables → users` to see registered rows.

---

## 6. Run the Flutter client

### 6a. One-time setup (Windows host, where Flutter SDK lives)

```powershell
cd D:\work\mobile-final-project\mobile
flutter pub get
flutter config --enable-web       # only needed once, to enable Chrome target
flutter doctor                    # verify Android toolchain (✓) for emulator/device
```

### 6b. Pick a target and run

```powershell
# Chrome (web) — easiest for dev, no device needed
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:80

# Android emulator — uses 10.0.2.2 as the magic host IP
flutter run -d emulator-5554 --dart-define=API_BASE_URL=http://10.0.2.2:80

# Physical Android device (USB or wireless debug)
# Find host LAN IP first:
ipconfig    # look for IPv4 Address, e.g. 192.168.1.42
flutter run -d <device-id> --dart-define=API_BASE_URL=http://192.168.1.42:80
```

> iOS Simulator is not an option on Windows (macOS-only).

### 6c. The HealthScreen

The app opens to `HealthScreen` with two buttons:

| Button | What it does | Expected |
|---|---|---|
| **GET /health** | One request through nginx | JSON block: `status: ok`, `postgres: up`, `redis: up`, `instance: nest-1` |
| **Ping 12 times** | 12 concurrent `/whoami` calls with `Connection: close` | Distribution chart: bars for `nest-1`, `nest-2`, `nest-3`; green check if 2+ distinct |

Press `r` in the Flutter terminal to hot-reload UI changes. Press `q` to quit.

---

## 7. Troubleshooting

> For deploy, rollback, backup/restore, secret rotation, and incident
> response, see [`docs/08-runbook.md`](./docs/08-runbook.md).

### `docker compose ps` shows containers restarting or unhealthy

```powershell
docker compose logs <service-name>      # check what's wrong
docker compose logs <service-name> --tail=50
```

Common cases:

- **postgres-replica** in restart loop: usually means `pg_hba.conf` doesn't allow replication from non-localhost. Check `postgres/init-primary.sh` ran on first init (logs should show `[primary] init done`).
- **nginx** unhealthy: probably bad config syntax. Run `docker compose exec nginx nginx -t` to verify.

### `curl http://localhost/health` times out

- **Docker Desktop not running**: open Docker Desktop, wait for it to be ready.
- **Wrong port**: `localhost:80` (nginx) not `localhost:3000` (Nest). The Nest ports are internal-only by design.

### Chrome shows "Connection refused" or CORS errors

- Stack must be running: `docker compose ps` should show all 7 healthy.
- Curl from the same shell first: `curl http://localhost/health/whoami` should return JSON.
- If curl works but Flutter doesn't, open Chrome DevTools (F12) → Network tab → check the exact error.

### Chrome connects but only one instance answers the ping

The Flutter app sets `Connection: close` on every request. If you see only `nest-1` for all 12 pings, something is keeping the connection open. Check `mobile/lib/core/api/api_client.dart` has `headers: {'Connection': 'close'}` in `BaseOptions`.

### `nginx -t` reports config error after editing `nginx.conf`

The config must be valid nginx syntax. Common mistakes:

- Missing semicolons.
- `if` inside `location` blocks (nginx's "if is evil" — put at server level).
- `proxy_pass` URL must end in `/` or the upstream name with no trailing slash. We use `proxy_pass http://backend;` (no trailing path manipulation).

If you edit `nginx.conf`, you must recreate the container (not just restart):

```powershell
docker compose down nginx
docker compose up -d nginx
```

The bind-mount in `docker-compose.yml` ensures the new file is picked up.

### Postgres data persists across restarts (good)

To wipe everything and start fresh:

```powershell
docker compose down -v       # -v removes named volumes
docker compose up -d --build
```

### Nest image rebuild after editing `backend/`

```powershell
docker compose up -d --build nest-1 nest-2 nest-3
```

The 3 builds happen in parallel.

---

## 8. Useful commands

| Goal | Command |
|---|---|
| View all container logs | `docker compose logs -f` |
| View one service's logs | `docker compose logs -f nest-1` |
| Restart one service | `docker compose restart nest-1` |
| Stop the whole stack | `docker compose down` |
| Wipe data + restart | `docker compose down -v && docker compose up -d --build` |
| Open psql to primary | `docker compose exec postgres-primary psql -U postgres -d auto_chess` |
| Open psql to replica (read-only) | `docker compose exec postgres-replica psql -U postgres -d auto_chess` |
| Inspect Redis | `docker compose exec redis redis-cli` |
| Validate nginx config | `docker compose exec nginx nginx -t` |
| Tail one Nest's logs | `docker compose logs --tail=50 nest-2` |
| Hot reload Flutter | press `r` in the Flutter terminal |
| Stop Flutter run | press `q` |

---

## 9. Project layout

```
mobile-final-project/
├── README.md                       ← you are here
├── .env                            ← gitignored, dev secrets
├── .env.example                    ← template, committed
├── .gitignore
├── docker-compose.yml              ← 7-service stack + RUN_MIGRATIONS gate
│
├── backend/                        ← Nest.js app
│   ├── Dockerfile                  ← multi-stage prod build
│   ├── .dockerignore
│   ├── package.json
│   ├── tsconfig.json / tsconfig.build.json
│   └── src/
│       ├── main.ts                 ← bootstrap, env, validation pipe
│       ├── app.module.ts           ← TypeORM (auto-migrations) + Redis + User + Auth
│       ├── data-source.ts          ← TypeORM CLI DataSource (migration scripts)
│       ├── auth/                   ✅ implemented
│       │   ├── auth.module.ts
│       │   ├── auth.controller.ts  # POST /auth/{register,login,refresh}
│       │   ├── auth.service.ts     # bcrypt(10) + JWT(HS256)
│       │   ├── guards/jwt-access.guard.ts
│       │   └── dto/{register,login,refresh,auth-response}.ts
│       ├── user/                   ✅ implemented
│       │   ├── user.module.ts
│       │   ├── user.entity.ts      # @Entity('users') with @Index unique
│       │   ├── user.service.ts     # single repo owner
│       │   ├── user.controller.ts  # GET/PATCH /user/me
│       │   ├── dto/update-user.dto.ts
│       │   └── decorators/current-user.decorator.ts
│       ├── common/                 ✅ implemented
│       │   ├── jwt-auth.module.ts  # shared JwtModule + JwtAccessGuard
│       │   └── health.controller.ts # GET /health, GET /health/whoami
│       ├── migrations/             ✅ implemented
│       │   └── 1736000000000-CreateUsers.ts
│       └── redis/                  ✅ implemented
│           ├── redis.module.ts
│           └── redis.service.ts
│
├── nginx/
│   ├── Dockerfile                  ← alpine + bind-mounted config
│   └── nginx.conf                  ← least_conn, CORS, WS upgrade; bind-mounted at runtime
│
├── postgres/
│   └── init-primary.sh             ← first-init only: replicator role + HBA rule
│
├── mobile/                         ← Flutter app
│   ├── pubspec.yaml                ← riverpod, dio, socket_io_client, secure storage
│   ├── analysis_options.yaml
│   └── lib/
│       ├── main.dart               ← auth-aware routes: /login, /register, /home
│       ├── core/                   ✅ implemented
│       │   ├── api/api_client.dart # dio + Bearer-token interceptor + auth methods
│       │   ├── auth/auth_repository.dart # login/register/logout/refresh + secure storage
│       │   └── config/app_config.dart
│       └── features/
│           ├── auth/               ✅ implemented
│           │   ├── login_screen.dart
│           │   └── register_screen.dart
│           └── health/             ✅ implemented (smoke-test screen + user card + logout)
│               └── health_screen.dart
│
├── docs/                           ← design + architecture docs
│   ├── 01-game-design.md           ← units, abilities, phases, win
│   ├── 02-requirements.md          ← FR + NFR + user stories
│   ├── 03-architecture.md          ← Nest modules, TypeORM, Redis, Flutter, multi-instance
│   ├── 04-api-contracts.md         ← REST + WS event schemas (✅ auth/user marked)
│   ├── 05-combat-spec.md           ← combat algorithm, targeting, abilities
│   ├── 06-backlog.md               ← 36-issue backlog index
│   ├── 07-design-spec.md           ← UX/UI spec: screens, tokens, components, motion (P0-FE-00)
│   └── 07-design-kit.html          ← visual reference — open in a browser, no build step
│
└── .opencode/skills/auto-chess-game/
    └── SKILL.md                    ← AI agent conventions (updated for auth + user)
```

---

## 10. Game rules snapshot

- **Board**: 3 rows × 3 cols per player (9 slots), mirror layout.
- **Units**: Fighter (1g), Healer (1g), Ranger (2g), Tank (2g).
- **Star upgrades**: 2× 0★ → 1★, 2× 1★ → 2★.
- **Phase per round**: 40 s merged shop + place → battle (≤ 30 cycles of 100 ticks) → damage.
- **Win**: opponent HP = 0, or opponent disconnects.
- **Wipe damage**: 5 → 10 → 15 → 20 → 25 (capped).
- **Combat model**: cycle-based ticks; unit cooldown = `100 − SPD`; actions/cycle = `floor(100/cooldown)`.

Full combat algorithm: [`docs/05-combat-spec.md`](./docs/05-combat-spec.md).

---

## 11. Roadmap

The full backlog lives in:
- [`docs/06-backlog.md`](./docs/06-backlog.md) — summary index
- [GitHub Issues](https://github.com/JaJoJi/mobile-final-project/issues) — canonical source of truth for every ticket
- [GitHub Project #3](https://github.com/users/JaJoJi/projects/3) — board with 4 columns (Backlog / In Progress / Review / Done)

**Done** ✅
- 7-service docker-compose stack (nginx, 3× Nest, postgres-primary, postgres-replica, redis, pgadmin)
- nginx with `least_conn` + CORS + WS upgrade + bind-mounted config
- Postgres primary + async replica (streaming replication working)
- NestJS multi-instance (3× stateless) with shared Redis
- Flutter app with auth UI (LoginScreen, RegisterScreen) + smoke-test home screen
- **TypeORM migrations** — `users` table auto-created on `nest-1` boot
- **Auth module** — POST `/auth/{register,login,refresh}` + JWT (HS256, 7d access / 30d long-lived refresh) + bcrypt(10) + class-validator DTOs
- **User module** — GET/PATCH `/user/me` guarded by `JwtAccessGuard`
- **Flutter auth flow** — LoginScreen / RegisterScreen / secure token storage / Dio Bearer interceptor / logout
- 6 connectivity gates + 8 auth lifecycle steps passing
- **GitHub Project #3** — 12 labels created, **36 backlog issues** open (14 P0 backend setup + 6 P0 backend logic + 7 P0 frontend + 4 P1 + 11 P3), 20 issues closed (14 out-of-MVP P2 + 6 old logic superseded)
- **UX/UI design spec** ([#106 / P0-FE-00](https://github.com/JaJoJi/mobile-final-project/issues/106)) — `docs/07-design-spec.md`: 7 screens × 4 states, light/dark tokens, 10 components, motion timings, per-PR checklist

**Next** (Phase 0 → Phase 1 → Frontend — see [`docs/06-backlog.md`](./docs/06-backlog.md) for full detail)

*Phase 0 — Backend setup (½–1 day each, do first):*
1. Redis + Lua loader (P0-BE-01) → TypeORM (P0-BE-02) → BullMQ (P0-BE-03) → WS gateway (P0-BE-04) → Pub/Sub bridge (P0-BE-05)
2. Lua scripts (P0-BE-06) → Match entities + migration (P0-BE-07) → WS DTOs (P0-BE-08)

*Phase 1 — Backend logic (after Phase 0):*
3. Combat engine (P0-BE-09) → WS handlers (P0-BE-10) → Matchmaking (P0-BE-11) → Match service (P0-BE-12) → Round orchestrator (P0-BE-13) → Shop (P0-BE-14)

*Frontend (can start in parallel with backend):*
4. ~~Design spec (P0-FE-00)~~ ✅ → WS client + DTOs (P0-FE-01) → Auth hardening (P0-FE-02) → Shared widgets (P0-FE-06)
5. Lobby (P0-FE-03) → Match (P0-FE-04) → Battle animation (P0-FE-05)

> **Board geometry**: 3 rows × 3 cols per player (9 board slots each) + 8 bench. See [`docs/01-game-design.md §2`](./docs/01-game-design.md).

See [`docs/01-game-design.md`](./docs/01-game-design.md) through [`docs/05-combat-spec.md`](./docs/05-combat-spec.md) for the full locked design.

---

## 12. Design system — read before touching UI

**Every UI ticket starts at [`docs/07-design-spec.md`](./docs/07-design-spec.md)** (deliverable of issue [#106 / P0-FE-00](https://github.com/JaJoJi/mobile-final-project/issues/106)). It is the single source of truth for how the app looks and behaves, written for both humans and AI agents. Download [`docs/07-design-kit.html`](./docs/07-design-kit.html) and open it in a browser for a visual walkthrough of the same tokens and screens — no build step, single file.

| You are about to… | Read |
|---|---|
| build or change a screen | §4 — wireframe, component tree, and the four states (loading / empty / error / success) for that route |
| pick a colour, font size, spacing, radius or animation duration | §2 — tokens. Never invent a value |
| build a reusable widget | §3 — `Button`, `Card`, `TextField`, `HealthBar`, `UnitAvatar`, `PhaseTimerRing`, `Toast`, `Modal`, `TabBar`, state views |
| wire a WS action or the phase timer | §5 — optimistic updates + rollback, deadline-based countdown, combat replay |
| write user-facing text | §7 — the Thai copy table (keyed to the error codes in `04-api-contracts.md` §5) |
| open a PR | §9.2 — the per-PR checklist |

Hard rules the reviewer will check: no `Colors.*` / `Color(0x…)` / `fontSize:` / off-scale padding / raw `Duration` under `mobile/lib/features/**`; every network screen implements all four states; tap targets ≥ 48 dp; nothing communicated by colour alone; the phase countdown is derived from a deadline, never `Timer.periodic`; combat outcomes are never predicted client-side.

---

## 13. AI agent assistance

The `.opencode/skills/auto-chess-game/SKILL.md` file encodes project conventions, folder layout, hard rules, and the combat cheat sheet. OpenCode/Claude reads it automatically when working in this repo — no manual context needed.

Doc-update rules (the docs are the source of truth):
- change ability behavior → update `docs/05-combat-spec.md` in the same commit
- change WS event names or payloads → update `docs/04-api-contracts.md`
- change a screen layout, token, component variant, or user-facing copy → update `docs/07-design-spec.md`
