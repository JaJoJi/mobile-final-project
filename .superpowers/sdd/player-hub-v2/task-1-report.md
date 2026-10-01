# Task 1 report — Typed fixture boundary

## Status

DONE

## Commit

`5916f74bf1b99285fe4ec718b15c7cc190beb80c` — `feat(player-hub): add typed display fixtures`

## Changed files

- `mobile/lib/features/player_hub/player_hub_models.dart`
  - Added immutable typed display models: `LeaderboardEntry`,
    `LeaderboardViewData`, `RoomPlayer`, and `RoomViewState`.
  - Added `RoomFixtureStatus { waiting, joined, reconnecting }`.
- `mobile/lib/features/player_hub/player_hub_fixture_provider.dart`
  - Added the centralized `PlayerHubFixtures` data set with the seven V2
    leaderboard rows, JaJoJi at rank 28/rating 1,240, and waiting/joined/
    reconnecting room display states.
  - Added `leaderboardSourceProvider` and `roomFixtureProvider`.
- `mobile/test/features/player_hub/player_hub_fixture_provider_test.dart`
  - Added fixture-boundary tests for the seven leaderboard rows/current player
    and host-waiting room without a guest.

## TDD evidence

1. Added the fixture test before any production file existed.
2. Ran the focused test. It failed as expected because both fixture/model
   imports and their symbols did not exist.
3. Added the typed models and fixture providers.
4. Re-ran the focused test; both tests passed.

## Commands and results

| Command | Result |
| --- | --- |
| `rtk flutter test --no-pub test/features/player_hub/player_hub_fixture_provider_test.dart` (pre-implementation) | Failed as expected: missing `player_hub_models.dart`, `player_hub_fixture_provider.dart`, and fixture symbols. |
| `rtk dart format lib/features/player_hub test/features/player_hub` | Formatted the new provider file. |
| `rtk flutter test --no-pub test/features/player_hub/player_hub_fixture_provider_test.dart` | Passed: 2 tests. |
| `rtk flutter analyze` | Passed: `No issues found!` |
| `rtk flutter test --no-pub --reporter compact` | Passed: 200 tests. |
| `rtk git diff --check` | Passed: no output. |

## Concerns

None for Task 1. The existing `.superpowers/` workflow directory remains
untracked and was intentionally excluded from the feature commit; this report
is stored there as required by the SDD workflow.

## Fix round 1 evidence

- `LeaderboardViewData` now creates an unmodifiable snapshot of its input
  entries, preventing UI consumers from mutating the public list boundary.
- The focused fixture test now locks all seven V2 leaderboard name/rating
  pairs, JaJoJi's rating of 1,240, and rejects a mutation attempt.
- `rtk flutter test --no-pub test/features/player_hub/player_hub_fixture_provider_test.dart`:
  passed (2 tests).
- `rtk flutter analyze`: passed (exit code 0).
