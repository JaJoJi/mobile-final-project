# Project Backlog

> Stack: Flutter (mobile) + Nest.js (backend) + TypeORM + PostgreSQL + Redis. University MVP, 3 people × 1 month.
> Reference docs: `docs/01-game-design.md`, `docs/02-requirements.md`, `docs/03-architecture.md`, `docs/04-api-contracts.md`, `docs/05-combat-spec.md`.
> Skill (AI agent conventions): `.opencode/skills/auto-chess-game/SKILL.md`.

This document is the **summary index** of the backlog. The canonical source of truth lives in **GitHub Issues** — every row below links to its issue, where the full body (What / Why / Setup steps / Done when / Size / Files / Example / Design notes / References) lives.

GitHub Project board: <https://github.com/users/JaJoJi/projects/3> (Backlog / In Progress / Review / Done).

---

## Implementation status

### Done ✅
- infra (`docker-compose`, 7 services, nginx `least_conn`, PG primary+replica, redis, pgadmin)
- backend: `auth/`, `user/`, `common/jwt-auth`, `common/health`, `redis/` (basic), `migrations/1736…-CreateUsers.ts`, `data-source.ts`
- mobile: `LoginScreen`, `RegisterScreen`, `HealthScreen`, `ApiClient`, `AuthRepository`, `AppConfig`
- GitHub: 12 labels created (`area:*` × 4, `type:*` × 5, `priority:*` × 3 used in backlog)
- GitHub: GitHub Project **Auto Chess Development (#3)** created with 4 columns (Backlog / In Progress / Review / Done)
- Backlog: **36 issues open** (14 P0-BE setup + logic + 7 P0-FE + 4 P1 + 11 P3), **20 issues closed** (14 out-of-MVP scope P2-* + 6 old logic superseded)
- Project board populated: **32 items in Backlog, 4 in In Progress** (per 2026-09-07 audit)

### Not done ❌
- no WebSocket gateway wired up, no matchmaking logic, no combat engine, no shop, no match lifecycle, no Pub/Sub bridge, no tests, no CI
- All 36 open issues are already in the project board; just need to be worked through

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
|  | `priority:p2` | Post-MVP / out-of-scope (cut from current backlog; re-add when needed). |
|  | `priority:p3` | Quality / NFR / dev-experience. |

> Hard rule from `SKILL.md §4`: **all combat math on backend**. Any ticket that puts combat logic in Flutter is a violation — redirect.

---

## Backlog summary (36 issues)

| Phase | Priority | Area | Count | Issues |
|---|---|---|---|---|
| **Phase 0 — Setup** | P0 | backend | 8 | P0-BE-01..08 |
| **Phase 1 — Logic** | P0 | backend | 6 | P0-BE-09..14 |
|  | P0 | frontend | 7 | P0-FE-00..06 |
|  | P1 | backend | 2 | P1-BE-01..02 |
|  | P1 | frontend | 2 | P1-FE-01..02 |
|  | P3 | backend | 3 | P3-BE-01..03 |
|  | P3 | frontend | 2 | P3-FE-01..02 |
|  | P3 | devops | 6 | P3-DO-01..06 |
| **Total** | | | **36** | |

All 36 issues are in the GitHub Project board (32 Backlog + 4 In Progress as of 2026-09-07).

Full detail lives in the GitHub issues linked below.

---

## P0 — Backend Setup (Phase 0) — 8 tickets

> **Do these FIRST.** They are the infrastructure plumbing (connections, modules, scripts, entities) that every other backend ticket depends on.

| ID | Issue (GitHub) | One-liner | Labels |
|---|---|---|---|
| P0-BE-01 | [#142](https://github.com/JaJoJi/mobile-final-project/issues/142) | Set up Redis module with Lua script loader | `area:backend` `type:infra` `priority:p0` |
| P0-BE-02 | [#143](https://github.com/JaJoJi/mobile-final-project/issues/143) | Set up TypeORM with entity registration + migration runner | `area:backend` `type:infra` `priority:p0` |
| P0-BE-03 | [#144](https://github.com/JaJoJi/mobile-final-project/issues/144) | Set up BullMQ queue + worker processor module | `area:backend` `type:infra` `priority:p0` |
| P0-BE-04 | [#145](https://github.com/JaJoJi/mobile-final-project/issues/145) | Set up WebSocket gateway module (Nest + socket.io) | `area:backend` `type:infra` `priority:p0` |
| P0-BE-05 | [#146](https://github.com/JaJoJi/mobile-final-project/issues/146) | Set up Pub/Sub cross-instance bridge | `area:backend` `type:infra` `priority:p0` |
| P0-BE-06 | [#147](https://github.com/JaJoJi/mobile-final-project/issues/147) | Write Lua scripts (atomic primitives: phase_flip, combat_done, action_log, match_pair) | `area:backend` `type:infra` `priority:p0` |
| P0-BE-07 | [#148](https://github.com/JaJoJi/mobile-final-project/issues/148) | Create Match + MatchRound entities + CreateMatches migration | `area:backend` `type:feature` `priority:p0` |
| P0-BE-08 | [#149](https://github.com/JaJoJi/mobile-final-project/issues/149) | Set up DTOs + class-validator schemas for all WS payloads | `area:backend` `type:chore` `priority:p0` |

## P0 — Backend Logic (Phase 1) — 6 tickets

> **Do these AFTER Phase 0 is done.** Each depends on the setup tickets above.

| ID | Issue (GitHub) | One-liner | Labels |
|---|---|---|---|
| P0-BE-09 | [#150](https://github.com/JaJoJi/mobile-final-project/issues/150) | Implement Cycle Processor (combat engine) | `area:backend` `type:feature` `priority:p0` |
| P0-BE-10 | [#151](https://github.com/JaJoJi/mobile-final-project/issues/151) | Implement WS event handlers (Real-time Gateway) | `area:backend` `type:feature` `priority:p0` |
| P0-BE-11 | [#152](https://github.com/JaJoJi/mobile-final-project/issues/152) | Implement Matchmaking logic | `area:backend` `type:feature` `priority:p0` |
| P0-BE-12 | [#153](https://github.com/JaJoJi/mobile-final-project/issues/153) | Implement Match Lifecycle service | `area:backend` `type:feature` `priority:p0` |
| P0-BE-13 | [#154](https://github.com/JaJoJi/mobile-final-project/issues/154) | Implement Round Orchestrator | `area:backend` `type:feature` `priority:p0` |
| P0-BE-14 | [#155](https://github.com/JaJoJi/mobile-final-project/issues/155) | Implement Shop System | `area:backend` `type:feature` `priority:p0` |

## P0 — Frontend (7, includes new Design Spec)

| ID | Issue (GitHub) | One-liner | Labels |
|---|---|---|---|
| P0-FE-00 | [#106](https://github.com/JaJoJi/mobile-final-project/issues/106) | **Design Spec** — Define screens, color tokens, typography, component states | `area:frontend` `type:feature` `priority:p0` |
| P0-FE-01 | [#107](https://github.com/JaJoJi/mobile-final-project/issues/107) | Wire up the WebSocket client + Dart data types | `area:frontend` `type:feature` `priority:p0` |
| P0-FE-02 | [#108](https://github.com/JaJoJi/mobile-final-project/issues/108) | Auto-refresh tokens + restore session on app launch | `area:frontend` `type:chore` `priority:p0` |
| P0-FE-03 | [#109](https://github.com/JaJoJi/mobile-final-project/issues/109) | Find-match screen with queue, profile, and logout | `area:frontend` `type:feature` `priority:p0` |
| P0-FE-04 | [#110](https://github.com/JaJoJi/mobile-final-project/issues/110) | In-game screen: shop, board, ready button, result overlay | `area:frontend` `type:feature` `priority:p0` |
| P0-FE-05 | [#111](https://github.com/JaJoJi/mobile-final-project/issues/111) | Animate the battle events the server sends | `area:frontend` `type:feature` `priority:p0` |
| P0-FE-06 | [#112](https://github.com/JaJoJi/mobile-final-project/issues/112) | Reusable UI building blocks (timer, HP bar, unit card) | `area:frontend` `type:chore` `priority:p0` |

> **Why P0-FE-00 matters**: every other P0 frontend ticket depends on a consistent design spec. Without it, every screen looks slightly different and the app feels like 3 different apps. Dev who picks this up **produces** the spec — it's the deliverable.

## P1 — Backend (2)

| ID | Issue (GitHub) | One-liner | Labels |
|---|---|---|---|
| P1-BE-01 | [#113](https://github.com/JaJoJi/mobile-final-project/issues/113) | Make the live system production-safe (rate limits, logs, errors) | `area:backend` `type:chore` `priority:p1` |
| P1-BE-02 | [#114](https://github.com/JaJoJi/mobile-final-project/issues/114) | Reject malformed game messages at the door | `area:backend` `type:feature` `priority:p1` |

## P1 — Frontend (2)

| ID | Issue (GitHub) | One-liner | Labels |
|---|---|---|---|
| P1-FE-01 | [#115](https://github.com/JaJoJi/mobile-final-project/issues/115) | Past-matches list + detail screen | `area:frontend` `type:feature` `priority:p1` |
| P1-FE-02 | [#116](https://github.com/JaJoJi/mobile-final-project/issues/116) | My-account screen with theme + reconnect toggle | `area:frontend` `type:feature` `priority:p1` |

## P3 — Backend (3)

| ID | Issue (GitHub) | One-liner | Labels |
|---|---|---|---|
| P3-BE-01 | [#131](https://github.com/JaJoJi/mobile-final-project/issues/131) | Write tests for the combat engine (>=90% coverage) | `area:backend` `type:test` `priority:p3` |
| P3-BE-02 | [#132](https://github.com/JaJoJi/mobile-final-project/issues/132) | Test the Lua scripts + shop RNG determinism | `area:backend` `type:test` `priority:p3` |
| P3-BE-03 | [#133](https://github.com/JaJoJi/mobile-final-project/issues/133) | Lint, OpenAPI, security headers, graceful shutdown | `area:backend` `type:chore` `priority:p3` |

## P3 — Frontend (2)

| ID | Issue (GitHub) | One-liner | Labels |
|---|---|---|---|
| P3-FE-01 | [#134](https://github.com/JaJoJi/mobile-final-project/issues/134) | Smoke tests for every Flutter screen | `area:frontend` `type:test` `priority:p3` |
| P3-FE-02 | [#135](https://github.com/JaJoJi/mobile-final-project/issues/135) | Lint, error logger, accessibility pass | `area:frontend` `type:chore` `priority:p3` |

## P3 — DevOps (6)

| ID | Issue (GitHub) | One-liner | Labels |
|---|---|---|---|
| P3-DO-01 | [#136](https://github.com/JaJoJi/mobile-final-project/issues/136) | GitHub Actions: lint + build + test on every PR | `area:devops` `type:infra` `priority:p3` |
| P3-DO-02 | [#137](https://github.com/JaJoJi/mobile-final-project/issues/137) | Auto-publish Nest images to GHCR on main | `area:devops` `type:infra` `priority:p3` |
| P3-DO-03 | [#138](https://github.com/JaJoJi/mobile-final-project/issues/138) | Prometheus + Grafana + Loki | `area:devops` `type:infra` `priority:p3` |
| P3-DO-04 | [#139](https://github.com/JaJoJi/mobile-final-project/issues/139) | Strong secrets, HTTPS, pgBouncer, backups | `area:devops` `type:infra` `priority:p3` |
| P3-DO-05 | [#140](https://github.com/JaJoJi/mobile-final-project/issues/140) | k6 load test to prove NFRs | `area:devops` `type:test` `priority:p3` |
| P3-DO-06 | [#141](https://github.com/JaJoJi/mobile-final-project/issues/141) | Templates, CODEOWNERS, Dependabot, pre-commit, badges | `area:devops` `type:chore` `priority:p3` |

---

## Out of MVP scope (closed — re-open if needed)

All `priority:p2` tickets were closed on 2026-09-07 as "out of scope for 1-month MVP". Reopen any of these if post-launch demand justifies them:

| Closed ID | Issue | One-liner | Reason closed |
|---|---|---|---|
| ~~P2-BE-01~~ | [#117](https://github.com/JaJoJi/mobile-final-project/issues/117) | API to fetch a match's events for replay | MVP — no replay viewer |
| ~~P2-BE-02~~ | [#118](https://github.com/JaJoJi/mobile-final-project/issues/118) | Player can surrender | MVP — forced playout is OK |
| ~~P2-BE-03~~ | [#119](https://github.com/JaJoJi/mobile-final-project/issues/119) | Match players by rating | MVP — FIFO works |
| ~~P2-BE-04~~ | [#120](https://github.com/JaJoJi/mobile-final-project/issues/120) | Items / XP / Level-up | MVP — major content expansion |
| ~~P2-BE-05~~ | [#121](https://github.com/JaJoJi/mobile-final-project/issues/121) | 3+ players + spectators | MVP — 2-player only |
| ~~P2-BE-06~~ | [#122](https://github.com/JaJoJi/mobile-final-project/issues/122) | Rotate refresh tokens | MVP — long-lived refresh is fine |
| ~~P2-BE-07~~ | [#123](https://github.com/JaJoJi/mobile-final-project/issues/123) | Push notifications | MVP — WS connection suffices |
| ~~P2-BE-08~~ | [#124](https://github.com/JaJoJi/mobile-final-project/issues/124) | Multi-region deployment | MVP — single region |
| ~~P2-FE-01~~ | [#125](https://github.com/JaJoJi/mobile-final-project/issues/125) | Surrender button | MVP — paired with #118 |
| ~~P2-FE-02~~ | [#126](https://github.com/JaJoJi/mobile-final-project/issues/126) | Replay viewer | MVP — no replay data |
| ~~P2-FE-03~~ | [#127](https://github.com/JaJoJi/mobile-final-project/issues/127) | Skins + polish animations | MVP — cosmetic |
| ~~P2-FE-04~~ | [#128](https://github.com/JaJoJi/mobile-final-project/issues/128) | Spectator mode UI | MVP — paired with #121 |
| ~~P2-FE-05~~ | [#129](https://github.com/JaJoJi/mobile-final-project/issues/129) | iOS support | MVP — Android/Chrome only |
| ~~P2-FE-06~~ | [#130](https://github.com/JaJoJi/mobile-final-project/issues/130) | Multi-language | MVP — English only |
| ~~P2-FE-07~~ | [#87](https://github.com/JaJoJi/mobile-final-project/issues/87) | Push notification opt-in | MVP — paired with #123 |

The 6 old logic tickets (`#100`–`#105`) were closed on 2026-09-07 as "Superseded by new setup + logic structure (P0-BE-01..14)". See the new tickets for the canonical implementation.

---

## Recommended execution order (P0)

```
# Phase 0 — Backend Setup (do these first; ~½-1 day each; can be parallelized)
P0-BE-01  Set up Redis module with Lua script loader
P0-BE-02  Set up TypeORM with entity registration + migration runner
P0-BE-03  Set up BullMQ queue + worker processor module
P0-BE-04  Set up WebSocket gateway module (Nest + socket.io)
P0-BE-05  Set up Pub/Sub cross-instance bridge
P0-BE-06  Write Lua scripts (atomic primitives)
P0-BE-07  Create Match + MatchRound entities + CreateMatches migration
P0-BE-08  Set up DTOs + class-validator schemas for all WS payloads

# Phase 1 — Backend Logic (after Phase 0; ~1-2 days each except P0-BE-09 + P0-BE-13 which are XL)
P0-BE-09  Implement Cycle Processor (combat engine)
P0-BE-10  Implement WS event handlers (Real-time Gateway)
P0-BE-11  Implement Matchmaking logic
P0-BE-12  Implement Match Lifecycle service
P0-BE-13  Implement Round Orchestrator
P0-BE-14  Implement Shop System

# Frontend (can start in parallel with backend)
P0-FE-00  Design Spec (blocks all other UI work — should land first)
P0-FE-01  WS & Models Foundation
P0-FE-02  Auth Flow Hardening
P0-FE-06  Design System / Shared Widgets
P0-FE-03  Lobby Page
P0-FE-04  Match Page
P0-FE-05  Battle Animation System
```

---

## Dependency graph

```
                    ┌─────────────────────────────────────┐
                    │  PHASE 0 — SETUP                    │
                    │  (do these first, in order)         │
                    └─────────────────────────────────────┘
                                       │
  ┌──────────┬──────────┬──────────┬────┴─────┬──────────┬──────────┬──────────┐
  ▼          ▼          ▼          ▼          ▼          ▼          ▼
P0-BE-01  P0-BE-02  P0-BE-03  P0-BE-04  P0-BE-05  P0-BE-06  P0-BE-07  P0-BE-08
Redis      TypeORM   BullMQ    WS mod    Pub/Sub   Lua       Match     DTOs
mod +Lua   +migrate  +worker   +JWT      bridge    scripts   entities  schemas
                                       │
                                       ▼
                    ┌─────────────────────────────────────┐
                    │  PHASE 1 — GAME LOGIC               │
                    │  (do these after Phase 0)           │
                    └─────────────────────────────────────┘
                                       │
   ┌───────────┬───────────┬───────────┬───────────┬───────────┬───────────┐
   ▼           ▼           ▼           ▼           ▼           ▼
P0-BE-09    P0-BE-10    P0-BE-11    P0-BE-12    P0-BE-13    P0-BE-14
Combat      WS          Match-     Match       Round       Shop
Engine      Handlers    making      Lifecycle   Orch.       System
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

Project: <https://github.com/users/JaJoJi/projects/3>
