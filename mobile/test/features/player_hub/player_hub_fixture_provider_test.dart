import 'package:auto_chess_mobile/features/player_hub/player_hub_fixture_provider.dart';
import 'package:auto_chess_mobile/features/player_hub/player_hub_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('leaderboard fixture separates visible rows from current player', () {
    final data = PlayerHubFixtures.leaderboard;

    expect(data.entries, hasLength(7));
    expect(
      data.entries.map((entry) => (entry.username, entry.rating)),
      [
        ('MoonKnight', 1840),
        ('BlueRanger', 1795),
        ('StoneGuard', 1760),
        ('Astra', 1720),
        ('ForestMage', 1685),
        ('SilverPawn', 1630),
        ('NightOwl', 1605),
      ],
    );
    expect(data.currentPlayer.username, 'JaJoJi');
    expect(data.currentPlayer.rank, 28);
    expect(data.currentPlayer.rating, 1240);
    expect(
      () => data.entries.add(
        const LeaderboardEntry(rank: 8, username: 'TestPlayer', rating: 1),
      ),
      throwsUnsupportedError,
    );
  });

  test('room fixture starts with host waiting for an opponent', () {
    expect(PlayerHubFixtures.hostWaiting.status, RoomFixtureStatus.waiting);
    expect(PlayerHubFixtures.hostWaiting.guest, isNull);
  });
}
