# Architecture

## 1. Stack Overview

| Layer | Tech |
|---|---|
| Mobile | Flutter (Dart), Riverpod, Socket.IO client, `dio` (REST), `flutter_secure_storage` (token storage) |
| Backend | Nest.js (TypeScript), TypeORM, PostgreSQL 16, Redis 7, Socket.IO via `@nestjs/platform-socket.io` |
| Infra | Docker Compose for local dev (postgres + redis) |
| Auth | JWT (access + refresh), bcrypt for password hashing |

## 2. Backend — Nest Modules

> Tree reflects **actual files on disk**. Implemented: `auth/`, `user/`, `common/`, `migrations/`, `data-source.ts`. Not yet: `matchmaking/`, `game/`, `match/`, `ws/`, `runtime/`, `queue/` (still planned per §16).

```
backend/src/
├── auth/                # ✅ implemented
│   ├── auth.module.ts
│   ├── auth.controller.ts        # POST /auth/{register,login,refresh}
│   ├── auth.service.ts           # bcrypt + JWT sign/verify
│   ├── guards/
│   │   └── jwt-access.guard.ts   # @UseGuards(JwtAccessGuard) on REST routes
│   └── dto/
│       ├── register.dto.ts       # class-validator: email/username/password
│       ├── login.dto.ts
│       ├── refresh.dto.ts        # @IsJWT
│       └── auth-response.ts      # { userId, accessToken, refreshToken }
│
├── user/                # ✅ implemented
│   ├── user.module.ts            # imports JwtAuthModule, exports UserService
│   ├── user.entity.ts            # @Entity('users') with @Index unique
│   ├── user.service.ts           # single repo owner for `users`
│   ├── user.controller.ts        # GET /user/me, PATCH /user/me (JwtAccessGuard)
│   ├── dto/update-user.dto.ts
│   └── decorators/
│       └── current-user.decorator.ts   # @CurrentUser() — extracts JWT payload
│
├── common/              # ✅ implemented
│   ├── jwt-auth.module.ts        # shared JwtModule + JwtAccessGuard;
│   │                             # breaks AuthModule ⇄ UserModule cycle
│   └── health.controller.ts      # GET /health, /health/whoami (no auth)
│
├── migrations/          # ✅ implemented
│   └── 1736000000000-CreateUsers.ts   # hand-written; auto-runs on nest-1 only
│
├── data-source.ts       # ✅ implemented (TypeORM CLI DataSource for migration scripts)
│
├── shop/                # ⏳ planned — server-side shop offer generation
├── matchmaking/         # ⏳ planned — Redis ZSET queue
├── game/                # ⏳ planned — ⚠ ALL combat logic (pure)
├── match/               # ⏳ planned — match lifecycle, persistence
├── ws/                  # ⏳ planned — WebSocket gateway
├── redis/               # ✅ partially — client + Lua scripts (planned)
├── runtime/             # ✅ stateless round orchestrator + combat coordinator
└── queue/               # ⏳ planned — BullMQ workers

backend/src/app.module.ts          ← wires TypeORM (auto-migrations RUN_MIGRATIONS-gated),
                                     RedisModule, UserModule, AuthModule, HealthController
backend/src/redis/                  ← already exists (RedisService); Lua scripts go here later
backend/src/redis/redis.service.ts
```

### 2.1 Why `game/` will be isolated

When `game/` lands, all combat math lives there as **pure functions**:

- No I/O (no DB, no Redis, no WS).
- No `Date.now()`, no `Math.random()` — RNG is **injected** as a parameter (or passed via `state.rng`).
- Easy to unit-test.
- Easy to keep deterministic.
- Easy to evolve combat without touching HTTP / WS layers.

**Flutter never implements combat logic.**

### 2.2 Nest module conventions

Each feature folder has:

- `*.controller.ts` — REST routes.
- `*.service.ts` — business logic.
- `*.entity.ts` — TypeORM entity.
- `dto/` — request/response DTOs with `class-validator`.
- `*.module.ts` — wires controller + service + entity.
- `*.spec.ts` — unit tests next to the file they test.

### 2.3 Auth module circular-dep pattern (locked)

`AuthModule` needs `UserService` (to register/login/refresh). `UserModule` needs `JwtAccessGuard` (to guard `/user/me`). If `AuthModule ⇄ UserModule` imports each other, Nest throws a cycle error.

Resolution: extract `JwtAuthModule` to `src/common/`. Both `AuthModule` and `UserModule` import it. The shared module owns `JwtModule.registerAsync` + `JwtAccessGuard`.

```
AuthModule ─┐
             ├─► imports JwtAuthModule (gets JwtAccessGuard, JwtService)
UserModule ─┘
```

### 2.4 Single-instance migration runner (locked)

All 3 Nest instances boot from the same image. If each ran `migrationsRun: true` simultaneously they'd race on `CREATE EXTENSION` / DDL.

Resolution: `RUN_MIGRATIONS=true` only on `nest-1` (see `docker-compose.yml`). `nest-2` and `nest-3` skip migrations on boot. Migrations are otherwise triggered by `npm run migration:run` against `data-source.ts`.

## 3. PostgreSQL — TypeORM entities

### 3.1 `users`
```ts
@Entity('users')
class User {
  @PrimaryGeneratedColumn('uuid') id: string;
  @Column({ unique: true }) email: string;
  @Column() username: string;
  @Column() passwordHash: string;
  @Column({ default: 1000 }) rating: number;
  @CreateDateColumn() createdAt: Date;
}
```

### 3.2 `matches`
```ts
@Entity('matches')
class Match {
  @PrimaryGeneratedColumn('uuid') id: string;
  @Column('uuid') player1Id: string;
  @Column('uuid') player2Id: string;
  @Column({ nullable: true }) winnerId: string;
  @Column({ default: 'in_progress' })
    status: 'in_progress' | 'finished' | 'forfeited';
  @Column({ type: 'jsonb' })  p1State: Json;  // snapshot HP/gold/roster
  @Column({ type: 'jsonb' })  p2State: Json;
  @CreateDateColumn() createdAt: Date;
  @UpdateDateColumn() finishedAt: Date;
}
```

### 3.3 `match_rounds` (optional detail)
```ts
@Entity('match_rounds')
class MatchRound {
  @PrimaryGeneratedColumn('uuid') id: string;
  @Column('uuid') matchId: string;
  @Column('int')   roundNumber: number;
  @Column({ type: 'jsonb' }) events: Json;   // combat events for replay
}
```

### 3.4 Migrations

- Use TypeORM CLI: `npm run migration:generate -- src/migrations/MyMigration`.
- **Never** `synchronize: true` in production. Set `synchronize: false` always for prod; allowed `true` only in `NODE_ENV=development`.

## 4. Redis Usage

The backend is **stateless**. Mutable game state lives entirely in Redis; multiple NestJS instances can serve requests against the same Redis.

### 4.1 Keys

| Key | Type | Purpose | TTL |
|---|---|---|---|
| `matchmaking:queue` | ZSET | Players waiting (FIFO). `ZADD` on join; atomic ZREM pop on match. | — |
| `match:<matchId>:runtime` | HASH | Live match state: `phase`, `round`, `readyFlags`, `combatLockInstance`, `combatLockUntil`, `wipeIndexP1`, `wipeIndexP2`, `p1Gold`, `p2Gold`, `p1Hp`, `p2Hp`, etc. Whole state is JSON-serialized in fields. | 30 min after match start |
| `match:<matchId>:combat-done` | HASH | Per-player combat-done acks: `playerId -> epoch-ms`. Cleared at each battle start. | 90 s |
| `match:<matchId>:combat-result` | STRING | Serialized `CombatEvent[]` of last battle (for late subscribers). | 60 s |
| `match:<matchId>:shop:<userId>` | STRING | Player-private offers, refresh count, and consumed offer slots for the current round. | 30 min |
| `match:<matchId>:actionLog:<userId>` | HASH | Processed `clientActionId` values used to make retries a no-op. | 120 s |
| `match:<matchId>:shop-lock:<userId>` | STRING | Short per-player mutex serializing concurrent shop actions across replicas. | 5 s |
| `combat-lock:<matchId>` | STRING | `SET NX EX 30s`. Holds the right to call `engine.runBattle()` for this match. | 30 s |
| BullMQ keys | — | Delayed + repeatable jobs (phase timers, combat-done timeout, cleanup). | — |
| Pub/Sub channel `match:<id>:events` | — | Fan-out for combat events and round events across all NestJS instances. | ephemeral |
| Pub/Sub pattern `match:*:events` | — | Subscribed by every NestJS instance on startup. | — |

### 4.2 Operations

| Op | Mechanism | Mutator |
|---|---|---|
| Match runtime read | `HGETALL match:<id>:runtime` | none |
| Match runtime mutate | Lua script `phase_flip.lua` / etc. | Lua atomic |
| Matchmaking pair | Lua atomic pop of bottom 2 ZSET entries (`ZRANGE` + `ZREM` in one Lua) | Lua atomic |
| Combat single-runner | `SET combat-lock:<id> <instanceId> NX EX 30` | Redis native (atomic) |
| Combat-done ack | Lua `combat_done.lua`: HSET if absent, return count | Lua atomic |
| Shop action commit | Per-player `SET NX PX` mutex + `action_log.lua` writes action id, runtime state, and shop state together | Lua atomic |
| Cross-instance WS fan-out | `PUBLISH match:<id>:events <json>` | Pub/Sub |

### 4.3 Matchmaking flow

```
Client → emit  game:matchmaking:join
Server → ZADD matchmaking:queue <joinMs-epoch> <userId>
Server (BullMQ, every 1s):
  atomic Lua:
    members = ZRANGE matchmaking:queue 0 1
    if #members >= 2:
      ZREM matchmaking:queue members[0] members[1]
      return [members[0], members[1]]
  → caller creates Match in PG → emits game:match:phase
```

This is **pure FIFO** (current implementation). Rating (ELO) is tracked but not used for matchmaking; the column is display-only and updated on match end.

## 5. WebSocket Gateway

`@nestjs/platform-socket.io`. Namespace: `/game`. JWT passed in `auth.token` during socket handshake. The WS layer is **stateless**: it does not hold game state. It dispatches incoming events to the appropriate orchestrator adapter in `runtime/`, and publishes outgoing events through Redis Pub/Sub so all instances can forward to their connected sockets.

### 5.1 Event naming convention: `game:<area>:<action>`

Server → client:
- `game:match:phase`     — phase transitions
- `game:shop:offer`      — per-player shop offers (`targetUserId` stays inside the Pub/Sub envelope)
- `game:match:state`     — roster / gold / ready-count snapshot
- `game:combat:events`   — **batch** of all combat events for one battle
- `game:match:damage`    — end-of-round damage
- `game:match:end`       — match end
- `game:error`           — structured error response

Client → server:
- `game:matchmaking:join` / `:leave`
- `game:shop:buy` / `:sell` / `:refresh` / `:fuse`
- `game:match:place` / `:ready`
- `game:match:combat_done` — client acks after playing `game:combat:events`

> Full schemas in `docs/04-api-contracts.md`.

## 6. Flutter Layers

```
mobile/lib/
├── core/
│   ├── api/             # dio REST client + interceptor (JWT)
│   ├── ws/              # Socket.IO client wrapper
│   ├── auth/            # secure storage, token refresh
│   ├── router/          # GoRouter
│   └── config.dart      # URLs, env
│
├── features/
│   ├── auth/
│   │   ├── data/        # repositories, DTOs
│   │   ├── application/ # Riverpod providers
│   │   └── presentation/# login, register screens
│   ├── matchmaking/
│   ├── shop/
│   └── match/
│
├── shared/
│   ├── widgets/         # reusable widgets
│   └── models/          # Dart DTOs mirroring backend contracts
│
└── main.dart
```

### 6.1 State management

- `Provider` for read-only derived state.
- `StateNotifierProvider` for mutable state (shop offers, board units).
- `StreamProvider` for WS event streams.
- No `setState` for game state.

### 6.2 Layer responsibilities

- **Presentation**: widgets & screens; read from providers only.
- **Application**: Riverpod providers; UI logic.
- **Data**: REST + WS clients; repositories transform DTOs.

## 7. Local Dev Setup

```bash
# 1. Infra
docker compose up -d   # postgres + redis

# 2. Backend
cd backend
npm install
npm run migration:run
npm run start:dev      # listens on :3000

# 3. Mobile
cd mobile
flutter pub get
flutter run            # configure localhost backend URL
```

### 7.1 Environment variables (backend `.env`)

```
DATABASE_URL=postgres://postgres:postgres@localhost:5432/auto_chess
REDIS_URL=redis://localhost:6379
JWT_SECRET=<random-32-byte>
JWT_ACCESS_TTL=7d
JWT_REFRESH_TTL=30d
PORT=3000
NODE_ENV=development
```

### 7.2 Mobile config

In `mobile/lib/core/config.dart`:

```dart
const apiBaseUrl = String.fromEnvironment('API_BASE_URL',
    defaultValue: 'http://10.0.2.2:3000'); // Android emulator → host
const wsBaseUrl = String.fromEnvironment('WS_BASE_URL',
    defaultValue: 'http://10.0.2.2:3000');
```

## 8. Top-Level Folder Layout

```
.
├── backend/                # Nest.js app (Nest CLI scaffolds this)
├── mobile/                 # Flutter app (flutter create scaffolds this)
├── docs/                   # Design + architecture docs
├── .opencode/skills/       # AI agent skill files
├── docker-compose.yml      # postgres + redis
└── README.md
```

## 9. CI/CD (post-MVP)

- ESLint (`backend`) + `dart analyze` (`mobile`) on PR.
- Backend unit tests with coverage gate ≥ 90 % on `backend/src/game/`.
- Deploy backend to a single VM with `docker compose`. Build mobile APK via `flutter build apk`.

## 10. Cross-Cutting Concerns

| Concern | Approach |
|---|---|
| Logging | `pino` backend, structured; Flutter logs to console + sentry-like local dump. |
| Error format | REST: `{ code, message }`. WS: `game:error` event with same shape. |
| Config | Env vars via `@nestjs/config`; Flutter via `String.fromEnvironment`. |
| Time | All timestamps UTC; clients render local. |
| Idempotency | Shop actions include `clientActionId`; server dedupes. |

## 11. Stateless Architecture

The backend is **stateless and horizontally scalable**. Multiple NestJS instances run behind any load balancer; all of them share a single Redis (and Postgres for persistence). No game state lives in Node heap between requests.

### 11.1 Topology

```
                        ┌─────────────┐
                        │    nginx    │      ← port 80/443
                        │  least_conn │      ← new connections go to the least-busy Nest
                        │ + WS upgrade │
                        └──┬─────┬────┬┘
                           │     │    │      (round-robin alternative rejected:
                           │     │    │       WS sessions are long-lived,
                           │     │    │       uneven load → use least-connection)
                           ▼     ▼    ▼
                       ┌─────┐┌─────┐┌─────┐
                       │Nest1││Nest2││Nest3│    3 stateless NestJS instances
                       │sock ││sock ││sock │
                       └──┬──┘└──┬──┘└──┬──┘
                          │      │      │     every Nest instance on boot:
                          │      │      │       PSUBSCRIBE match:*:events
                          └──────┼──────┘
                                 │
                  ┌──────────────▼──────────────┐
                  │            Redis             │
                  │  ┌──────────────────────┐   │
                  │  │ matchmaking:queue    │ ZSET
                  │  ├──────────────────────┤   │
                  │  │ match:<id>:runtime   │ HSET
                  │  ├──────────────────────┤   │
                  │  │ match:<id>:combat-done│ HSET
                  │  ├──────────────────────┤   │
                  │  │ match:<id>:result    │ STR (60s TTL)
                  │  ├──────────────────────┤   │
                  │  │ combat-lock:<id>     │ STR (30s TTL)
                  │  ├──────────────────────┤   │
                  │  │ BullMQ jobs          │ delayed + repeatable
                  │  └──────────────────────┘   │
                  │                                │
                  │  Pub/Sub channel match:<id>:events
                  └────────────────────────────────┘

                  ┌───────────────────┐
                  │    Postgres 16     │      per-round snapshots + history
                  └───────────────────┘
```

nginx is configured for `least_conn` (not round-robin) so connections with long-lived WS sessions don't pin load on a single instance. Sticky sessions are intentionally **not** used — a reconnect to a different Nest is absorbed by Redis state + Pub/Sub fan-out (see §12).

### 11.2 Read-modify-write contract

Every WS handler that mutates state goes through this pattern:

```
1. WS handler receives message (e.g., game:match:ready)
2. runtime/match.runtime.adapter.ts:
     const runtime = await redis.hgetall(`match:${id}:runtime`);
     validate action against runtime (phase = 'shop_place'?)
3. mutate atomically:
     const ok = await redis.eval(LUA_PHASE_FLIP, KEYS=[runtimeKey], ARGV=[old, new, instId, round]);
     if (!ok) return;                       // already advanced
4. publish any necessary updates:
     redis.publish(`match:${id}:events`, JSON.stringify(event));
5. respond OK.
```

### 11.3 Combat single-runner (race protection)

When the orchestrator's phase-flip Lua sets phase to `battle`, it also tries to acquire `combat-lock:<id>` via `SET NX EX 30`. The instance that wins the lock is responsible for:

1. Calling `engine.runBattle(state)`.
2. Writing `match:<id>:combat-result` (STRING).
3. `PUBLISH match:<id>:events` with the combat payload.
4. Releasing the lock.

Other instances that later try to acquire the lock see `nil` and skip (they'll re-fetch state from Redis).

### 11.4 Combat-done ack flow

```
Server: PUBLISH match:<id>:events { round, events }    (Lua ack wait)
Server: BullMQ delayed job (60s) for combat_done_timeout

Each client:
  Animates events locally.
  On finish, sends game:match:combat_done { matchId, round, clientActionId }.

Server: (each instance)
  await redis.eval(LUA_COMBAT_DONE, KEYS=[combat-done key], ARGV=[playerId])
  → returns count of distinct acks
  When count == 2 (or timeout): proceed to damage phase.
```

## 12. Pub/Sub Bridge

On boot, every NestJS instance calls `pubsubBridge.subscribe('match:*:events')`. The bridge:

- Maintains a local `Map<matchId, Set<socketId>>` of which sockets are interested in which matches.
- Each WS connect/disconnect updates the map (per-instance, ephemeral).
- On `MESSAGE match:<id>:events payload`:
  - Look up sockets tracking this matchId in the local map.
  - `socket.emit('game:combat:events', JSON.parse(payload))` to each.

This achieves **cross-instance fan-out**: any instance can publish; every connected client gets the event regardless of which instance holds their socket.

Late subscribers (e.g., a client reconnects right after combat was emitted) fetch `match:<id>:combat-result` (60 s TTL) on reconnect.

## 13. Lua Scripts (atomicity)

All `*.lua` files live in `backend/src/redis/scripts/` and are loaded at boot with `SCRIPT LOAD` + cached SHA. The `redisService` exposes `eval<T>(scriptName, keys, args)`.

### 13.1 `phase_flip.lua` — atomic phase transition

```lua
-- KEYS[1] = match:<id>:runtime
-- ARGV[1] = expectedPhase   ('shop_place' / 'battle' / 'resolved')
-- ARGV[2] = newPhase
-- ARGV[3] = instanceId (for combat-lock owner tag)
-- ARGV[4] = expectedRound (optional for backward compatibility)
-- Returns 1 if flipped, 0 if phase or round didn't match.
local cur = redis.call('HGET', KEYS[1], 'phase')
if cur ~= ARGV[1] then return 0 end
if ARGV[4] and ARGV[4] ~= '' then
  local round = redis.call('HGET', KEYS[1], 'round')
  if round ~= ARGV[4] then return 0 end
end
redis.call('HSET', KEYS[1], 'phase', ARGV[2])
if ARGV[2] == 'battle' then
  redis.call('HSET', KEYS[1], 'combatLockInstance', ARGV[3])
  -- combat-lock key is set via SET NX EX outside this script
end
return 1
```

### 13.2 `combat_done.lua` — idempotent ack + count

```lua
-- KEYS[1] = match:<id>:combat-done
-- ARGV[1] = playerId
-- ARGV[2] = epoch ms
-- Returns count of acks after this insert (1 or 2).
if redis.call('HEXISTS', KEYS[1], ARGV[1]) == 1 then
  return tonumber(redis.call('HLEN', KEYS[1]))
end
redis.call('HSET', KEYS[1], ARGV[1], ARGV[2])
redis.call('EXPIRE', KEYS[1], 90)
return tonumber(redis.call('HLEN', KEYS[1]))
```

### 13.3 `match_pair.lua` — atomic matchmaking pop

```lua
-- KEYS[1] = matchmaking:queue (ZSET)
-- Pops the two longest-waiting entries if at least 2 are present.
-- Returns array of [userId1, userId2] or [].
local members = redis.call('ZRANGE', KEYS[1], 0, 1)
if #members < 2 then return {} end
redis.call('ZREM', KEYS[1], members[1], members[2])
return members
```

### 13.4 Why Lua and not WATCH/MULTI/EXEC?

- Round-trips: a single `EVAL` is one round trip; WATCH/MULTI requires multiple.
- Server-agnostic: works with any Redis client; workers across instances all use the same scripts.
- Clearer semantics: scripts read like the desired mutation.
- Loaded once at boot: SHA + EVALSHA on hot path is sub-millisecond.

## 14. Race Conditions and Idempotency

The state machine + Lua scripts make every shared-mutation safe. Below is the **complete list** tracked for this project.

| # | Race | Where | Lock / resolution |
|---|---|---|---|
| 1 | Two simultaneous **register** requests with same email | auth.controller | **PG unique constraint** on `users.email` — last insert raises 23505, mapped to 409 |
| 2 | Two simultaneous **username update** from same user | user.controller | Last-write-wins on `users.username`; both UPDATEs succeed. Acceptable. |
| 3 | Token refresh collision (long-lived, no rotation) | auth.service | Both refreshes return success with new tokens; multiple valid pairs coexist. Acceptable. |
| 4 | **Two BullMQ pollers** fire matchmaking at the same tick | matchmaking | **Atomic Lua** (`match_pair.lua`) — only one wins the `ZREM` |
| 5 | Player **joins queue while being matched** | matchmaking | Atomic `ZRANGE 0 1 + ZREM` is one op; player is either selected or not, never half-selected. |
| 6 | **Both players `game:match:ready` simultaneously** | runtime | **Atomic Lua** (`phase_flip.lua`) — first wins the phase flip; second sees `phase != 'shop_place'` and returns 0 |
| 7 | **Client retries `shop:buy`** with the same `clientActionId` | runtime | **Optimistic** (`action_log.lua` HEXISTS) — second insert is a no-op |
| 8 | **Late shop action** for previous round (stale `round` field) | runtime | Phase + round validation in Lua rejects; client must re-fetch state |
| 9 | **Composite read-modify-write** outside a script | runtime | Forbidden by Hard Rule #10; every composite RMW must go through Lua |
| 10 | **Action arrives after phase advanced** | runtime | Phase validation rejects with `match.not_your_turn` |
| 11 | **Combat runs twice** (retry / two schedulers / failover) | combat.coordinator | **Pessimistic lock** (`SET combat-lock:<id> <instanceId> NX EX 30`) — only one instance calls `engine.runBattle()` |
| 12 | **`combat_done` arrives twice** from same player | runtime | **Optimistic** (`combat_done.lua` HEXISTS) — second insert is a no-op |
| 13 | **`combat_done` arrives after damage applied** | runtime | Phase validation rejects with `combat.not_in_battle` |
| 14 | **Late subscriber misses combat result** | pubsub.bridge | **60 s Redis fallback** — client fetches `match:<id>:combat-result` on reconnect |
| 15 | **Pub/Sub message lost** between publish and subscriber-list update | pubsub | Fire-and-forget; covered by Redis fallback (R14) |
| 16 | **Two WS from same player** on different instances | ws.gateway | Per-user connect dedup: last socket wins; previous disconnects |
| 17 | **Player disconnects mid-battle** | match.runtime | Forfeit applied to that player; other client wins |
| 18 | **Reconnect mid-match to different instance** | pubsub.bridge | OK: Pub/Sub + Redis state absorb the move |
| 19 | **Two instances write `p1State` snapshot simultaneously** | match.service | Last-write-wins at PG row level. Acceptable for MVP (snapshots overwrite, history in `match_rounds.events` is the source of truth) |
| 20 | **`match_rounds.events` write fails after damage applied** | match.service | Combat result is in Redis; PG write is best-effort. Match state is correct; round history may be lost. Acceptable. |

## 15. Match Action Log (idempotency)

Each shop/place/ready/combat_done action carries a `clientActionId`. The runtime adapter writes `{actionKey: clientActionId}` to a HSET `match:<id>:actionLog:<userId>` via Lua (`action_log.lua`):

```lua
-- KEYS[1] = match:<id>:actionLog:<userId>
-- KEYS[2] = match:<id>:runtime                 (optional shop commit)
-- KEYS[3] = match:<id>:shop:<userId>           (optional shop commit)
-- ARGV[1] = clientActionId
-- Returns 1 if newly recorded, 0 if duplicate.
if redis.call('HEXISTS', KEYS[1], ARGV[1]) == 1 then return 0 end
if KEYS[2] and KEYS[3] then
  if redis.call('HGET', KEYS[2], 'round') ~= ARGV[8] then return -2 end
  if redis.call('HGET', KEYS[2], 'phase') ~= ARGV[7] then return -1 end
end
redis.call('HSET', KEYS[1], ARGV[1], ARGV[2])    -- ARGV[2] = epoch ms
redis.call('EXPIRE', KEYS[1], 120)
if KEYS[2] and KEYS[3] then
  redis.call('HSET', KEYS[2], ARGV[3], ARGV[4])  -- player state field + JSON
  redis.call('SET', KEYS[3], ARGV[5], 'EX', ARGV[6])
end
return 1
```

For shop actions, the same script atomically records the action and commits the
updated runtime/shop JSON. If a client retries on network failure, the second
arrival is a no-op. Re-tries within 120 s are safe.

## 16. Boot Order & Topology

```
docker compose up -d
  ├─ postgres-primary   (postgres:16-alpine + init-primary.sh)
  ├─ postgres-replica   (postgres:16-alpine, pg_basebackup on first init)
  ├─ redis              (redis:7-alpine)
  ├─ nest1              (RUN_MIGRATIONS=true; runs CreateUsers on boot)
  ├─ nest2              (no migrations; otherwise identical)
  ├─ nest3              (no migrations; otherwise identical)
  ├─ nginx              (port 80 → upstream backend; bind-mounted conf)
  └─ pgadmin            (port 5050 → host browser UI)

Each Nest instance on boot:
  - Connects to postgres-primary + redis
  - If RUN_MIGRATIONS=true: runs pending migrations (one instance only)
  - When ws/ lands: PSUBSCRIBEs match:*:events, starts BullMQ workers
  - Begins accepting HTTP + WS via the shared upstream

Postgres replication is configured via init-primary.sh on primary:
  - Creates `replicator` role with REPLICATION privilege
  - Appends `host replication replicator 0.0.0.0/0 md5` rule to pg_hba.conf
  - Replica container runs pg_basebackup on first init

nginx config (`nginx/nginx.conf`) is **bind-mounted** into the
container at `/etc/nginx/nginx.conf:ro` so changes apply via
`docker compose down nginx && up -d nginx` without rebuilding.
`docker compose restart nginx` is **not enough** — recreate required.
```

### 16.1 nginx details

| Concern | Setting |
|---|---|
| Load balancing | `least_conn` over 3 Nest upstreams |
| HTTP keep-alive | `keepalive 32` per upstream |
| CORS | `Access-Control-Allow-Origin: *` for MVP; tighten before prod |
| Preflight | `OPTIONS → 204` short-circuit at server level (no proxy) |
| WS upgrade | `proxy_set_header Upgrade $http_upgrade` on `/socket.io/` |
| Public port | 80 (HTTP only) |

**NFR-13 compliance**: 3 instances prove the multi-node story empirically.

**No sticky sessions.** A client can land on Nest 1, reconnect to Nest 2 mid-match — it just works because match state is in Redis, events fan out via Pub/Sub, and combat result is cached for 60 s.

## 17. Lock Choice Taxonomy

For each shared-mutation shape, we picked a lock strategy explicitly. The table below is the project's policy.

| Pattern | When to use | Cost | Used at |
|---|---|---|---|
| **Atomic Lua** (Redis single-thread script) | Read-check-write must appear atomic | 1 RTT, ~µs | `phase_flip` (R6), `match_pair` (R4), `action_log` (R7), `combat_done` (R12) |
| **Pessimistic lock** (`SET NX EX`) | Expensive / side-effectful op that must not be repeated | 1 RTT + lock wait or TTL expiry | `combat-lock` (R11) — runs `engine.runBattle()` |
| **Optimistic** (idempotency check) | Cheap, repeated ops we just skip on duplicate | 1 RTT | `action_log` (R7), `combat_done` (R12) |
| **PG unique constraint** | Duplicate-key inserts protected by the DB | 0 (DB-side) | Duplicate email (R1) |
| **Last-write-wins** | Field where concurrent edits are user-correctable | 0 | Username (R2), `p1State` snapshot (R19) |
| **Pub/Sub + Redis fallback** | Cross-instance event delivery that tolerates loss | best-effort + 60 s TTL | Event delivery (R14, R15) |
| **Fire-and-forget** | Truly don't-care transient state | 0 | Late Pub/Sub messages (R15) |

### Considered and rejected

| Lock type | Why rejected for MVP |
|---|---|
| **Redlock** (multi-master Redis) | Single Redis is sufficient; Redlock is for replicated deployments |
| **`SELECT FOR UPDATE`** on PG rows | JSONB overwrites are atomic at row level; pessimistic DB locks are unnecessary overhead |
| **CRDT / multi-master** | Overkill; no parallel writers for the same field in this system |
| **Sticky sessions + per-instance state** | Defeats the stateless goal; Pub/Sub absorbs cross-instance anyway |

### Decision flow (cheatsheet)

```
                   expensive / irreversible
                              ▲
                              │
                  R11 Combat  │   ⇒ Pessimistic (SET NX EX)
                              │
   cross-instance   ──────────┼──────────   same-instance
                              │
       R14, R15 Pub/Sub       │ R6, R4, R7, R12 Lua
       (eventual / cached)    │ (atomic Lua)
                              │
                  R1, R2, R19 │
                  (PG / last-write-wins)
                              │
                              ▼
                   cheap / skip-on-dup
```
