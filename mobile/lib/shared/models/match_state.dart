/// `game:match:state` — sent when a roster changes, both teams lock for
/// battle, or an active match reconnects. Each client sees its own full roster
/// plus a stable previous-round scouting snapshot. A separate live opponent
/// board is present only after both teams are locked for battle.
///
/// Mirrors `docs/04-api-contracts.md` §2 — `game:match:state`.
library;

import 'unit.dart';

/// `'p1'` or `'p2'` — which side the receiving client controls.
enum MatchSide {
  p1,
  p2;

  static MatchSide fromJson(String? raw) =>
      raw == 'p2' ? MatchSide.p2 : MatchSide.p1;

  String toJson() => name;
}

/// The caller's own roster: board (9 slots), bench (8 slots), gold, hp.
class PlayerRoster {
  const PlayerRoster({
    this.username,
    required this.board,
    required this.bench,
    required this.gold,
    required this.hp,
  });

  /// 9 slots, row-major (`col = slot % 3`, `row = slot ~/ 3`). `null` = empty.
  final List<Unit?> board;
  final String? username;

  /// 8 slots. `null` = empty.
  final List<Unit?> bench;
  final int gold;
  final int hp;

  factory PlayerRoster.fromJson(Map<String, dynamic> j) => PlayerRoster(
        username: j['username'] as String?,
        board: Unit.slotsFromJson(j['board'], 9),
        bench: Unit.slotsFromJson(j['bench'], 8),
        gold: (j['gold'] as num?)?.toInt() ?? 0,
        hp: (j['hp'] as num?)?.toInt() ?? 0,
      );
}

/// One redacted opponent board cell — archetype + star only, no HP.
class OpponentUnit {
  const OpponentUnit({required this.unitId, required this.star});

  final UnitId unitId;
  final int star;

  factory OpponentUnit.fromJson(Map<String, dynamic> j) => OpponentUnit(
        unitId: UnitId.fromJson(j['unitId'] as String?),
        star: (j['star'] as num?)?.toInt() ?? 0,
      );
}

/// What the caller is allowed to know about the opponent.
class OpponentView {
  const OpponentView({
    this.username,
    required this.gold,
    required this.hp,
    required this.scoutRound,
    required this.boardSummary,
    required this.battleBoardSummary,
  });

  final int gold;
  final String? username;
  final int hp;

  /// The completed round that [boardSummary] was captured from.
  /// `null` in round one, before any scouting information exists.
  final int? scoutRound;

  /// Stable 9-slot snapshot from [scoutRound]. Never changes during planning.
  final List<OpponentUnit?> boardSummary;

  /// Live board sent only after both teams are locked for battle.
  /// Kept separate so scouting data can never drive battle playback.
  final List<OpponentUnit?>? battleBoardSummary;

  factory OpponentView.fromJson(Map<String, dynamic> j) {
    final raw = (j['boardSummary'] as List<dynamic>?) ?? const [];
    return OpponentView(
      username: j['username'] as String?,
      gold: (j['gold'] as num?)?.toInt() ?? 0,
      hp: (j['hp'] as num?)?.toInt() ?? 0,
      scoutRound: (j['scoutRound'] as num?)?.toInt(),
      boardSummary: _opponentSlots(raw),
      battleBoardSummary: j['battleBoardSummary'] is List
          ? _opponentSlots(j['battleBoardSummary'] as List<dynamic>)
          : null,
    );
  }

  static List<OpponentUnit?> _opponentSlots(List<dynamic> raw) =>
      List<OpponentUnit?>.generate(
        9,
        (i) {
          if (i >= raw.length) return null;
          final entry = raw[i];
          return entry is Map
              ? OpponentUnit.fromJson(entry.cast<String, dynamic>())
              : null;
        },
        growable: false,
      );
}

class MatchState {
  const MatchState({
    required this.matchId,
    required this.round,
    required this.yourSide,
    required this.roster,
    required this.opponent,
    required this.readyCount,
  });

  final String matchId;
  final int round;
  final MatchSide yourSide;
  final PlayerRoster roster;
  final OpponentView opponent;

  /// 0, 1, or 2 — how many players have pressed ready this phase.
  final int readyCount;

  factory MatchState.fromJson(Map<String, dynamic> j) => MatchState(
        matchId: j['matchId'] as String? ?? '',
        round: (j['round'] as num?)?.toInt() ?? 0,
        yourSide: MatchSide.fromJson(j['yourSide'] as String?),
        roster: PlayerRoster.fromJson(
          (j['roster'] as Map?)?.cast<String, dynamic>() ?? const {},
        ),
        opponent: OpponentView.fromJson(
          (j['opponent'] as Map?)?.cast<String, dynamic>() ?? const {},
        ),
        readyCount: (j['readyCount'] as num?)?.toInt() ?? 0,
      );

  @override
  String toString() =>
      'MatchState(match: $matchId, round: $round, side: $yourSide, '
      'gold: ${roster.gold}, hp: ${roster.hp}, ready: $readyCount)';
}
