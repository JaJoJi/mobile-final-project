# Requirements

## 1. Functional Requirements

### Authentication
- **FR-AUTH-1**: User can register with `email` + `password` + `username`. Email must be valid; password ≥ 8 chars.
- **FR-AUTH-2**: User can log in and receive a JWT (access + refresh). Access expires in 7 days; refresh in 30 days.
- **FR-AUTH-3**: All authenticated endpoints require `Authorization: Bearer <token>`.
- **FR-AUTH-4**: User can update username via `PATCH /user/me`. Email and password are non-editable post-MVP.

### Matchmaking
- **FR-MATCH-1**: Logged-in user can join matchmaking queue via `game:matchmaking:join` WS event.
- **FR-MATCH-2**: Server matches two waiting players within 30 s of second player joining.
- **FR-MATCH-3**: When matched, both clients receive a `game:match:phase` event with `matchId` and phase = `shop_place`.
- **FR-MATCH-4**: User can leave queue via `game:matchmaking:leave` if not yet matched.

### Game flow (per round)
- **FR-GAME-0**: Each player's board is **3 rows × 3 cols (9 slots)**. Bench is 8 slots (separate). Lane = column 0..2. Row 0 = front row (closest to enemy), row 1 = middle row, row 2 = back row.
- **FR-GAME-1**: Each round begins with a 40 s merged shop+place phase.
- **FR-GAME-2**: Server emits shop offers at phase start (5 cards, server-side seeded RNG).
- **FR-GAME-3**: Player can `buy`, `sell`, `refresh`, `fuse`, `place`, and click `Ready` during the phase.
- **FR-GAME-4**: Battle starts when both players are Ready **or** 40 s elapses.
- **FR-GAME-5**: Battle resolves server-side; the engine produces a single `CombatEvent[]` array per battle, emitted as one `game:combat:events` batch. Each client acks with `game:match:combat_done`. Server waits for both acks OR a 60 s timeout before applying damage via `game:match:damage`.
- **FR-GAME-6**: Battle ends when one side is empty **or** after 30 cycles (3000 ticks).
- **FR-GAME-7**: On battle end, server applies damage, awards gold, emits `game:match:damage`, then starts the next round.
- **FR-GAME-8**: Match ends when a player HP ≤ 0 or a player disconnects.

### Combat (server-side only)
- **FR-COMBAT-1**: All combat math runs in `backend/src/game/`. Flutter never computes damage, targeting, or ability effects.
- **FR-COMBAT-2**: Combat follows `docs/05-combat-spec.md` (cycle-based tick model).
- **FR-COMBAT-3**: Tank 1★ Revive triggers in-tick and does not break the cycle.
- **FR-COMBAT-4**: 2★ global rules (Tank prioritize, Ranger global targeting) compose with base targeting.
- **FR-COMBAT-5**: All RNG (shop, tie-tick init) derives from a per-match seed. Same seed + same inputs ⇒ identical outcome.

### Win / Loss
- **FR-END-1**: Player at 0 HP loses; opponent wins.
- **FR-END-2**: On disconnect during a match, the disconnected player loses immediately.
- **FR-END-3**: On match end, server persists match history and updates ratings (post-MVP ratings optional).

### Match history
- **FR-HIST-1**: User can view list of past matches (most recent 50) via `GET /match/history`.
- **FR-HIST-2**: User can view match detail via `GET /match/:matchId` (basic: participants, rounds, winner).

## 2. Non-Functional Requirements

| ID | Requirement |
|---|---|
| NFR-1 | **Authoritative server**: client cannot influence combat outcome. All round resolution happens on backend. |
| NFR-2 | **Latency**: p95 round-state WS event delivery < 500 ms within same region. |
| NFR-3 | **Concurrency**: system supports ≥ 50 concurrent matches (~3 min each, 1v1). |
| NFR-4 | **Determinism**: given the same match seed and same client actions, battle outcome is reproducible. |
| NFR-5 | **Security**: passwords hashed with bcrypt (≥ 10 rounds). JWT secret ≥ 32 bytes, rotated via env. |
| NFR-6 | **Validation**: all REST inputs validated by `class-validator` DTOs; all WS payloads validated server-side. |
| NFR-7 | **Error handling**: backend never crashes on bad input — returns structured error (REST 4xx/5xx, WS `game:error` event). |
| NFR-8 | **Logging**: structured logs (`pino`) on backend; Flutter logs errors with context. |
| NFR-9 | **Testing**: combat rules engine (`backend/src/game/`) has ≥ 90 % line coverage; every ability has at least one unit test. |
| NFR-10 | **Style**: ESLint passes on backend CI; `flutter analyze` passes on mobile CI. |
| NFR-11 | **Reproducibility**: shop RNG seeded per player; tie-tick init RNG seeded per round. |
| NFR-12 | **Disconnect detection**: server detects socket close within 30 s and forfeits the disconnected player. (Per design decision: instant forfeit on disconnect, not 30 s grace.) |
| NFR-13 | **Multi-instance statelessness**: ≥ 2 NestJS instances must run concurrently with shared Redis. No mutable state in Node heap between requests. |
| NFR-14 | **Combat latency**: from `phase: battle` flip to `game:combat:events` emitted < 500 ms p95 within same region. |
| NFR-15 | **Combat single-runner**: only ONE instance runs `engine.runBattle()` per match. Enforced via `SET NX EX` lock on `combat-lock:<matchId>`. Concurrent WS schedulers must never double-run combat. |

## 3. User Stories

- **US-1**: *As a player, I want to register an account* so I can play ranked games.
- **US-2**: *As a player, I want to log in once and stay logged in* so I don't re-enter credentials every match.
- **US-3**: *As a player, I want to enter matchmaking* so I can find an opponent quickly.
- **US-4**: *As a player, I want to see my shop with 5 units* so I can choose what to buy.
- **US-5**: *As a player, I want to drag units from shop to board* so I can position them.
- **US-6**: *As a player, I want units to auto-fuse when I buy duplicates* so I don't manage fusion manually.
- **US-7**: *As a player, I want to see live battle updates* so I can follow what's happening.
- **US-8**: *As a player, I want to see who won the round* so I know whether I took damage.
- **US-9**: *As a player, I want to see my match history* so I can review past games.
- **US-10**: *As a player, I want the game to be fair* so outcomes depend on decisions, not luck or cheating.
- **US-11**: *As a developer, I want combat logic to be pure functions* so I can unit-test it without infrastructure.

## 4. Out of Scope (MVP)

- Ranked ladder, MMR display.
- Items, XP, level-up.
- 3+ player modes, spectator mode, replay viewer.
- Cosmetics, animations beyond simple FX.
- Mobile push notifications.
- Multi-region deployment.
- Anti-cheat beyond authoritative-server + WS payload validation.
- Surrender button.
