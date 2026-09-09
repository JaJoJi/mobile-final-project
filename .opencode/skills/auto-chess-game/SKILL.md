---
name: auto-chess-game
description: |
  Build and modify the Auto Chess university project — a 2-player auto-chess
  mobile game on Flutter + Nest.js + TypeORM + PostgreSQL + Redis. This skill
  covers backend (Nest, TypeORM, Socket.IO), mobile (Flutter, Riverpod), and
  the game's combat rules. Use this skill whenever working in this project on
  backend code, mobile code, or game engine logic.
---

# Auto Chess Project — AI Agent Skill

## 1. Project Context

- **Goal**: 2-player auto-chess mobile game (university project, 1-month MVP).
- **Stack**: Flutter (mobile) + Nest.js (backend) + TypeORM + PostgreSQL + Redis.
- **Authority**: All combat math runs on backend. Flutter is a thin client.
- **Players**: 3 people × 1 month.

## 2. Documentation Map (read before coding)

| Topic | File |
|---|---|
| Game rules, units, abilities, phases | `docs/01-game-design.md` |
| Functional + non-functional requirements | `docs/02-requirements.md` |
| Nest modules, TypeORM, PG, Redis | `docs/03-architecture.md` |
| REST + WS event contracts | `docs/04-api-contracts.md` |
| Combat rules, abilities, edge cases | `docs/05-combat-spec.md` |

Read these before any non-trivial change.

## 3. Folder Layout

> ✅ = implemented. ⏳ = planned per `docs/03-architecture.md` §16.

```
backend/src/
├── auth/                       ✅ implemented
│   ├── auth.module.ts
│   ├── auth.controller.ts       # POST /auth/{register,login,refresh}
│   ├── auth.service.ts          # bcrypt(10) + JWT(HS256) sign/verify
│   ├── guards/jwt-access.guard.ts
│   └── dto/{register,login,refresh,auth-response}.ts
│
├── user/                       ✅ implemented
│   ├── user.module.ts           # imports JwtAuthModule; exports UserService
│   ├── user.entity.ts           # @Entity('users') with @Index unique
│   ├── user.service.ts          # single repo owner for `users` table
│   ├── user.controller.ts       # GET/PATCH /user/me (JwtAccessGuard)
│   ├── dto/update-user.dto.ts
│   └── decorators/current-user.decorator.ts   # @CurrentUser() → req.user
│
├── common/                     ✅ implemented
│   ├── jwt-auth.module.ts       # shared JwtModule + JwtAccessGuard
│   │                            # (breaks AuthModule ⇄ UserModule cycle)
│   └── health.controller.ts     # GET /health, GET /health/whoami
│
├── migrations/                 ✅ implemented
│   └── 1736000000000-CreateUsers.ts
│
├── data-source.ts              ✅ implemented (TypeORM CLI for migration scripts)
│
├── redis/                      ✅ partial (RedisService + RedisModule only)
│   ├── redis.module.ts
│   └── redis.service.ts
│
├── shop/                       ⏳ planned — server-side shop offer generation
├── matchmaking/                ⏳ planned — Redis ZSET queue (FIFO)
├── game/                       ⏳ planned — ⚠ ALL combat logic (pure functions, ≥90% tested)
├── match/                      ⏳ planned — match lifecycle, persistence, BullMQ consumers
├── ws/                         ⏳ planned — WebSocket gateway (stateless; subscribes to Pub/Sub)
├── runtime/                    ⏳ planned — stateless orchestrator adapter
│   ├── match.runtime.adapter.ts
│   ├── combat.coordinator.ts
│   └── pubsub.bridge.ts
│
└── common/ continues with:
    ├── redis/scripts/*.lua      ⏳ planned — phase_flip, combat_lock, combat_done
    ├── filters/                  ⏳ planned — exception filters
    └── decorators/              ⏳ planned — shared decorators beyond current-user

mobile/lib/
├── core/                       ✅ implemented
│   ├── api/api_client.dart      # dio + Bearer-token interceptor + auth methods
│   ├── auth/auth_repository.dart # login/register/logout/refresh + secure storage
│   └── config/app_config.dart    # --dart-define API_BASE_URL/WS_BASE_URL
│
├── features/                   ✅ auth + health; ⏳ matchmaking/shop/match
│   ├── auth/
│   │   ├── login_screen.dart    # /login
│   │   └── register_screen.dart # /register
│   └── health/
│       └── health_screen.dart   # /home: GET /health, GET /user/me, Ping 12×, logout
│
└── main.dart                    ✅ auth-aware routes: /login, /register, /home
```

## 4. Hard Rules (do not violate)

1. **All combat math lives in `backend/src/game/`.** Flutter never implements damage, targeting, or ability logic. If a Flutter change touches combat behavior, redirect to backend.
2. **Combat functions are pure.** No I/O, no `Date.now`, no `Math.random`. Pass RNG explicitly via `state.rng` (seeded). Required for determinism + testing.
3. **WS event names use the `game:*` prefix.** See `docs/04-api-contracts.md`. Don't invent new events without updating the contracts doc in the same PR.
4. **REST DTOs are validated by `class-validator`.** WS payloads validated server-side too.
5. **TypeORM entities use `@Entity()` decorators.** `synchronize: false` in prod. Use migrations for schema changes.
6. **Flutter state managed via Riverpod.** No `setState` for game state. Use `StateNotifierProvider` or `StreamProvider`.
7. **All abilities follow the spec** in `docs/05-combat-spec.md`. If you change ability behavior, update the spec in the same commit.
8. **Shop RNG and tie-tick init RNG are seeded** so matches are replayable. RNG is injected, never imported from a global.
9. **Stateless backend**: no mutable state in Node heap between requests. Every WS message: read runtime from Redis → mutate via Lua script → publish via Pub/Sub if needed. Multiple NestJS instances may run side-by-side.
10. **Lua scripts are the only mutator of match runtime.** Use `redisService.eval(...)` with the SHA-loaded scripts in `src/redis/scripts/*.lua`. Never HSET runtime fields directly from a controller.
11. **JWT payload shape is fixed: `{ sub: <userId>, type: 'access' | 'refresh' }`.** Guards reject the wrong type (refresh token can't authenticate `/user/me`; access token can't be used to refresh). When you add new tokens, add a new type — don't reuse `access`/`refresh` for a different purpose.
12. **Long-lived refresh tokens, no rotation, no blacklist** (MVP). Logout = client deletes the tokens from `flutter_secure_storage`. Adding a blacklist is a post-MVP concern; flag it explicitly in `docs/02-requirements.md` if you change this.
13. **Only ONE Nest instance runs migrations on boot** (`RUN_MIGRATIONS=true` on `nest-1`, `false` elsewhere — see `docker-compose.yml`). Adding migrations via `npm run migration:run` against `data-source.ts` is the alternative path.
14. **Flutter Dio interceptor injects `Authorization: Bearer <accessToken>`** from `flutter_secure_storage` automatically on every non-`/auth/*` request. Don't manually attach tokens in screens.
15. **Auth ⇄ User circular dep is broken by `JwtAuthModule` in `common/`.** If you add a third module that needs JWT (e.g. `MatchModule` with WS guards), also import `JwtAuthModule` — never re-create the cycle.

## 5. Conventions

### Backend (TypeScript / NestJS)

- Decorator style for entities and controllers.
- ES modules.
- `class-validator` for DTOs.
- `pino` for logging.
- One module per top-level feature folder.
- Tests use Jest. Combat engine must have ≥ 90 % coverage.
- Path: `backend/src/<feature>/<file>.ts`. Tests next to code: `<file>.spec.ts`.

### Frontend (Dart / Flutter)

- Riverpod for state.
- GoRouter for navigation.
- `dio` for REST; `socket_io_client` for WS.
- Mirror backend DTOs in Dart — keep in sync.
- `flutter analyze` clean; `flutter test` for widget tests when useful.
- Mirror backend camelCase field names in Dart models.

### Naming

- DB columns: `snake_case`.
- TS variables: `camelCase`.
- WS events: `game:<area>:<action>`.
- File names: `kebab-case.ts` / `snake_case.dart`.

## 6. Common Tasks

### Add a new unit

1. Add to `docs/01-game-design.md` (stats, role, abilities).
2. Add to `docs/05-combat-spec.md` (targeting, ability pseudocode).
3. Add to shop pool in `backend/src/shop/shop.service.ts`.
4. Add ability handler in `backend/src/game/abilities.ts`.
5. Update unit catalog in `backend/src/game/types.ts`.
6. Write tests in `backend/src/game/abilities.spec.ts`.
7. Mirror Dart model in `mobile/lib/shared/models/unit.dart`.

### Add a new WS event

1. Add to `docs/04-api-contracts.md`.
2. Define payload type in `backend/src/ws/ws.dto.ts` (use class-validator).
3. Emit from `backend/src/ws/ws.gateway.ts` with `game:<area>:<action>` name.

### Add a new TypeORM entity (or change schema)

1. Create or edit `*.entity.ts` next to its module.
2. Register in module's `imports` (`TypeOrmModule.forFeature([Entity])`).
3. **Generate migration** (against the live primary):
   ```
   npm run migration:generate -- src/migrations/AddX
   ```
   TypeORM diffs the entity vs. the current DB and writes a file.
4. **Review** the generated SQL — `pgcrypto`, `gen_random_uuid()`, default values are usually correct, but always verify.
5. **Commit** the migration file.
6. Deploy: `nest-1` runs it on next boot (it's `RUN_MIGRATIONS=true`).
7. **Never** `synchronize: true` in any environment — bypasses migrations.

### Add a new REST endpoint

1. Add the DTO in `dto/<name>.dto.ts` with `class-validator` decorators.
2. Add the handler in `<feature>.controller.ts`:
   - Public routes: `@Get()` / `@Post()` etc.
   - Guarded: `@UseGuards(JwtAccessGuard)` at method or class level. Get the user id with `@CurrentUser() jwt`.
3. Add the service method in `<feature>.service.ts`. Business logic only — no I/O in the controller.
4. Update `docs/04-api-contracts.md` (request/response shapes + status codes).
5. Write a spec (`*.spec.ts`) for the service method.

### Add a new ability to an existing unit

1. Update `docs/05-combat-spec.md` first.
2. Add ability handler in `backend/src/game/abilities.ts`.
3. Update unit catalog in `backend/src/game/types.ts` if star-level enum changes.
4. Tests in `backend/src/game/abilities.spec.ts`.

### Add a new Flutter screen

1. `mobile/lib/features/<feature>/<name>_screen.dart` as `ConsumerStatefulWidget`.
2. Riverpod providers go in `mobile/lib/core/` (services) or `<feature>/application/` (UI state).
3. Add the route in `main.dart` and navigate via `Navigator.of(context).pushNamed(...)`.
4. For auth-guarded screens, follow the `HealthScreen` pattern: `apiClientProvider` injects the Bearer header automatically; on 401 the interceptor could be extended to trigger logout.

### Modify the Nest auth flow

1. JWT payload shape must remain `{ sub, type }` — change in `auth.service.ts`.
2. New JWT types (e.g., `password_reset`) → update `JwtAccessGuard` type check and add a parallel guard.
3. New endpoints → add to `auth.controller.ts`, update `docs/04-api-contracts.md`.
4. New Flutter screens → `features/auth/` + add to `AuthRepository`.

## 7. Forbidden Patterns

- Combat logic in Flutter (`mobile/lib/**`).
- `Math.random()` in `backend/src/game/**`.
- `synchronize: true` in production TypeORM config.
- Supabase / Prisma / Mongoose — stick to TypeORM.
- Mock RNG in tests for combat functions — use a deterministic seeded RNG passed in.
- Hardcoded URLs / secrets / JWT keys in code.
- `setState` for game state in Flutter (use Riverpod).
- Storing match runtime state in Node heap between WS messages — must go through Redis.
- Direct `HSET` on runtime keys outside of Lua scripts — bypasses the atomicity guarantee.
- Setting `RUN_MIGRATIONS=true` on more than one Nest service in compose.
- Re-introducing the Auth ⇄ User circular dep (use `JwtAuthModule`).
- Putting `auth/` or `user/` business logic in `app.module.ts` or any controller — use services.

## 8. Dev Commands

```bash
# Infra
docker compose up -d                  # start all 7 containers
docker compose down -v                # wipe + restart (loses Postgres data)
docker compose restart nginx          # NOT enough — see § 9 below

# Backend
cd backend
npm install
npm run start:dev          # local dev with ts-node
npm run build              # tsc → dist/
npm run start              # node dist/main.js (production)
npm run test               # jest
npm run test:cov           # coverage
npm run migration:generate # diff entity vs DB, write a new migration file
npm run migration:run      # apply pending migrations
npm run migration:revert   # rollback the most recent one

# Mobile
cd mobile
flutter pub get
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:80
flutter test
flutter analyze
```

## 9. When You're Unsure

If a task is ambiguous and involves combat, **always re-read `docs/05-combat-spec.md` first**. If still ambiguous, ask the user with specific options rather than guessing. Default to the simpler implementation that the spec already covers — don't invent.

## 10. Anti-Patterns to Avoid

- Don't put business logic in NestJS controllers. Use services.
- Don't share state between Riverpod providers via globals. Use constructor-style dependencies.
- Don't hardcode URLs or tokens. Use `core/config.dart` for Flutter, env vars for backend.
- Don't skip validation. Every public endpoint validates input.
- Don't add a "magic" behavior that isn't in the spec. Add it to the spec first.

## 11. Per-issue Workflow

The 3-person team works one issue per agent in lockstep. The agent drives
a tight loop: pick issue → plan → wait for `go` → implement → verify →
commit → PR → next. **Never skip steps; the "check for teammate" step
in particular catches a lot of duplicate work.**

### 11.1 Pre-flight — check teammate work FIRST

This is the #1 source of duplicate work. FiatThanapon shipped P0-BE-08,
P0-BE-09, and P0-FE-01 while the author was working on other tickets.
**Always** run these before starting:

```bash
# 1. Is the issue already done by a teammate?
git branch -a | grep -iE "P0-(BE|FE)-<NN>\b"
gh pr list --search "P0-BE-<NN> OR <NN>" --state all --json number,title,state,headRefName

# 2. Is the issue closed in GitHub but not on the project board?
gh issue view <NN> --json state,closedAt

# 3. Project board status (GraphQL — the project is ProjectsV2 on org JaJoJi)
gh api graphql -f query='{ node(id:"PVTI_lA..."){...} }' | grep name
```

If a teammate branch + PR exist with status MERGED, the work is done.
**Don't redo it.** Reset your local branch to `origin/<id>`, run any
smoke tests they wrote, and report back to the user. Move on to the
next open issue.

### 11.2 Plan mode

Plan mode is **read-only** (no edits, no shell execution). The user must
toggle it off before you can execute. The flow:

1. Read the issue (`gh issue view <NN>`).
2. Inspect the existing codebase to understand the current state
   (always grep, read, check imports — never assume).
3. Ask clarifying questions when there's a real ambiguity. Use the
   `question` tool with concrete options. Mark the recommended option
   with `(Recommended)` as the first entry.
4. Present a final execution plan: files to add/modify, verify steps,
   commit format, PR target.
5. **Stop and wait.** Do not execute. The user toggles off plan mode and
   says "go" to authorise.

### 11.3 Branch conventions

- **First issue of a session**: branch from `origin/dev` (or the most
  recent `origin/P0-(BE|FE)-NN` if the prior ticket is still open).
- **Chained subsequent issues**: each new ticket branches from the
  previous ticket's tip, not from `dev`. This keeps the linear history
  clean and means each PR can be diffed against its predecessor.
  Example: P0-FE-03 was branched off `origin/P0-BE-09` (the prior
  author's tip on dev), not off `origin/dev` directly.
- **Naming**: exactly `<issue-id>` (e.g. `P0-BE-07`). No suffix.
- **PR target**: always `dev`. Never merge to `main` from agent PRs —
  `main` is reserved for release tags.

### 11.4 Implementation discipline

| Layer | Smoke / test convention |
|---|---|
| **Backend (NestJS)** | Every PR ships a smoke (or unit spec) that exercises the change. Smokes live next to the code as `*.smoke.ts` and are run via `npm run smoke:<name>`. Verify by running inside the Docker network: `docker compose exec -T nest-1 node dist/<path>/<file>.smoke.js` |
| **Frontend (Flutter)** | Widget tests under `mobile/test/` using `flutter_test` + the `FakeWsTransport` from `mobile/test/core/ws/fake_ws_transport.dart`. The author can't run `flutter test` from WSL bash (CRLF scripts in `flutter/bin/` break); the user runs `flutter pub get && flutter analyze && flutter test` on their Windows host. CI (P3-DO-01) re-runs on the PR. |

### 11.5 Commit + PR conventions

**Commit message format** (see git log for canonical examples):

```
feat(be): P0-BE-NN Short imperative title

- Bullet 1 (what + why, not just what)
- Bullet 2 (file grouping when helpful)
- Bullet 3 (verification notes)

Refs #NNN
```

For frontend: `feat(fe):` prefix. For docs: `docs:`. The middle line is
the imperative present ("Add", "Fix", "Replace") and ≤ 50 chars.

**PR title format**: `<issue-id> — <Short description>`.

**PR body** (every PR — keep it meaty):
1. **Summary** — 1–3 sentences describing the change and why.
2. **Changes** — `### New` then `### Modified` lists of files.
3. **Out of scope (follow-ups)** — what was deliberately NOT done so
   reviewers don't ask. Link each item to its ticket.
4. **Acceptance checklist** — paste the issue's "Done when" with every
   box ticked off + brief evidence.
5. **Verification (live, this session)** — copy-paste of the actual
   `docker compose` boot log, smoke output, regression table. Don't
   summarise — show real output so the reviewer can spot anomalies.
6. **Notes** — anything unusual (e.g. "this PR folds in a fix for
   pre-existing bug X — happy to split if you'd rather").
7. **Refs #NNN** at the bottom.

### 11.6 Post-commit checks

```bash
git status                        # clean?
git log -1 --oneline               # right commit message?
git push -u origin <branch>        # does it push cleanly?
gh pr create --base dev --head <branch> --title "..." --body "..."
```

If `git push` is rejected with "remote contains work you do not have",
another agent pushed in parallel. Fetch their tip, rebase onto it, fix
any conflicts, then push. The pattern that bit P0-BE-08: teammate
already shipped their P0-BE-08 to a branch while we were still
implementing locally.

### 11.7 Project board card move

The PAT used by the agent (`gh auth status`) is a **fine-grained
personal access token** that lacks `project` scope. `updateProjectV2ItemFieldValue`
fails with `FORBIDDEN — Resource not accessible by personal access token`.

**Workaround**: tell the user to drag the card manually on
https://github.com/users/JaJoJi/projects/1. Card IDs are
`PVTI_lAHOCZxzvc4Biq5zzhhi...` (see graphql API).

The GitHub project bot sometimes auto-flips cards when the PR is
merged/closed — verify the column on the project board before manually
dragging, otherwise you'll re-flip an already-Done card back to Review.

### 11.8 Merge PRs to dev (batch)

When the user says "let's do all PRs to dev first":

1. `gh pr list --base dev --state open` — confirm which PRs are open.
2. Sort merges by dependency order (foundation tickets first; PRs that
   touch only independent code can go in any order).
3. For each: `gh pr merge <N> --merge --delete-branch=false`.
4. After each merge: `git fetch origin dev && git log --oneline
   origin/dev -1` to confirm the new tip.
5. After all merges: `git checkout dev && git pull origin dev` so the
   local checkout tracks.
6. Run cold-stack boot + every smoke for regression.

Use **`--merge` (merge commit)** to match the existing convention — the
merged PRs in dev history (`Merge pull request #X from ...`) are all
merge commits, not squash.

### 11.9 Known traps in this environment

| Trap | Mitigation |
|---|---|
| **Flutter SDK on WSL bash**: `flutter` is a Windows binary; bash scripts in `bin/flutter/` have CRLF line endings that break `sh -c`. | Tell the user to run `flutter pub get && flutter analyze && flutter test` on their Windows host. CI runs on PR. |
| **`dart analyze` from WSL**: package-resolution errors for everything outside `dart:*` because `.dart_tool/package_config.json` isn't built. | Use as a syntax + lint check only; real errors surface after `flutter pub get`. |
| **NestJS runtime image is `npm ci --omit=dev`**: smokes that import `socket.io-client` (a devDep) fail with `Cannot find module`. | Inside the container, `NODE_ENV=development npm install --include=dev socket.io-client@^4.8.3` before running the smoke. |
| **`pubspec.lock` drift from `flutter pub get`**: a fresh lockfile shows up as untracked diff. | `git checkout -- mobile/pubspec.lock` before staging — the lockfile drift is environment noise, not a real change. |
| **`pubspec.yaml` / `package.json` dep drift from `npm install <pkg>`**: same problem on backend. | Revert before staging. |
| **PAT scope**: fine-grained PAT started with no `contents:write` (push was 403). User granted it on the token. If push fails again with 403, ask user to check the token's repository permissions on github.com/settings/personal-access-tokens/active. |
| **Smokes from inside the container**: `localhost` in a container is the container, not the host. Use `HTTP_BASE=http://nest-1:3000` or `http://nginx:80`, not `http://localhost`. |
| **`io(...)` defaults to root namespace**: the `/game` namespace is **appended** to the URL — `io('http://host', ...)` connects to root, not `/game`. | Use `io(\`${HTTP_BASE}/game\`, ...)` to match the NestJS `@WebSocketGateway({ namespace: '/game' })`. |

### 11.10 Discovered follow-ups (open TODOs from prior tickets)

Track these so the next agent knows what's pending. Each one will
probably become its own issue.

- **P0-FE-03 / Lobby**:
  - Resume-match flow (hide Find match if user has an active match). Needs `GET /match/active` REST endpoint — `MatchRepository.findActiveByUserId` exists (P0-BE-07), just no HTTP route yet.
  - Disconnect cleanup: P0-BE-10's `OnGatewayDisconnect` removes the socket from dedup indexes but probably doesn't `ZREM` the user from `matchmaking:queue`. Survivable (worker pairs a phantom next tick; 60 s combat-done timeout fires; other player wins) but not great UX.
  - Auto-retry on Find match if WS drops mid-search — user is stuck on "Searching…" until they tap Cancel + Find match again.
  - ELO-based matchmaking — deliberately deferred per spec (display-only).

- **WS lifecycle fix** (folded into P0-FE-03 as the red-banner bug):
  - `_AutoChessAppState` now listens to `AuthGate` and calls
    `wsClient.connect()` on sign-in, `disconnect()` on sign-out. If
    you need to split the fix into its own PR for the project history,
    the diff is `mobile/lib/main.dart` (add the listener) plus
    `mobile/test/main_lifecycle_test.dart` (regression).

## 11. Top-of-mind Cheatsheet

### Combat (planned, in `docs/05-combat-spec.md`)

- Cycle = 100 ticks. Per unit: `cooldown = 100 - SPD`, `acts = floor(100 / cooldown)` per cycle.
- **Board is 3 rows × 3 cols per player (9 slots)**. Row 0 = front (closest to enemy), row 1 = middle, row 2 = back.
- Targeting: front-row first → middle-row → back-row, within same lane; fall back across lanes (col 0 → 1 → 2).
- Tank 2★ = **Prioritize** (not absolute). Falls back when Tank dead.
- Ranger 2★ = global lowest HP. Tank 2★ rule affects enemies of Tank; doesn't change targeting of Tank's allies.
- Ranger 1★ Pierce: only hits the adjacent row behind target (`row + 1`); does not skip rows.
- Healer heals own team's lowest HP (any lane). 1★ = slow. 2★ = heal two.
- All RNG seeds from `matchSeed`.
- Wipe damage: 5, 10, 15, 20, 25 (cap). Tie = 5 to both, no wipe counter advance.
- Battle ends after 30 cycles.
- **Engine = `runBattle(state): CombatEvent[]`** — pure sync function called once per battle. Network delivery and ack happen OUTSIDE the engine.
- Combat single-runner: `SET NX EX combat-lock:<matchId>` with TTL 30 s. Whoever wins runs `engine.runBattle()`. Others skip.
- Combat-done: server waits for BOTH clients' `game:match:combat_done` (HSET via Lua ack script) OR 60 s timeout (BullMQ delayed job).
- **3 Nest instances behind nginx `least_conn`.** No sticky sessions. Pub/Sub + Redis state absorb reconnects.

### Auth (implemented)

- JWT payload: `{ sub: <userId>, type: 'access' | 'refresh' }`. HS256.
- Access TTL: `JWT_ACCESS_TTL` env (default `7d`). Refresh TTL: `JWT_REFRESH_TTL` (default `30d`).
- Refresh is **long-lived** (no rotation, no blacklist). Both old and new refresh tokens work until expiry.
- bcrypt cost = 10. Username regex: `^[a-zA-Z0-9_]+$`, 3–20 chars. Email format validated by `@IsEmail`.
- `JwtAccessGuard` reads `Authorization: Bearer <jwt>`, attaches payload to `req.user`. `@CurrentUser()` decorator extracts it.
- PG `23505` (unique violation) → 409 with field name (`email` / `username`) parsed from error detail.
- **Single-instance migrations**: only `nest-1` has `RUN_MIGRATIONS=true`. Use `npm run migration:run` to apply later.
- nginx: `least_conn` for HTTP, `Upgrade`/`Connection` headers for WS. CORS preflight short-circuits at server level (`OPTIONS → 204`).
- Flutter Dio interceptor reads `access_token` from `flutter_secure_storage` and injects `Authorization` header on every non-`/auth/*` request.
