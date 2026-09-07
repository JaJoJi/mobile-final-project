# Project Backlog

> Stack: Flutter (mobile) + Nest.js (backend) + TypeORM + PostgreSQL + Redis. University MVP, 3 people × 1 month.
> Reference docs: `docs/01-game-design.md`, `docs/02-requirements.md`, `docs/03-architecture.md` §16, `docs/04-api-contracts.md`, `docs/05-combat-spec.md`.
> Skill: `.opencode/skills/auto-chess-game/SKILL.md`.

## Implementation status today

- ✅ infra (`docker-compose`, 7 services, nginx `least_conn`, PG primary+replica)
- ✅ `auth/`, `user/`, `common/jwt-auth`, `common/health`, `redis/` (basic), `migrations/1736…-CreateUsers.ts`, `data-source.ts`
- ✅ Flutter `LoginScreen`, `RegisterScreen`, `HealthScreen`, `ApiClient`, `AuthRepository`, `AppConfig`
- ❌ no WebSocket, no matchmaking, no combat engine, no shop, no match lifecycle, no Pub/Sub, no tests, no CI

---

## Label taxonomy

| Group | Labels | Meaning |
|---|---|---|
| **area** | `area:backend` | Code in `backend/` (Nest, TypeORM, Lua). |
|  | `area:frontend` | Code in `mobile/` (Flutter, Riverpod). |
|  | `area:devops` | CI/CD, Docker, nginx, monitoring, deployment. |
|  | `area:docs` | `docs/*.md`, `README.md`, `SKILL.md`. |
| **type** | `type:feature` | New user-facing functionality. |
|  | `type:bug` | Bug fix. |
|  | `type:chore` | Refactor, cleanup, docs update, internal quality. |
|  | `type:test` | Writing/running tests (unit, widget, integration, e2e). |
|  | `type:infra` | Infrastructure plumbing (CI, Docker, Redis scripts, BullMQ, observability, hardening). |
| **priority** | `priority:p0` | Critical path — game cannot function without it. |
|  | `priority:p1` | Required for MVP launch, blocked by P0. |
|  | `priority:p2` | Post-MVP / out-of-scope per `docs/01 §9` / `docs/02 §4`. |
|  | `priority:p3` | Quality / NFR / dev-experience. |

> Hard rule from `SKILL.md §4`: **all combat math on backend**. Any ticket that puts combat logic in Flutter is a violation — redirect.

---

## P0 — Backend

| ID | Title | Labels | Includes | Maps to |
|---|---|---|---|---|
| P0-BE-01 | **Real-time Gateway** — WebSocket gateway, JWT handshake auth, Pub/Sub cross-instance fan-out, late-subscriber fallback, WS payload validation, `game:error` events | `area:backend` `type:infra` `priority:p0` | `ws/` module (namespace `/game`, `game:*` events, `WsAuthGuard`, per-user socket dedup); `runtime/pubsub.bridge.ts` (PSUBSCRIBE `match:*:events`, local `Map<matchId, Set<socketId>>`, `match:<id>:combat-result` 60 s TTL cache); Lua `phase_flip`, `combat_done`, `action_log`; `ws.dto.ts` (class-validator for every `game:*` payload); global WS error envelope | docs/03 §5, §11–§12, R6/R12/R14/R15/R16 |
| P0-BE-02 | **Matchmaking System** — Redis ZSET queue, atomic pairing, WS join/leave, auto-creates match on pair | `area:backend` `type:feature` `priority:p0` | `matchmaking/` module (WS handlers `game:matchmaking:join/leave`); Lua `match_pair` (atomic ZRANGE+ZREM); BullMQ repeatable 1 s poller; broadcast `game:match:phase` to both paired clients | FR-MATCH-1..4, R4/R5 |
| P0-BE-03 | **Match Lifecycle Service** — Match entity + migration, create/end/persist match state, match history endpoints, ELO rating update | `area:backend` `type:feature` `priority:p0` | `match/` module (`Match` entity with `matchSeed`, `wipeIndexP1`, `wipeIndexP2`, `p1State/p2State jsonb`; `MatchRound` entity for `events jsonb` replay); migration `CreateMatches`; `match.service` (create on pair, end on `hp_zero`/`forfeit`/`disconnect`); `match.controller` (`GET /match/history`, `GET /match/:matchId`); `UserService.updateRating(id, delta)` (ELO K=32); per-player forfeit on WS `disconnect` (NFR-12) | docs/03 §3.2–§3.3, FR-END-1..3, FR-HIST-1..2 |
| P0-BE-04 | **Round Orchestrator** — Phase state machine (shop_place → battle → resolved → next round), 40 s shop timer, combat single-runner lock, combat-done ack wait + 60 s timeout, end-of-round damage apply | `area:backend` `type:feature` `priority:p0` | `runtime/match.runtime.adapter.ts` (single entry for every WS mutation: read `HGETALL match:<id>:runtime`, validate phase+round, dispatch via Lua, publish events); `runtime/combat.coordinator.ts` (`SET combat-lock:<id> <instId> NX EX 30`, write `match:<id>:combat-result` 60 s TTL, `PUBLISH match:<id>:events`); `queue/` (BullMQ: 40 s phase timer, 60 s `combat_done_timeout`, 30 s disconnect detector, match cleanup); `match.<round>.ended` ack aggregation across both clients | docs/03 §11.2–§11.4, §13, FR-GAME-1..8, R8/R9/R10/R11/R18 |
| P0-BE-05 | **Cycle Processor** (combat engine) — Pure `runBattle(state): CombatEvent[]`, seeded RNG, targeting algorithm, all 4 unit abilities at all star levels, Tank Revive, wipe/tie resolution | `area:backend` `type:feature` `priority:p0` | `game/` module (`runBattle` pure function; seeded RNG utility `seedrandom`/xorshift injected as `state.rng`; `pickTarget` with front-row → same-lane → fall-back; targeting tie-break by lowest col→row→instanceId; `applyDamage` with Tank 1★ Revive; Fighter Lifesteal 5%/10%; Ranger Pierce 10% + 2★ global-lowest-HP; Tank 2★ Prioritize; Healer heal-lowest-ally + 2★ heal-two + 1★ Slow; tie-tick init ordering from `roundSeed`; wipe index `[5,10,15,20,25]` capped; tie = 5 each no index advance); **no `Math.random`** | FR-COMBAT-1..5, docs/05 §1–§6, NFR-4 |
| P0-BE-06 | **Shop System** — Server-side offer generation with seeded RNG, gold ledger, buy/sell/refresh/fuse + auto-fuse on buy | `area:backend` `type:feature` `priority:p0` | `shop/` module (`ShopService.generateOffers(matchSeed, round, playerId)` returns 5 cards with probabilities Fighter 40 / Healer 40 / Ranger 15 / Tank 5, all 0★; gold ledger; `Buy` deducts gold + appends to roster + auto-fuses with same-star duplicate; `Sell` returns 100% cost; `Refresh` rerolls (free once/phase); `Fuse` merges two same-star copies); `game:shop:offer` emit per player | FR-GAME-2..3, docs/01 §4, docs/05 §7 |

---

## P0 — Frontend

| ID | Title | Labels | Includes | Maps to |
|---|---|---|---|---|
| P0-FE-01 | **WS & Models Foundation** — Socket.IO client, Riverpod StreamProviders, all Dart DTOs mirroring `docs/04 §2`, auto-reconnect with backoff | `area:frontend` `type:feature` `priority:p0` | `core/ws/{ws_client.dart, ws_event.dart, ws_providers.dart}` (connect to `AppConfig.wsBaseUrl`, pass `auth.token = accessToken`, reconnect+backoff, `StreamProvider<MatchEvent>` family); `shared/models/*.dart` (`Unit`, `ShopOffer`, `MatchState`, sealed `CombatEvent` union, `MatchEnd`, `MatchPhase`, `MatchDamage`); camelCase field names mirroring backend | docs/03 §5–§6, docs/04 §2 |
| P0-FE-02 | **Auth Flow Hardening** — Silent token refresh on 401, session restoration on launch, go_router migration | `area:frontend` `type:chore` `priority:p0` | Extend Dio interceptor (401 → `AuthRepository.tryRefresh()` once, retry; on failure → logout); `core/router.dart` (go_router with `/lobby`, `/match/:id` guards); `main.dart` (read tokens on launch → silent `tryRefresh()` → `/lobby` else `/login`); `AuthRepository.tryRefresh()` already exists, wire it in | US-2, NFR-7 |
| P0-FE-03 | **Lobby Page** — Matchmaking queue (join/leave/searching/found states), profile card, logout | `area:frontend` `type:feature` `priority:p0` | `features/matchmaking/matchmaking_screen.dart` ("Find match" → `game:matchmaking:join`; status "Searching…" / "Match found!"; cancel emits `game:matchmaking:leave`; on `game:match:phase` navigate to `/match/:id`); profile card (username, email, rating from `/user/me`); logout button (uses existing `AuthRepository.logout()`) | FR-MATCH-1..4 |
| P0-FE-04 | **Match Page** — Shop tab + Board tab + 40 s phase countdown + Ready button + end-of-round result overlay | `area:frontend` `type:feature` `priority:p0` | `features/match/match_screen.dart` (receives `game:match:phase`; tabs `Shop` / `Board`; 40 s `PhaseTimerRing`; "Ready" → `game:match:ready`); `features/match/shop/*.dart` (5 cards from `game:shop:offer`, gold display, Buy/Sell/Refresh/Fuse buttons, `clientActionId` UUID per action, optimistic update + rollback on `game:error`); `features/match/board/*.dart` (2×3 grid per player mirror, 8-slot bench, drag unit board↔bench↔shop → `game:match:place`); `features/match/result/*.dart` (render `game:match:damage` and `game:match:end`; HP bars, wipe-damage popup, "You won / You lost" modal) | FR-GAME-1..7, FR-END-1 |
| P0-FE-05 | **Battle Animation System** — Receive `game:combat:events`, play batched events sequentially, ack with `game:match:combat_done`; reconnect refetches via `match:<id>:combat-result` fallback | `area:frontend` `type:feature` `priority:p0` | `features/match/battle/*.dart` (event sequencer — movement flashes, attack hits, death, heal, slow, pierce, revive — based on `CombatEvent` sealed type; speed slider; on finish emit `game:match:combat_done {clientActionId}`); on WS reconnect mid-match, fetch latest cached combat result for active `matchId`; resubscribe to current match's event stream | FR-GAME-5, R18 |
| P0-FE-06 | **Design System / Shared Widgets** — PhaseTimerRing, HealthBar, UnitAvatar, ErrorBanner, loading/empty states | `area:frontend` `type:chore` `priority:p0` | `shared/widgets/phase_timer_ring.dart` (animated 40 s countdown); `shared/widgets/health_bar.dart` (reused on board + result); `shared/widgets/unit_avatar.dart` (placeholder sprites OK for MVP); `shared/widgets/error_banner.dart` (human-readable strings for `game:error` codes); loading + empty placeholders for matchmaking waiting, history empty, "no offers" | NFR-7 |

---

## P0 — DevOps

> No new P0 infra tickets — `docker-compose.yml`, `nginx.conf`, and the 7-service topology already exist and do not block P0-BE / P0-FE. First DevOps ticket is **P3-DO-01**.

---

## P1 — Backend

| ID | Title | Labels | Includes | Maps to |
|---|---|---|---|---|
| P1-BE-01 | **Realtime Hardening** — Rate limiting on WS, global exception filter (REST + WS), structured logging with `pino` | `area:backend` `type:chore` `priority:p1` | `common/throttle.guard.ts` (per-user 30 msg/s, `rate.limited`); `common/filters/` (REST `{code, message}`, WS `game:error` same shape); `common/logger.module.ts` (replace `Logger` defaults with `pino`; per-request id; per-match id propagated through orchestrator) | NFR-7, NFR-8, docs/04 §5 |
| P1-BE-02 | **Server-side WS Payload Hardening** — `class-validator` DTOs for every incoming `game:*` payload; rejected → `game:error { code: 'invalid_payload' }` | `area:backend` `type:feature` `priority:p1` | `ws/ws.dto.ts` (per `docs/04 §3`: `round` matches server, `slot`/`offerIndex` in range, `unitInstanceId` in caller roster, source of funds/ownership, `clientActionId` not previously processed) | NFR-6 |

---

## P1 — Frontend

| ID | Title | Labels | Includes | Maps to |
|---|---|---|---|---|
| P1-FE-01 | **History Pages** — Match list + match detail | `area:frontend` `type:feature` `priority:p1` | `features/history/history_list_screen.dart` (paged `GET /match/history`, tap → detail); `features/history/match_detail_screen.dart` (`GET /match/:matchId`, round-by-round winner + damage) | FR-HIST-1, FR-HIST-2 |
| P1-FE-02 | **Profile & Settings Page** — Username/email/rating card, logout, theme + WS reconnect toggle | `area:frontend` `type:feature` `priority:p1` | `features/profile/profile_screen.dart` (read from `/user/me`; logout uses existing `AuthRepository.logout()`); settings (dark/light theme toggle, WS auto-reconnect toggle) | — |

---

## P2 — Backend (post-MVP / `docs/01 §9`)

| ID | Title | Labels | Maps to |
|---|---|---|---|
| P2-BE-01 | **Replay API** — `GET /match/:matchId/replay` returning `MatchRound.events[]` | `area:backend` `type:feature` `priority:p2` | docs/01 §9 |
| P2-BE-02 | **Surrender** — `game:match:surrender` WS event; applies `forfeit` | `area:backend` `type:feature` `priority:p2` | docs/01 §6.3 |
| P2-BE-03 | **Rating-based Matchmaking** — Replace FIFO with nearest-rating matching (currently display-only per `docs/03 §4.3`) | `area:backend` `type:feature` `priority:p2` | docs/01 §8 |
| P2-BE-04 | **Items / XP / Level-up System** — Unit items + drop tables + player XP / level-up | `area:backend` `type:feature` `priority:p2` | docs/01 §9 |
| P2-BE-05 | **Multi-player & Spectator Modes** — 3+ player mode + spectator mode | `area:backend` `type:feature` `priority:p2` | docs/01 §9 |
| P2-BE-06 | **Refresh Token Rotation & Blacklist** — Replace long-lived refresh model | `area:backend` `type:feature` `priority:p2` | docs/02 §4; `SKILL.md §4.12` |
| P2-BE-07 | **Push Notifications** — Mobile push for match-found / your-turn events | `area:backend` `type:feature` `priority:p2` | docs/02 §4 |
| P2-BE-08 | **Multi-region Deployment** — Cross-region Redis / PG topology | `area:backend` `type:infra` `priority:p2` | docs/01 §9 |

---

## P2 — Frontend (post-MVP)

| ID | Title | Labels | Maps to |
|---|---|---|---|
| P2-FE-01 | **Surrender Button** — On match screen | `area:frontend` `type:feature` `priority:p2` | docs/01 §6.3 |
| P2-FE-02 | **Replay Viewer Page** — Playback `CombatEvent[]` from `/match/:id/replay`; scrubber | `area:frontend` `type:feature` `priority:p2` | docs/01 §9 |
| P2-FE-03 | **Cosmetic Skins & Animations** — Unit skins + polish animations | `area:frontend` `type:feature` `priority:p2` | docs/01 §9 |
| P2-FE-04 | **Spectator Mode UI** | `area:frontend` `type:feature` `priority:p2` | docs/01 §9 |
| P2-FE-05 | **iOS Support** — Build iOS targets (currently Android/Chrome only) | `area:frontend` `type:feature` `priority:p2` | docs/01 |
| P2-FE-06 | **Localization** — en + additional languages | `area:frontend` `type:feature` `priority:p2` | UX |
| P2-FE-07 | **Push Notification Opt-in** | `area:frontend` `type:feature` `priority:p2` | docs/02 §4 |

---

## P3 — Backend (quality / NFR / dev-experience)

| ID | Title | Labels | Includes | Maps to |
|---|---|---|---|---|
| P3-BE-01 | **Combat Engine Test Suite** — Unit tests for `game/` with ≥ 90 % line coverage | `area:backend` `type:test` `priority:p3` | `game/engine.spec.ts` + `game/abilities.spec.ts`; cover targeting matrix, every ability at every star, all edge cases E1–E16, fixed-seed full-battle regression (byte-for-byte) | **NFR-9** |
| P3-BE-02 | **Lua & Shop Determinism Tests** — Atomic-Lua tests + shop RNG replay tests | `area:backend` `type:test` `priority:p3` | `redis/scripts/*.spec.ts` (`match_pair`, `phase_flip`, `combat_done`, `action_log` against `ioredis-mock`); `shop/shop.spec.ts` (same `matchSeed + round + playerId` → identical 5 offers) | NFR-13, FR-COMBAT-5 |
| P3-BE-03 | **Backend Quality Polish** — Lint, OpenAPI, security headers, graceful shutdown, health split, anti-cheat audit | `area:backend` `type:chore` `priority:p3` | ESLint config + CI gate (`NFR-10`); `@nestjs/swagger` OpenAPI artifact; Helmet + REST rate-limit; CORS tightening (replace `*`); graceful shutdown (close sockets, drain BullMQ, release combat-lock); `/health` split into `/ready` + `/live`; pagination for `/match/history` (cursor); server-side shop RNG audit log; `clientActionId` uniqueness + payload schema validation on the wire | NFR-1, NFR-7, NFR-10, NFR-13 |

---

## P3 — Frontend (quality / NFR / dev-experience)

| ID | Title | Labels | Includes | Maps to |
|---|---|---|---|---|
| P3-FE-01 | **Widget Test Suite** — Smoke tests for every screen | `area:frontend` `type:test` `priority:p3` | `test/` for `LoginScreen`, `RegisterScreen`, `HealthScreen`, `MatchmakingScreen`, `MatchScreen`, `ShopScreen`, `BoardScreen`, `HistoryListScreen`, `MatchDetailScreen`, `ProfileScreen` | NFR-10 |
| P3-FE-02 | **Frontend Quality Polish** — CI lint gate, local error logger, accessibility pass | `area:frontend` `type:chore` `priority:p3` | `flutter analyze` clean + CI gate; local Sentry-like dump for unhandled exceptions (`NFR-8`); semantic labels on board slots, shop cards, HP bars | NFR-8, NFR-10 |

---

## P3 — DevOps

| ID | Title | Labels | Includes | Maps to |
|---|---|---|---|---|
| P3-DO-01 | **CI Pipeline** — GitHub Actions: lint + build + test on PR | `area:devops` `type:infra` `priority:p3` | 2 jobs — `backend` (`npm ci && npm run build && npm test`); `mobile` (`flutter pub get && flutter analyze && flutter test`) | NFR-10 |
| P3-DO-02 | **CD Pipeline** — Build & publish Nest image to GHCR on `main`; semantic version tags | `area:devops` `type:infra` `priority:p3` | `.github/workflows/release.yml`; image tagging from git tag | DX |
| P3-DO-03 | **Observability Stack** — Prometheus `/metrics`, Grafana dashboards, Loki for logs | `area:devops` `type:infra` `priority:p3` | `@willsoto/nestjs-prometheus`; per-instance + per-match metrics; log shipping | NFR-2, NFR-14 |
| P3-DO-04 | **Production Hardening** — Strong `JWT_SECRET` per env, HTTPS termination, secret rotation, pgBouncer, backup policy | `area:devops` `type:infra` `priority:p3` | nginx TLS cert mount; secrets manager wiring; pgBouncer sidecar; daily `pg_basebackup` of `pg_primary_data` | NFR-5, NFR-13 |
| P3-DO-05 | **Load Testing & Capacity Validation** — k6 script verifying NFR-3 (≥ 50 concurrent matches), NFR-2 (p95 < 500 ms), NFR-14 (combat < 500 ms p95) | `area:devops` `type:test` `priority:p3` | `k6/load.js` runs against `docker compose up` stack; results published as CI artifact | NFR-2, NFR-3, NFR-14 |
| P3-DO-06 | **Repo Hygiene** — Templates, CODEOWNERS, Dependabot, pre-commit, badges | `area:devops` `type:chore` `priority:p3` | `.github/ISSUE_TEMPLATE`, PR template (references FR/NFR IDs); `.github/CODEOWNERS` (backend/mobile/docs); Dependabot for npm + pub; pre-commit hooks (`prettier`, `eslint --fix`); README CI/coverage badges; `.dockerignore` tightening | DX, NFR-5 |

---

## Recommended execution order (P0 only)

```
# Backend
P0-BE-05  Cycle Processor (combat engine — pure functions, easiest to test in isolation)
P0-BE-01  Real-time Gateway (WS + Pub/Sub + Lua primitives)
P0-BE-03  Match Lifecycle Service (entity, create, persist, history, ELO)
P0-BE-04  Round Orchestrator (phase machine, combat-lock, timers)
P0-BE-02  Matchmaking System (depends on Match + WS)
P0-BE-06  Shop System

# Frontend (can start in parallel with backend)
P0-FE-01  WS & Models Foundation
P0-FE-02  Auth Flow Hardening
P0-FE-06  Design System / Shared Widgets
P0-FE-03  Lobby Page
P0-FE-04  Match Page
P0-FE-05  Battle Animation System
```

---

## GitHub Project layout

```
Board columns (4 only):
  Backlog → In Progress → Review → Done

Priority is filtered by label (priority:p0 / p1 / p2 / p3), not by column.

Labels (apply all matching per ticket):
  area:     area:backend · area:frontend · area:devops · area:docs
  type:     type:feature · type:bug · type:chore · type:test · type:infra
  priority: priority:p0 · priority:p1 · priority:p2 · priority:p3
```
