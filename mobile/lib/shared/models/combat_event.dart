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
/// The `*Side` / `*Slot` / `*UnitId` / `*Star` fields (P0-FE-05 prep, see
/// `docs/04 §2.1`) are optional in the type but always populated by the
/// engine. They let the FE animation player resolve any event to world
/// coordinates + the right sprite without an out-of-band snapshot.
library;

import 'match_state.dart' show MatchSide;
import 'unit.dart' show UnitId;

sealed class CombatEvent {
  const CombatEvent();

  /// Combat cycle this event belongs to (battles run ≤ ~30 cycles).
  int get cycle;

  /// Ordering tick within the cycle. `cycle_end` / `battle_end` carry no
  /// tick of their own and report `0`.
  int get tick;

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
        ),
      'death' => DeathEvent(
          cycle: i('cycle'),
          tick: i('tick'),
          unit: s('unit'),
          unitSide: side('unitSide'),
          unitSlot: iOpt('unitSlot'),
          unitUnitId: uid('unitUnitId'),
          unitStar: starOpt('unitStar'),
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
        ),
      'cycle_end' => CycleEndEvent(cycle: i('cycle')),
      'battle_end' => BattleEndEvent(
          cycle: i('cycle'),
          winner: switch (j['winner']) {
            'p1' => MatchSide.p1,
            'p2' => MatchSide.p2,
            _ => null,
          },
        ),
      _ => UnknownCombatEvent(type: type, cycle: i('cycle'), tick: i('tick')),
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
  });

  @override
  final int cycle;
  @override
  final int tick;
  final String attacker;
  final String target;
  final int damage;
  final int targetHpAfter;

  // P0-FE-05 enriched fields — always populated by the engine.
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
  const CycleEndEvent({required this.cycle});

  @override
  final int cycle;
  @override
  int get tick => 0;
}

class BattleEndEvent extends CombatEvent {
  const BattleEndEvent({required this.cycle, required this.winner});

  @override
  final int cycle;
  @override
  int get tick => 0;

  /// `null` on a tie (both boards wiped in the same cycle).
  final MatchSide? winner;
}

/// Fallback for a `type` this client build doesn't know yet.
class UnknownCombatEvent extends CombatEvent {
  const UnknownCombatEvent({
    required this.type,
    required this.cycle,
    required this.tick,
  });

  final String type;
  @override
  final int cycle;
  @override
  final int tick;
}

class CombatEventBatch {
  const CombatEventBatch({
    required this.matchId,
    required this.round,
    required this.cycleCount,
    required this.endedAt,
    required this.events,
  });

  final String matchId;
  final int round;

  /// Number of cycles the engine ran (typically ≤ 30).
  final int cycleCount;

  /// Epoch milliseconds when the engine finished.
  final int endedAt;

  /// Full ordered event list — usually 100–2000 entries.
  final List<CombatEvent> events;

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
    );
  }

  @override
  String toString() => 'CombatEventBatch(match: $matchId, round: $round, '
      'cycles: $cycleCount, events: ${events.length})';
}
