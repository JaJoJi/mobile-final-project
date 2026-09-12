/// `game:combat:events` — the full, ordered list of every combat tick for
/// one battle, sent once. The client plays them as animations then acks
/// with `game:match:combat_done`.
///
/// Mirrors `docs/04-api-contracts.md` §2 — `game:combat:events` and the
/// backend `CombatEvent` union in `backend/src/game/types.ts`.
///
/// [CombatEvent] is a `sealed` class: a `switch` over a [CombatEvent] that
/// misses a subtype is a compile error, which keeps the animation code
/// honest when the server grows a new event kind.
///
/// Every event carries a `unitStates` snapshot — the full board state after
/// the event. The FE renders directly from this snapshot, eliminating
/// phantom-unit bugs caused by client/server state divergence.
library;

import 'match_state.dart' show MatchSide;
import 'unit.dart' show Unit, UnitId;

/// Lightweight snapshot of a unit's state at a specific point in battle.
class UnitSnapshot {
  const UnitSnapshot({
    required this.instanceId,
    required this.unitId,
    required this.star,
    required this.hp,
    required this.maxHp,
    required this.slot,
    required this.side,
    required this.alive,
  });

  final String instanceId;
  final UnitId unitId;
  final int star;
  final int hp;
  final int maxHp;
  final int slot;
  final MatchSide side;
  final bool alive;

  factory UnitSnapshot.fromJson(Map<String, dynamic> j) => UnitSnapshot(
        instanceId: j['instanceId'] as String? ?? '',
        unitId: UnitId.fromJson(j['unitId'] as String?),
        star: (j['star'] as num?)?.toInt() ?? 0,
        hp: (j['hp'] as num?)?.toInt() ?? 0,
        maxHp: (j['maxHp'] as num?)?.toInt() ?? 0,
        slot: (j['slot'] as num?)?.toInt() ?? 0,
        side: MatchSide.fromJson(j['side'] as String?),
        alive: j['alive'] as bool? ?? false,
      );

  Unit toUnit() => Unit(
        instanceId: instanceId,
        unitId: unitId,
        star: star,
        hp: hp,
        maxHp: maxHp,
      );
}

sealed class CombatEvent {
  const CombatEvent({this.unitStates});

  /// Combat cycle this event belongs to (battles run ≤ ~30 cycles).
  int get cycle;

  /// Ordering tick within the cycle. `cycle_end` / `battle_end` carry no
  /// tick of their own and report `0`.
  int get tick;

  /// Full board snapshot after this event. FE renders from this.
  final List<UnitSnapshot>? unitStates;

  /// Dispatch on the `type` discriminator. An unrecognised type yields
  /// [UnknownCombatEvent] rather than throwing, so one unknown event
  /// can't abort playback of the whole batch.
  factory CombatEvent.fromJson(Map<String, dynamic> j) {
    final type = j['type'] as String? ?? '';
    int i(String k) => (j[k] as num?)?.toInt() ?? 0;
    String s(String k) => j[k] as String? ?? '';
    UnitId? uid(String k) {
      final v = j[k] as String?;
      return v == null ? null : UnitId.fromJson(v);
    }
    MatchSide? side(String k) {
      final v = j[k] as String?;
      if (v == 'p1') return MatchSide.p1;
      if (v == 'p2') return MatchSide.p2;
      return null;
    }

    int? iOpt(String k) {
      final v = j[k];
      return v is num ? v.toInt() : null;
    }

    int? starOpt(String k) {
      final v = iOpt(k);
      return (v == 0 || v == 1 || v == 2) ? v : null;
    }

    List<UnitSnapshot>? snapshots() {
      final raw = j['unitStates'];
      if (raw is! List) return null;
      return raw
          .whereType<Map<String, dynamic>>()
          .map(UnitSnapshot.fromJson)
          .toList(growable: false);
    }

    return switch (type) {
      'attack' => AttackEvent(
          cycle: i('cycle'),
          tick: i('tick'),
          attacker: s('attacker'),
          target: s('target'),
          damage: i('damage'),
          targetHpAfter: i('targetHpAfter'),
          attackerSide: side('attackerSide'),
          attackerSlot: iOpt('attackerSlot'),
          attackerUnitId: uid('attackerUnitId'),
          attackerStar: starOpt('attackerStar'),
          targetSide: side('targetSide'),
          targetSlot: iOpt('targetSlot'),
          targetUnitId: uid('targetUnitId'),
          targetStar: starOpt('targetStar'),
          unitStates: snapshots(),
        ),
      'death' => DeathEvent(
          cycle: i('cycle'),
          tick: i('tick'),
          unit: s('unit'),
          unitSide: side('unitSide'),
          unitSlot: iOpt('unitSlot'),
          unitUnitId: uid('unitUnitId'),
          unitStar: starOpt('unitStar'),
          unitStates: snapshots(),
        ),
      'revive' => ReviveEvent(
          cycle: i('cycle'),
          tick: i('tick'),
          unit: s('unit'),
          hpAfter: i('hpAfter'),
          unitSide: side('unitSide'),
          unitSlot: iOpt('unitSlot'),
          unitUnitId: uid('unitUnitId'),
          unitStar: starOpt('unitStar'),
          unitStates: snapshots(),
        ),
      'heal' => HealEvent(
          cycle: i('cycle'),
          tick: i('tick'),
          target: s('target'),
          by: s('by'),
          amount: i('amount'),
          targetHpAfter: i('targetHpAfter'),
          targetSide: side('targetSide'),
          targetSlot: iOpt('targetSlot'),
          targetUnitId: uid('targetUnitId'),
          targetStar: starOpt('targetStar'),
          bySide: side('bySide'),
          bySlot: iOpt('bySlot'),
          byUnitId: uid('byUnitId'),
          byStar: starOpt('byStar'),
          unitStates: snapshots(),
        ),
      'lifesteal' => LifestealEvent(
          cycle: i('cycle'),
          tick: i('tick'),
          unit: s('unit'),
          amount: i('amount'),
          hpAfter: i('hpAfter'),
          unitSide: side('unitSide'),
          unitSlot: iOpt('unitSlot'),
          unitUnitId: uid('unitUnitId'),
          unitStar: starOpt('unitStar'),
          unitStates: snapshots(),
        ),
      'pierce' => PierceEvent(
          cycle: i('cycle'),
          tick: i('tick'),
          attacker: s('attacker'),
          target: s('target'),
          damage: i('damage'),
          attackerSide: side('attackerSide'),
          attackerSlot: iOpt('attackerSlot'),
          attackerUnitId: uid('attackerUnitId'),
          attackerStar: starOpt('attackerStar'),
          targetSide: side('targetSide'),
          targetSlot: iOpt('targetSlot'),
          targetUnitId: uid('targetUnitId'),
          targetStar: starOpt('targetStar'),
          unitStates: snapshots(),
        ),
      'slow' => SlowEvent(
          cycle: i('cycle'),
          tick: i('tick'),
          target: s('target'),
          by: s('by'),
          targetSide: side('targetSide'),
          targetSlot: iOpt('targetSlot'),
          targetUnitId: uid('targetUnitId'),
          targetStar: starOpt('targetStar'),
          bySide: side('bySide'),
          bySlot: iOpt('bySlot'),
          byUnitId: uid('byUnitId'),
          byStar: starOpt('byStar'),
          unitStates: snapshots(),
        ),
      'cycle_end' => CycleEndEvent(
          cycle: i('cycle'),
          unitStates: snapshots(),
        ),
      'battle_end' => BattleEndEvent(
          cycle: i('cycle'),
          winner: switch (j['winner']) {
            'p1' => MatchSide.p1,
            'p2' => MatchSide.p2,
            _ => null,
          },
          unitStates: snapshots(),
        ),
      _ => UnknownCombatEvent(
          type: type,
          cycle: i('cycle'),
          tick: i('tick'),
          unitStates: snapshots(),
        ),
    };
  }
}

class AttackEvent extends CombatEvent {
  const AttackEvent({
    required this.cycle,
    required this.tick,
    required this.attacker,
    required this.target,
    required this.damage,
    required this.targetHpAfter,
    this.attackerSide,
    this.attackerSlot,
    this.attackerUnitId,
    this.attackerStar,
    this.targetSide,
    this.targetSlot,
    this.targetUnitId,
    this.targetStar,
    super.unitStates,
  });

  @override
  final int cycle;
  @override
  final int tick;
  final String attacker;
  final String target;
  final int damage;
  final int targetHpAfter;

  final MatchSide? attackerSide;
  final int? attackerSlot;
  final UnitId? attackerUnitId;
  final int? attackerStar;
  final MatchSide? targetSide;
  final int? targetSlot;
  final UnitId? targetUnitId;
  final int? targetStar;
}

class DeathEvent extends CombatEvent {
  const DeathEvent({
    required this.cycle,
    required this.tick,
    required this.unit,
    this.unitSide,
    this.unitSlot,
    this.unitUnitId,
    this.unitStar,
    super.unitStates,
  });

  @override
  final int cycle;
  @override
  final int tick;
  final String unit;

  final MatchSide? unitSide;
  final int? unitSlot;
  final UnitId? unitUnitId;
  final int? unitStar;
}

class ReviveEvent extends CombatEvent {
  const ReviveEvent({
    required this.cycle,
    required this.tick,
    required this.unit,
    required this.hpAfter,
    this.unitSide,
    this.unitSlot,
    this.unitUnitId,
    this.unitStar,
    super.unitStates,
  });

  @override
  final int cycle;
  @override
  final int tick;
  final String unit;
  final int hpAfter;

  final MatchSide? unitSide;
  final int? unitSlot;
  final UnitId? unitUnitId;
  final int? unitStar;
}

class HealEvent extends CombatEvent {
  const HealEvent({
    required this.cycle,
    required this.tick,
    required this.target,
    required this.by,
    required this.amount,
    required this.targetHpAfter,
    this.targetSide,
    this.targetSlot,
    this.targetUnitId,
    this.targetStar,
    this.bySide,
    this.bySlot,
    this.byUnitId,
    this.byStar,
    super.unitStates,
  });

  @override
  final int cycle;
  @override
  final int tick;
  final String target;
  final String by;
  final int amount;
  final int targetHpAfter;

  final MatchSide? targetSide;
  final int? targetSlot;
  final UnitId? targetUnitId;
  final int? targetStar;
  final MatchSide? bySide;
  final int? bySlot;
  final UnitId? byUnitId;
  final int? byStar;
}

class LifestealEvent extends CombatEvent {
  const LifestealEvent({
    required this.cycle,
    required this.tick,
    required this.unit,
    required this.amount,
    required this.hpAfter,
    this.unitSide,
    this.unitSlot,
    this.unitUnitId,
    this.unitStar,
    super.unitStates,
  });

  @override
  final int cycle;
  @override
  final int tick;
  final String unit;
  final int amount;
  final int hpAfter;

  final MatchSide? unitSide;
  final int? unitSlot;
  final UnitId? unitUnitId;
  final int? unitStar;
}

class PierceEvent extends CombatEvent {
  const PierceEvent({
    required this.cycle,
    required this.tick,
    required this.attacker,
    required this.target,
    required this.damage,
    this.attackerSide,
    this.attackerSlot,
    this.attackerUnitId,
    this.attackerStar,
    this.targetSide,
    this.targetSlot,
    this.targetUnitId,
    this.targetStar,
    super.unitStates,
  });

  @override
  final int cycle;
  @override
  final int tick;
  final String attacker;
  final String target;
  final int damage;

  final MatchSide? attackerSide;
  final int? attackerSlot;
  final UnitId? attackerUnitId;
  final int? attackerStar;
  final MatchSide? targetSide;
  final int? targetSlot;
  final UnitId? targetUnitId;
  final int? targetStar;
}

class SlowEvent extends CombatEvent {
  const SlowEvent({
    required this.cycle,
    required this.tick,
    required this.target,
    required this.by,
    this.targetSide,
    this.targetSlot,
    this.targetUnitId,
    this.targetStar,
    this.bySide,
    this.bySlot,
    this.byUnitId,
    this.byStar,
    super.unitStates,
  });

  @override
  final int cycle;
  @override
  final int tick;
  final String target;
  final String by;

  final MatchSide? targetSide;
  final int? targetSlot;
  final UnitId? targetUnitId;
  final int? targetStar;
  final MatchSide? bySide;
  final int? bySlot;
  final UnitId? byUnitId;
  final int? byStar;
}

class CycleEndEvent extends CombatEvent {
  const CycleEndEvent({
    required this.cycle,
    super.unitStates,
  });

  @override
  final int cycle;
  @override
  int get tick => 0;
}

class BattleEndEvent extends CombatEvent {
  const BattleEndEvent({
    required this.cycle,
    required this.winner,
    super.unitStates,
  });

  @override
  final int cycle;
  @override
  int get tick => 0;

  final MatchSide? winner;
}

/// Fallback for a `type` this client build doesn't know yet.
class UnknownCombatEvent extends CombatEvent {
  const UnknownCombatEvent({
    required this.type,
    required this.cycle,
    required this.tick,
    super.unitStates,
  });

  final String type;
  @override
  final int cycle;
  @override
  final int tick;
}

/// Server-authoritative unit state at combat start.
class CombatUnit {
  const CombatUnit({
    required this.instanceId,
    required this.unitId,
    required this.star,
    required this.hp,
    required this.maxHp,
  });

  final String instanceId;
  final UnitId unitId;
  final int star;
  final int hp;
  final int maxHp;

  factory CombatUnit.fromJson(Map<String, dynamic> j) => CombatUnit(
        instanceId: j['instanceId'] as String? ?? '',
        unitId: UnitId.fromJson(j['unitId'] as String?),
        star: (j['star'] as num?)?.toInt() ?? 0,
        hp: (j['hp'] as num?)?.toInt() ?? 0,
        maxHp: (j['maxHp'] as num?)?.toInt() ?? 0,
      );

  Unit toUnit() => Unit(
        instanceId: instanceId,
        unitId: unitId,
        star: star,
        hp: hp,
        maxHp: maxHp,
      );
}

/// Server-authoritative board state: p1 and p2 boards at combat start.
class CombatBoardState {
  const CombatBoardState({
    required this.p1,
    required this.p2,
  });

  final List<CombatUnit?> p1;
  final List<CombatUnit?> p2;

  factory CombatBoardState.fromJson(Map<String, dynamic> j) {
    return CombatBoardState(
      p1: _parseBoard(j['p1']),
      p2: _parseBoard(j['p2']),
    );
  }

  static List<CombatUnit?> _parseBoard(dynamic raw) {
    final list = raw is List ? raw : const <Object?>[];
    return List<CombatUnit?>.generate(
      9,
      (i) {
        if (i >= list.length) return null;
        final entry = list[i];
        return entry is Map<String, dynamic> ? CombatUnit.fromJson(entry) : null;
      },
      growable: false,
    );
  }
}

class CombatEventBatch {
  const CombatEventBatch({
    required this.matchId,
    required this.round,
    required this.cycleCount,
    required this.endedAt,
    required this.events,
    this.initialBoard,
  });

  final String matchId;
  final int round;
  final int cycleCount;
  final int endedAt;
  final List<CombatEvent> events;
  final CombatBoardState? initialBoard;

  DateTime get endedAtTime =>
      DateTime.fromMillisecondsSinceEpoch(endedAt, isUtc: true);

  factory CombatEventBatch.fromJson(Map<String, dynamic> j) {
    final raw = (j['events'] as List?) ?? const [];
    return CombatEventBatch(
      matchId: j['matchId'] as String? ?? '',
      round: (j['round'] as num?)?.toInt() ?? 0,
      cycleCount: (j['cycleCount'] as num?)?.toInt() ?? 0,
      endedAt: (j['endedAt'] as num?)?.toInt() ?? 0,
      events: raw
          .whereType<Map<String, dynamic>>()
          .map(CombatEvent.fromJson)
          .toList(growable: false),
      initialBoard: j['initialBoard'] != null
          ? CombatBoardState.fromJson(
              j['initialBoard'] as Map<String, dynamic>)
          : null,
    );
  }

  @override
  String toString() => 'CombatEventBatch(match: $matchId, round: $round, '
      'cycles: $cycleCount, events: ${events.length})';
}
