# Task 1 brief — Typed fixture boundary

Implement only Task 1 of `docs/superpowers/plans/2026-09-23-player-hub-v2.md`.

Create `mobile/lib/features/player_hub/player_hub_models.dart` and
`mobile/lib/features/player_hub/player_hub_fixture_provider.dart`. Create
`mobile/test/features/player_hub/player_hub_fixture_provider_test.dart`.

Define immutable typed display models for the ranking and room fixture states:
`LeaderboardEntry`, `LeaderboardViewData`, `RoomPlayer`, `RoomViewState`, and
`RoomFixtureStatus { waiting, joined, reconnecting }`. Define
`leaderboardSourceProvider` as a `FutureProvider<LeaderboardViewData>` and
`roomFixtureProvider` as a `Provider<RoomViewState>`. Keep all fixture values
in `PlayerHubFixtures`, including the V2 HTML's seven leaderboard names and
ratings and `JaJoJi #28 / 1,240` as current player. The default room fixture
is a host waiting for an opponent with a null guest.

Write the tests first. They must verify seven leaderboard entries, current
player `JaJoJi` rank 28, and a host-waiting room with null guest. Do not
modify backend, WebSocket code, router, Profile, Room, or Leaderboard screen.
Run the focused test, `flutter analyze`, and commit with
`feat(player-hub): add typed display fixtures`.
