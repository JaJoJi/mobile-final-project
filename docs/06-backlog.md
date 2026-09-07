# Project Backlog

> Stack: Flutter (mobile) + Nest.js (backend) + TypeORM + PostgreSQL + Redis. University MVP, 3 people × 1 month.
> Reference docs: `docs/01-game-design.md`, `docs/02-requirements.md`, `docs/03-architecture.md`, `docs/04-api-contracts.md`, `docs/05-combat-spec.md`.
> Skill (AI agent conventions): `.opencode/skills/auto-chess-game/SKILL.md`.

This document is the **summary index** of the backlog. The canonical source of truth lives in **GitHub Issues** — every row below links to its issue, where the full body (What / Why / Done when / Size / Files / Example / Design notes / References) lives.

GitHub Project board: <https://github.com/users/JaJoJi/projects/3> (Backlog / In Progress / Review / Done).

---

## Implementation status

### Done ✅
- infra (`docker-compose`, 7 services, nginx `least_conn`, PG primary+replica, redis, pgadmin)
- backend: `auth/`, `user/`, `common/jwt-auth`, `common/health`, `redis/` (basic), `migrations/1736…-CreateUsers.ts`, `data-source.ts`
- mobile: `LoginScreen`, `RegisterScreen`, `HealthScreen`, `ApiClient`, `AuthRepository`, `AppConfig`
- GitHub: 12 labels created (`area:*` × 4, `type:*` × 5, `priority:*` × 4)
- GitHub: GitHub Project **Auto Chess Development (#3)** created with 4 columns (Backlog / In Progress / Review / Done)
- Backlog: **28 issues open** (13 P0 + 4 P1 + 11 P3), **14 issues closed** as out-of-MVP scope (P2-*)

### Not done ❌
- no WebSocket, no matchmaking, no combat engine, no shop, no match lifecycle, no Pub/Sub, no tests, no CI
- 28 issues still need to be added to the project's Backlog column (paste issue URLs into the project's **+ Add items** dialog — your PAT lacks `Projects: Write` scope so the agent cannot do this for you)

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

## Backlog summary (28 issues)

| Priority | Area | Count | Issues |
|---|---|---|---|
| P0 | backend | 6 | P0-BE-01..06 |
| P0 | frontend | 7 | P0-FE-00..06 (includes new Design Spec) |
| P1 | backend | 2 | P1-BE-01..02 |
| P1 | frontend | 2 | P1-FE-01..02 |
| P3 | backend | 3 | P3-BE-01..03 |
| P3 | frontend | 2 | P3-FE-01..02 |
| P3 | devops | 6 | P3-DO-01..06 |
| **Total** | | **28** | |

Full detail lives in the GitHub issues linked below.

---

## P0 — Backend (6)

| ID | Issue (GitHub) | One-liner | Labels |
|---|---|---|---|
| P0-BE-01 | [#100](https://github.com/JaJoJi/mobile-final-project/issues/100) | Push game updates to clients over WebSocket | `area:backend` `type:infra` `priority:p0` |
| P0-BE-02 | [#101](https://github.com/JaJoJi/mobile-final-project/issues/101) | Pair up waiting players into a match | `area:backend` `type:feature` `priority:p0` |
| P0-BE-03 | [#102](https://github.com/JaJoJi/mobile-final-project/issues/102) | Save matches to the DB so history + ratings work | `area:backend` `type:feature` `priority:p0` |
| P0-BE-04 | [#103](https://github.com/JaJoJi/mobile-final-project/issues/103) | Drive the round loop: shop → battle → damage → next round | `area:backend` `type:feature` `priority:p0` |
| P0-BE-05 | [#104](https://github.com/JaJoJi/mobile-final-project/issues/104) | Run auto-chess battles on the server (deterministic) | `area:backend` `type:feature` `priority:p0` |
| P0-BE-06 | [#105](https://github.com/JaJoJi/mobile-final-project/issues/105) | Generate the per-round shop and handle buy/sell/refresh/fuse | `area:backend` `type:feature` `priority:p0` |

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

---

## Recommended execution order (P0)

```
# Backend
P0-BE-05  Cycle Processor (combat engine — pure functions, easiest to test in isolation)
P0-BE-01  Real-time Gateway (WS + Pub/Sub + Lua primitives)
P0-BE-03  Match Lifecycle Service (entity, create, persist, history, ELO)
P0-BE-04  Round Orchestrator (phase machine, combat-lock, timers)
P0-BE-02  Matchmaking System (depends on Match + WS)
P0-BE-06  Shop System

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
