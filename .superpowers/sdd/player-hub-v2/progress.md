# SDD ledger — plan: docs/superpowers/plans/2026-09-23-player-hub-v2.md

## Pre-flight interface scan

| Tasks / interface | Producer → consumer | Finding / ruling |
| --- | --- | --- |
| 1 → 3 | `LeaderboardViewData` + `leaderboardSourceProvider` → Leaderboard screen | Consistent. Task 1 provider is a `FutureProvider`; Task 3 invalidates it for retry. |
| 1 → 4 | `RoomViewState`, `RoomFixtureStatus`, `roomFixtureProvider` → Room screens | Consistent. Fixture source is read-only and tests override it. |
| 2 → 3 | `PlayerHubShell`, `PlayerCrest` → Leaderboard | Consistent. Task 2 establishes shared visual shell before Task 3. |
| 2 → 5 | Profile CTA → `/leaderboard`; navigation → `/lobby`, `/history` | Consistent. Task 3 creates the target route before Task 5 exposes lobby actions. |
| 3 → 5 | `LeaderboardScreen.path` → Lobby action | Consistent. Task 5 follows Task 3. |
| 4 → 5 | room route paths → Lobby actions | Consistent. Task 5 follows Task 4. |
| Task 2 itself | Existing Profile API/settings vs. V2 HTML hierarchy | Consistent. Settings remain subordinate after the HTML-described profile content to preserve existing required behavior. |
| Task 4 itself | Fixture `K7M2Q9` join success vs. no network operations | Consistent. Success is explicitly local presentation only. |

## Task status

- [x] Task 1 — Typed fixture boundary
- [x] Task 2 — Shared V2 shell and exact Profile hierarchy
- [x] Task 3 — Leaderboard route and visual states
- [x] Task 4 — Create Room and Join Room fixture routes
- [x] Task 5 — Discoverability and complete regression verification

Task 1: fix round 1/5 (2 addressed, 0 open — immutable leaderboard entries; exact V2 fixture assertions; commits 5916f74..c5d8e20)
Task 1: complete (commits 4530589..c5d8e20, review clean)
Task 2: complete (Profile hierarchy, settings, and narrow-layout coverage; commits a5e4bd4..d676161)
Task 3: complete (Leaderboard route, loading/error/empty/self-rank states; commits d7de623..ecf5116)
Task 4: complete (Create/Join Room fixture routes and responsive tests; commit 7e6c370)
Task 5: complete (Lobby discoverability with matchmaking preserved; commit 5323f27)

Final verification: `rtk flutter analyze` clean; full Flutter suite passed 219 tests; `rtk git diff --check` clean.
