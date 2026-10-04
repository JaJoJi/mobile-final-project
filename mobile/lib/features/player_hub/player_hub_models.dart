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
  LeaderboardViewData({
    required List<LeaderboardEntry> entries,
    required this.currentPlayer,
    this.total = 0,
    this.limit = 20,
    this.offset = 0,
  }) : entries = List.unmodifiable(entries);

  factory LeaderboardViewData.fromJson(Map<String, dynamic> json) {
    LeaderboardEntry parse(Map<String, dynamic> row) => LeaderboardEntry(
          rank: (row['rank'] as num).toInt(),
          username: row['username'] as String,
          rating: (row['rating'] as num).toInt(),
        );
    return LeaderboardViewData(
      entries: (json['entries'] as List<dynamic>)
          .map((row) => parse(Map<String, dynamic>.from(row as Map)))
          .toList(),
      currentPlayer: parse(Map<String, dynamic>.from(json['me'] as Map)),
      total: (json['total'] as num).toInt(),
      limit: (json['limit'] as num).toInt(),
      offset: (json['offset'] as num).toInt(),
    );
  }

  /// Immutable snapshot of leaderboard rows supplied to UI consumers.
  final List<LeaderboardEntry> entries;
  final LeaderboardEntry currentPlayer;
  final int total;
  final int limit;
  final int offset;
}

/// A player occupying one side of a private room.
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

/// The display state for a private room.
class RoomViewState {
  const RoomViewState({
    required this.roomCode,
    required this.host,
    required this.guest,
    required this.status,
    this.roomId,
    this.matchId,
  });

  factory RoomViewState.fromJson(
    Map<String, dynamic> json, {
    required String currentUserId,
    required String currentUsername,
  }) {
    final ownerId = json['ownerId'] as String;
    final guestId = json['guestId'] as String?;
    RoomPlayer player(String id, String role) => RoomPlayer(
          username: id == currentUserId
              ? currentUsername
              : 'ผู้เล่น ${id.substring(0, id.length < 8 ? id.length : 8)}',
          crestLabel: id == currentUserId
              ? (currentUsername.isEmpty
                  ? '?'
                  : currentUsername.substring(0, 1).toUpperCase())
              : '?',
          roleLabel: role,
        );
    return RoomViewState(
      roomId: json['roomId'] as String?,
      roomCode: json['code'] as String,
      host: player(
        ownerId,
        'เจ้าของห้อง',
      ),
      guest: guestId == null
          ? null
          : player(
              guestId,
              guestId == currentUserId ? 'คุณ · ผู้เข้าร่วม' : 'เข้าร่วมแล้ว',
            ),
      status: guestId == null
          ? RoomFixtureStatus.waiting
          : RoomFixtureStatus.joined,
      matchId: json['matchId'] as String?,
    );
  }

  final String roomCode;
  final RoomPlayer host;
  final RoomPlayer? guest;
  final RoomFixtureStatus status;
  final String? roomId;
  final String? matchId;
}
