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
