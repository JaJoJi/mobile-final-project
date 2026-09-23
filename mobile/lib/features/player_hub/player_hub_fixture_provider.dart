import 'package:auto_chess_mobile/features/player_hub/player_hub_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Temporary display data for Player Hub screens until their API contracts exist.
abstract final class PlayerHubFixtures {
  static final leaderboard = LeaderboardViewData(
    entries: [
      LeaderboardEntry(rank: 1, username: 'MoonKnight', rating: 1840),
      LeaderboardEntry(rank: 2, username: 'BlueRanger', rating: 1795),
      LeaderboardEntry(rank: 3, username: 'StoneGuard', rating: 1760),
      LeaderboardEntry(rank: 4, username: 'Astra', rating: 1720),
      LeaderboardEntry(rank: 5, username: 'ForestMage', rating: 1685),
      LeaderboardEntry(rank: 6, username: 'SilverPawn', rating: 1630),
      LeaderboardEntry(rank: 7, username: 'NightOwl', rating: 1605),
    ],
    currentPlayer: LeaderboardEntry(rank: 28, username: 'JaJoJi', rating: 1240),
  );

  static const _host = RoomPlayer(
    username: 'JaJoJi',
    crestLabel: 'JJ',
    roleLabel: 'คุณ · เจ้าของห้อง',
  );

  static const _guest = RoomPlayer(
    username: 'Astra',
    crestLabel: 'AS',
    roleLabel: 'เข้าร่วมแล้ว',
  );

  static const hostWaiting = RoomViewState(
    roomCode: 'K7M2Q9',
    host: _host,
    guest: null,
    status: RoomFixtureStatus.waiting,
  );

  static const joined = RoomViewState(
    roomCode: 'K7M2Q9',
    host: _host,
    guest: _guest,
    status: RoomFixtureStatus.joined,
  );

  static const reconnecting = RoomViewState(
    roomCode: 'K7M2Q9',
    host: _host,
    guest: _guest,
    status: RoomFixtureStatus.reconnecting,
  );
}

final leaderboardSourceProvider = FutureProvider<LeaderboardViewData>(
  (ref) async => PlayerHubFixtures.leaderboard,
);

final roomFixtureProvider =
    Provider<RoomViewState>((ref) => PlayerHubFixtures.hostWaiting);
