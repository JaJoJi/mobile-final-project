/// `game:match:damage` — end-of-round result: who got wiped, HP before /
/// after, and the round winner.
///
/// Mirrors `docs/04-api-contracts.md` §2 — `game:match:damage`.
library;

/// Round winner as reported on the damage event.
enum RoundOutcome {
  p1,
  p2,
  tie;

  static RoundOutcome? fromJson(String? raw) => switch (raw) {
        'p1' => RoundOutcome.p1,
        'p2' => RoundOutcome.p2,
        'tie' => RoundOutcome.tie,
        _ => null,
      };
}

/// One side's damage ledger for the round.
class SideDamage {
  const SideDamage({
    required this.wiped,
    required this.tie,
    required this.hpBefore,
    required this.hpAfter,
    required this.damageApplied,
  });

  final bool wiped;
  final bool tie;
  final int hpBefore;
  final int hpAfter;
  final int damageApplied;

  factory SideDamage.fromJson(Map<String, dynamic> j) => SideDamage(
        wiped: j['wiped'] == true,
        tie: j['tie'] == true,
        hpBefore: (j['hpBefore'] as num?)?.toInt() ?? 0,
        hpAfter: (j['hpAfter'] as num?)?.toInt() ?? 0,
        damageApplied: (j['damageApplied'] as num?)?.toInt() ?? 0,
      );
}

class MatchDamageEvent {
  const MatchDamageEvent({
    required this.matchId,
    required this.round,
    required this.p1,
    required this.p2,
    required this.winner,
  });

  final String matchId;
  final int round;
  final SideDamage p1;
  final SideDamage p2;

  /// `null` when neither side has been eliminated yet and it wasn't a tie.
  final RoundOutcome? winner;

  factory MatchDamageEvent.fromJson(Map<String, dynamic> j) {
    final damage = (j['damage'] as Map?)?.cast<String, dynamic>() ?? const {};
    Map<String, dynamic> side(String k) =>
        (damage[k] as Map?)?.cast<String, dynamic>() ?? const {};
    return MatchDamageEvent(
      matchId: j['matchId'] as String? ?? '',
      round: (j['round'] as num?)?.toInt() ?? 0,
      p1: SideDamage.fromJson(side('p1')),
      p2: SideDamage.fromJson(side('p2')),
      winner: RoundOutcome.fromJson(j['winner'] as String?),
    );
  }

  @override
  String toString() =>
      'MatchDamageEvent(match: $matchId, round: $round, winner: $winner)';
}
