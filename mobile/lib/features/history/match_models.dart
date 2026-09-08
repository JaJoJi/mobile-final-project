/// Client models for the match-history API (backend P0-BE-12).
///
/// * `GET /match/history` → `List<MatchHistoryEntry>`
/// * `GET /match/:matchId` → `MatchDetail`
library;

enum MatchOutcome { win, loss, tie }

MatchOutcome _outcomeFrom(String? winner) => switch (winner) {
      'self' => MatchOutcome.win,
      'opponent' => MatchOutcome.loss,
      _ => MatchOutcome.tie,
    };

class MatchHistoryEntry {
  const MatchHistoryEntry({
    required this.matchId,
    required this.opponentName,
    required this.outcome,
    required this.status,
    required this.rounds,
    required this.createdAt,
    required this.duration,
  });

  final String matchId;

  /// Opponent's username, or `null` if the account was deleted.
  final String? opponentName;
  final MatchOutcome outcome;

  /// `in_progress` · `finished` · `forfeited`.
  final String status;
  final int rounds;
  final DateTime createdAt;

  /// Match length; `null` while a match is still in progress.
  final Duration? duration;

  factory MatchHistoryEntry.fromJson(Map<String, dynamic> j) {
    final opp = j['opponent'];
    final secs = j['duration'];
    return MatchHistoryEntry(
      matchId: j['matchId'] as String,
      opponentName: opp is Map ? opp['username'] as String? : null,
      outcome: _outcomeFrom(j['winner'] as String?),
      status: j['status'] as String? ?? 'finished',
      rounds: (j['rounds'] as num?)?.toInt() ?? 0,
      createdAt:
          DateTime.tryParse(j['createdAt'] as String? ?? '')?.toLocal() ??
              DateTime.fromMillisecondsSinceEpoch(0),
      duration: secs is num ? Duration(seconds: secs.toInt()) : null,
    );
  }
}

class MatchPlayer {
  const MatchPlayer({required this.id, required this.name});

  final String id;
  final String? name;

  factory MatchPlayer.fromJson(Map<String, dynamic> j) => MatchPlayer(
        id: j['id'] as String,
        name: j['username'] as String?,
      );
}

class RoundSummary {
  const RoundSummary({
    required this.roundNumber,
    required this.eventCount,
    required this.winnerName,
  });

  final int roundNumber;
  final int eventCount;

  /// Derived from the round's `battle_end` event when present, else `null`.
  final String? winnerName;

  factory RoundSummary.fromJson(
    Map<String, dynamic> j, {
    required String? Function(String side) resolveSide,
  }) {
    final events = (j['events'] as List?) ?? const [];
    String? winner;
    for (final e in events) {
      if (e is Map && e['type'] == 'battle_end') {
        final side = e['winner'];
        winner = side is String ? resolveSide(side) : null;
        break;
      }
    }
    return RoundSummary(
      roundNumber: (j['roundNumber'] as num).toInt(),
      eventCount: events.length,
      winnerName: winner,
    );
  }
}

class MatchDetail {
  const MatchDetail({
    required this.matchId,
    required this.players,
    required this.winnerName,
    required this.status,
    required this.rounds,
    required this.createdAt,
    required this.finishedAt,
  });

  final String matchId;
  final List<MatchPlayer> players;
  final String? winnerName;
  final String status;
  final List<RoundSummary> rounds;
  final DateTime createdAt;
  final DateTime? finishedAt;

  Duration? get duration => finishedAt?.difference(createdAt);

  factory MatchDetail.fromJson(Map<String, dynamic> j) {
    final players = ((j['players'] as List?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(MatchPlayer.fromJson)
        .toList();

    // side ('p1'/'p2') → username, so a round's winner reads as a name.
    String? resolveSide(String side) {
      final idx = side == 'p1' ? 0 : (side == 'p2' ? 1 : -1);
      return idx >= 0 && idx < players.length ? players[idx].name : null;
    }

    final rounds = ((j['rounds'] as List?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .map((r) => RoundSummary.fromJson(r, resolveSide: resolveSide))
        .toList()
      ..sort((a, b) => a.roundNumber.compareTo(b.roundNumber));

    return MatchDetail(
      matchId: j['matchId'] as String,
      players: players,
      winnerName: j['winner'] as String?,
      status: j['status'] as String? ?? 'finished',
      rounds: rounds,
      createdAt:
          DateTime.tryParse(j['createdAt'] as String? ?? '')?.toLocal() ??
              DateTime.fromMillisecondsSinceEpoch(0),
      finishedAt:
          DateTime.tryParse(j['finishedAt'] as String? ?? '')?.toLocal(),
    );
  }
}
