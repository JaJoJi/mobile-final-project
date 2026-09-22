import 'package:auto_chess_mobile/features/player_hub/player_hub_fixture_provider.dart';
import 'package:auto_chess_mobile/features/player_hub/player_hub_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('leaderboard fixture separates visible rows from current player', () {
    const data = PlayerHubFixtures.leaderboard;

    expect(data.entries, hasLength(7));
    expect(data.currentPlayer.username, 'JaJoJi');
    expect(data.currentPlayer.rank, 28);
  });

  test('room fixture starts with host waiting for an opponent', () {
    expect(PlayerHubFixtures.hostWaiting.status, RoomFixtureStatus.waiting);
    expect(PlayerHubFixtures.hostWaiting.guest, isNull);
  });
}
