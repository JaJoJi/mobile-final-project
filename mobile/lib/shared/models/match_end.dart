/// `game:match:end` — the match is over.
///
/// Mirrors `docs/04-api-contracts.md` §2 — `game:match:end`.
library;

/// Why the match ended.
enum MatchEndReason {
  /// A player's HP hit zero (the normal path).
  hpZero,

  /// A player conceded.
  forfeit,

  /// A player dropped and did not reconnect in time.
  disconnect,

  unknown;

  static MatchEndReason fromJson(String? raw) => switch (raw) {
        'hp_zero' => MatchEndReason.hpZero,
        'forfeit' => MatchEndReason.forfeit,
        'disconnect' => MatchEndReason.disconnect,
        _ => MatchEndReason.unknown,
      };
}

/// Final HP / gold for one side.
class FinalPlayerState {
  const FinalPlayerState({required this.hp, required this.gold});

  final int hp;
  final int gold;

  factory FinalPlayerState.fromJson(Map<String, dynamic> j) => FinalPlayerState(
        hp: (j['hp'] as num?)?.toInt() ?? 0,
        gold: (j['gold'] as num?)?.toInt() ?? 0,
      );
}

class MatchEndEvent {
  const MatchEndEvent({
    required this.matchId,
    required this.winnerId,
    required this.reason,
    required this.finalP1,
    required this.finalP2,
  });

  final String matchId;

  /// `null` on a double knockout (both sides at 0 HP).
  final String? winnerId;
  final MatchEndReason reason;
  final FinalPlayerState finalP1;
  final FinalPlayerState finalP2;

  bool get isDraw => winnerId == null;

  /// `true` when [userId] is the winner. `false` for the loser or a draw.
  bool didWin(String userId) => winnerId != null && winnerId == userId;

  factory MatchEndEvent.fromJson(Map<String, dynamic> j) {
    final fin = (j['final'] as Map?)?.cast<String, dynamic>() ?? const {};
    Map<String, dynamic> side(String k) =>
        (fin[k] as Map?)?.cast<String, dynamic>() ?? const {};
    return MatchEndEvent(
      matchId: j['matchId'] as String? ?? '',
      winnerId: j['winnerId'] as String?,
      reason: MatchEndReason.fromJson(j['reason'] as String?),
      finalP1: FinalPlayerState.fromJson(side('p1')),
      finalP2: FinalPlayerState.fromJson(side('p2')),
    );
  }

  @override
  String toString() =>
      'MatchEndEvent(match: $matchId, winner: ${winnerId ?? "draw"}, '
      'reason: $reason)';
}
