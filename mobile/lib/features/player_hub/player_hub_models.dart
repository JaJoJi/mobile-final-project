/// A ranked player row displayed by the Player Hub leaderboard.
class LeaderboardEntry {
  const LeaderboardEntry({
    required this.rank,
    required this.username,
    required this.rating,
  });

  final int rank;
  final String username;
  final int rating;
}

/// The leaderboard rows and the independently displayed current player.
class LeaderboardViewData {
  const LeaderboardViewData({
    required this.entries,
    required this.currentPlayer,
  });

  final List<LeaderboardEntry> entries;
  final LeaderboardEntry currentPlayer;
}

/// A player occupying one side of a private-room fixture.
class RoomPlayer {
  const RoomPlayer({
    required this.username,
    required this.crestLabel,
    required this.roleLabel,
  });

  final String username;
  final String crestLabel;
  final String roleLabel;
}

enum RoomFixtureStatus { waiting, joined, reconnecting }

/// The display state for a private-room fixture.
class RoomViewState {
  const RoomViewState({
    required this.roomCode,
    required this.host,
    required this.guest,
    required this.status,
  });

  final String roomCode;
  final RoomPlayer host;
  final RoomPlayer? guest;
  final RoomFixtureStatus status;
}
