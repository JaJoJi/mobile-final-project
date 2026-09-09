/// `game:match:phase` — sent on every phase change (match start or
/// transition). Drives the top-level in-game screen state machine.
///
/// Mirrors `docs/04-api-contracts.md` §2 — `game:match:phase`.
library;

/// The server's phase for the current round.
enum GamePhase {
  /// Buy / sell / place units, then press ready.
  shopPlace,

  /// Combat is running / being played back.
  battle,

  /// Round damage applied, brief pause before the next `shop_place`.
  resolved,

  /// Match over — a `game:match:end` has been (or is about to be) sent.
  finished,

  /// A phase string this build doesn't recognise.
  unknown;

  static GamePhase fromJson(String? raw) => switch (raw) {
        'shop_place' => GamePhase.shopPlace,
        'battle' => GamePhase.battle,
        'resolved' => GamePhase.resolved,
        'finished' => GamePhase.finished,
        _ => GamePhase.unknown,
      };
}

/// Per-player public state carried on a phase event.
class PhasePlayer {
  const PhasePlayer({
    required this.id,
    required this.hp,
    required this.gold,
    required this.ready,
  });

  final String id;
  final int hp;
  final int gold;
  final bool ready;

  factory PhasePlayer.fromJson(Map<String, dynamic> j) => PhasePlayer(
        id: j['id'] as String? ?? '',
        hp: (j['hp'] as num?)?.toInt() ?? 0,
        gold: (j['gold'] as num?)?.toInt() ?? 0,
        ready: j['ready'] == true,
      );
}

class MatchPhaseEvent {
  const MatchPhaseEvent({
    required this.matchId,
    required this.phase,
    required this.round,
    required this.timer,
    required this.players,
  });

  final String matchId;
  final GamePhase phase;
  final int round;

  /// Seconds remaining in this phase (`0` for instantaneous transitions).
  final int timer;
  final List<PhasePlayer> players;

  factory MatchPhaseEvent.fromJson(Map<String, dynamic> j) {
    final raw = (j['players'] as List?) ?? const [];
    return MatchPhaseEvent(
      matchId: j['matchId'] as String? ?? '',
      phase: GamePhase.fromJson(j['phase'] as String?),
      round: (j['round'] as num?)?.toInt() ?? 0,
      timer: (j['timer'] as num?)?.toInt() ?? 0,
      players: raw
          .whereType<Map<String, dynamic>>()
          .map(PhasePlayer.fromJson)
          .toList(growable: false),
    );
  }

  @override
  String toString() =>
      'MatchPhaseEvent(match: $matchId, phase: $phase, round: $round, '
      'timer: $timer)';
}
