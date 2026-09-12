/// Visual state for the in-match combat player (P0-FE-05).
///
/// 2a: thin wrapper around the loaded [CombatEventBatch] and playhead.
/// 2b: adds per-unit HP / alive derivation — [deriveUnitStates] replays
///     events up to the current playhead and returns a map of
///     `[UnitKey] → [UnitVisualState]` that the tile widgets consume.
library;

import 'package:flutter/material.dart' show IconData, Icons;

import '../../../shared/models/combat_event.dart';
import '../../../shared/models/match_state.dart' show MatchSide;
import '../../../shared/models/unit.dart';

/// Stable key for one unit on the board: side + board slot (0–8).
class UnitKey {
  const UnitKey({required this.side, required this.slot});

  final MatchSide side;
  final int slot;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UnitKey && other.side == side && other.slot == slot;

  @override
  int get hashCode => Object.hash(side, slot);

  @override
  String toString() => 'UnitKey(${side.name}, $slot)';
}

/// Per-unit visual state derived from the event list up to the current
/// playhead position. Consumed by [BattleTile] to render the correct
/// sprite, HP bar, and alive/dead alpha.
class UnitVisualState {
  const UnitVisualState({
    required this.unitId,
    required this.star,
    required this.hp,
    required this.maxHp,
    required this.alive,
    this.isLunging = false,
    this.lungeTargetSlot,
    this.isShooting = false,
    this.projectileTargetSlot,
    this.projectileIcon = Icons.arrow_forward,
    this.floatingDamage,
    this.floatingIsHeal = false,
  });

  final UnitId unitId;
  final int star;

  /// Current HP after applying all events up to the playhead.
  final int hp;

  /// Maximum HP — seeded from the roster snapshot, updated if a
  /// later event reveals a higher value (e.g. heal above initial).
  final int maxHp;

  /// Whether this unit is alive at the current playhead. `false` after
  /// a `death` event, restored to `true` by `revive`.
  final bool alive;

  /// Whether this unit is currently performing a melee lunge (the most
  /// recent event at the playhead is an attack by this unit).
  final bool isLunging;

  /// The board slot (0–8) of the attack target, used by the tile to
  /// compute the lunge direction. `null` when [isLunging] is `false`.
  final int? lungeTargetSlot;

  /// Whether this unit is currently shooting a projectile (ranged attack).
  final bool isShooting;

  /// The board slot (0–8) of the projectile target.
  final int? projectileTargetSlot;

  /// The icon to display as the projectile (arrow_forward for ranger,
  /// bolt for healer).
  final IconData projectileIcon;

  /// The damage/heal amount to float above this unit. `null` when no
  /// number should be shown.
  final int? floatingDamage;

  /// Whether the floating number is a heal (green) vs damage (red).
  final bool floatingIsHeal;

  double get hpFraction => maxHp <= 0 ? 0 : (hp / maxHp).clamp(0.0, 1.0);
}

/// Derive per-unit visual states by replaying events [0..playheadIndex]
/// (inclusive) on top of the initial board roster.
///
/// The roster provides starting HP for the player's units. The opponent's
/// roster is redacted (no HP), so their initial HP is inferred from the
/// first event that references them (targetHpAfter + damage for attack/
/// pierce, hpAfter for heal/lifesteal/revive).
Map<UnitKey, UnitVisualState> deriveUnitStates({
  required List<CombatEvent> events,
  required int playheadIndex,
  required List<Unit?> playerBoard,
  required List<Unit?> opponentBoard,
}) {
  final map = <UnitKey, UnitVisualState>{};

  // Seed from roster snapshots.
  for (var i = 0; i < 9; i++) {
    final u = playerBoard[i];
    if (u != null) {
      map[UnitKey(side: MatchSide.p1, slot: i)] = UnitVisualState(
        unitId: u.unitId,
        star: u.star,
        hp: u.hp,
        maxHp: u.maxHp,
        alive: u.hp > 0,
      );
    }
  }
  for (var i = 0; i < 9; i++) {
    final u = opponentBoard[i];
    if (u != null) {
      map[UnitKey(side: MatchSide.p2, slot: i)] = UnitVisualState(
        unitId: u.unitId,
        star: u.star,
        hp: u.hp,
        maxHp: u.maxHp,
        alive: u.hp > 0,
      );
    }
  }

  // Clamp to the events visible at the current playhead.
  final limit = playheadIndex.clamp(0, events.length - 1);

  for (var i = 0; i <= limit; i++) {
    final e = events[i];

    switch (e) {
      case AttackEvent():
        _applyTarget(
          e.targetSide,
          e.targetSlot,
          e.targetUnitId,
          e.targetStar,
          e.targetHpAfter,
          map,
        );
        _ensureAttacker(
          e.attackerSide,
          e.attackerSlot,
          e.attackerUnitId,
          e.attackerStar,
          map,
        );
      case PierceEvent():
        _applyTarget(
          e.targetSide,
          e.targetSlot,
          e.targetUnitId,
          e.targetStar,
          null,
          map,
        );
        _ensureAttacker(
          e.attackerSide,
          e.attackerSlot,
          e.attackerUnitId,
          e.attackerStar,
          map,
        );
      case DeathEvent():
        _kill(e.unitSide, e.unitSlot, e.unitUnitId, e.unitStar, map);
      case ReviveEvent():
        _revive(
          e.unitSide,
          e.unitSlot,
          e.unitUnitId,
          e.unitStar,
          e.hpAfter,
          map,
        );
      case HealEvent():
        _applyTarget(
          e.targetSide,
          e.targetSlot,
          e.targetUnitId,
          e.targetStar,
          e.targetHpAfter,
          map,
        );
        _ensureAttacker(
          e.bySide,
          e.bySlot,
          e.byUnitId,
          e.byStar,
          map,
        );
      case LifestealEvent():
        _applySelf(
          e.unitSide,
          e.unitSlot,
          e.unitUnitId,
          e.unitStar,
          e.hpAfter,
          map,
        );
      case SlowEvent():
        _ensureAttacker(
          e.targetSide,
          e.targetSlot,
          e.targetUnitId,
          e.targetStar,
          map,
        );
        _ensureAttacker(
          e.bySide,
          e.bySlot,
          e.byUnitId,
          e.byStar,
          map,
        );
      case CycleEndEvent():
      case BattleEndEvent():
      case UnknownCombatEvent():
        break;
    }
  }

  // Mark the attacker of the current event as lunging or shooting,
  // and set floating damage/heal numbers on the target.
  if (events.isNotEmpty && limit < events.length) {
    final current = events[limit];

    switch (current) {
      case AttackEvent():
        // Floating damage on target.
        _setFloating(
          current.targetSide,
          current.targetSlot,
          current.targetUnitId,
          current.targetStar,
          current.damage,
          false, // not heal
          map,
        );
        // Lunging / shooting on attacker.
        if (current.attackerSlot != null &&
            current.attackerSide != null &&
            current.attackerUnitId != null) {
          final isMelee = current.attackerUnitId == UnitId.fighter ||
              current.attackerUnitId == UnitId.tank;
          final key = UnitKey(
            side: current.attackerSide!,
            slot: current.attackerSlot!,
          );
          final existing = map[key];
          if (existing != null) {
            if (isMelee) {
              map[key] = UnitVisualState(
                unitId: existing.unitId,
                star: existing.star,
                hp: existing.hp,
                maxHp: existing.maxHp,
                alive: existing.alive,
                isLunging: true,
                lungeTargetSlot: current.targetSlot,
              );
            } else {
              final icon = current.attackerUnitId == UnitId.ranger
                  ? Icons.arrow_forward
                  : Icons.bolt;
              map[key] = UnitVisualState(
                unitId: existing.unitId,
                star: existing.star,
                hp: existing.hp,
                maxHp: existing.maxHp,
                alive: existing.alive,
                isShooting: true,
                projectileTargetSlot: current.targetSlot,
                projectileIcon: icon,
              );
            }
          }
        }
      case HealEvent():
        _setFloating(
          current.targetSide,
          current.targetSlot,
          current.targetUnitId,
          current.targetStar,
          current.amount,
          true, // heal
          map,
        );
      case LifestealEvent():
        _setFloating(
          current.unitSide,
          current.unitSlot,
          current.unitUnitId,
          current.unitStar,
          current.amount,
          true, // heal
          map,
        );
      case PierceEvent():
        _setFloating(
          current.targetSide,
          current.targetSlot,
          current.targetUnitId,
          current.targetStar,
          current.damage,
          false,
          map,
        );
      default:
        break;
    }
  }

  return map;
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Update target HP from attack / heal events.
void _applyTarget(
  MatchSide? side,
  int? slot,
  UnitId? unitId,
  int? star,
  int? hpAfter,
  Map<UnitKey, UnitVisualState> map,
) {
  if (side == null || slot == null) return;
  final key = UnitKey(side: side, slot: slot);
  final existing = map[key];
  if (existing != null && hpAfter != null) {
    map[key] = UnitVisualState(
      unitId: existing.unitId,
      star: existing.star,
      hp: hpAfter,
      maxHp: existing.maxHp < hpAfter ? hpAfter : existing.maxHp,
      alive: hpAfter > 0,
    );
  } else if (existing == null && unitId != null && star != null) {
    // First time seeing this unit (opponent with no roster entry).
    final hp = hpAfter ?? 0;
    map[key] = UnitVisualState(
      unitId: unitId,
      star: star,
      hp: hp,
      maxHp: hp,
      alive: hp > 0,
    );
  }
}

/// Ensure an attacker/self unit exists in the map (may be first sighting
/// for opponent units not in the roster).
void _ensureAttacker(
  MatchSide? side,
  int? slot,
  UnitId? unitId,
  int? star,
  Map<UnitKey, UnitVisualState> map,
) {
  if (side == null || slot == null || unitId == null || star == null) return;
  final key = UnitKey(side: side, slot: slot);
  if (map.containsKey(key)) return;
  map[key] = UnitVisualState(
    unitId: unitId,
    star: star,
    hp: 0,
    maxHp: 0,
    alive: true,
  );
}

/// Update self HP from lifesteal events.
void _applySelf(
  MatchSide? side,
  int? slot,
  UnitId? unitId,
  int? star,
  int hpAfter,
  Map<UnitKey, UnitVisualState> map,
) {
  if (side == null || slot == null) return;
  final key = UnitKey(side: side, slot: slot);
  final existing = map[key];
  if (existing != null) {
    map[key] = UnitVisualState(
      unitId: existing.unitId,
      star: existing.star,
      hp: hpAfter,
      maxHp: existing.maxHp < hpAfter ? hpAfter : existing.maxHp,
      alive: hpAfter > 0,
    );
  } else if (unitId != null && star != null) {
    map[key] = UnitVisualState(
      unitId: unitId,
      star: star,
      hp: hpAfter,
      maxHp: hpAfter,
      alive: hpAfter > 0,
    );
  }
}

/// Mark a unit as dead.
void _kill(
  MatchSide? side,
  int? slot,
  UnitId? unitId,
  int? star,
  Map<UnitKey, UnitVisualState> map,
) {
  if (side == null || slot == null) return;
  final key = UnitKey(side: side, slot: slot);
  final existing = map[key];
  if (existing != null) {
    map[key] = UnitVisualState(
      unitId: existing.unitId,
      star: existing.star,
      hp: 0,
      maxHp: existing.maxHp,
      alive: false,
    );
  } else if (unitId != null && star != null) {
    map[key] = UnitVisualState(
      unitId: unitId,
      star: star,
      hp: 0,
      maxHp: 0,
      alive: false,
    );
  }
}

/// Revive a dead unit.
void _revive(
  MatchSide? side,
  int? slot,
  UnitId? unitId,
  int? star,
  int hpAfter,
  Map<UnitKey, UnitVisualState> map,
) {
  if (side == null || slot == null) return;
  final key = UnitKey(side: side, slot: slot);
  final existing = map[key];
  if (existing != null) {
    map[key] = UnitVisualState(
      unitId: existing.unitId,
      star: existing.star,
      hp: hpAfter,
      maxHp: existing.maxHp < hpAfter ? hpAfter : existing.maxHp,
      alive: true,
    );
  } else if (unitId != null && star != null) {
    map[key] = UnitVisualState(
      unitId: unitId,
      star: star,
      hp: hpAfter,
      maxHp: hpAfter,
      alive: true,
    );
  }
}

/// Set a floating damage/heal number on a unit.
void _setFloating(
  MatchSide? side,
  int? slot,
  UnitId? unitId,
  int? star,
  int amount,
  bool isHeal,
  Map<UnitKey, UnitVisualState> map,
) {
  if (side == null || slot == null) return;
  final key = UnitKey(side: side, slot: slot);
  final existing = map[key];
  if (existing != null) {
    map[key] = UnitVisualState(
      unitId: existing.unitId,
      star: existing.star,
      hp: existing.hp,
      maxHp: existing.maxHp,
      alive: existing.alive,
      floatingDamage: amount,
      floatingIsHeal: isHeal,
    );
  } else if (unitId != null && star != null) {
    map[key] = UnitVisualState(
      unitId: unitId,
      star: star,
      hp: 0,
      maxHp: 0,
      alive: true,
      floatingDamage: amount,
      floatingIsHeal: isHeal,
    );
  }
}

/// State of the battle player at one instant.
class BattleVisualState {
  const BattleVisualState({
    required this.batch,
    required this.playheadIndex,
    required this.playheadProgress,
  })  : assert(playheadIndex >= 0, 'playheadIndex must be non-negative'),
        assert(
          playheadProgress >= 0.0 && playheadProgress <= 1.0,
          'playheadProgress must be in [0, 1]',
        );

  /// The full batch that was just loaded. `null` before the first batch
  /// arrives (still in `shop_place` or waiting for the engine to finish).
  final CombatEventBatch? batch;

  /// Index of the most recently *finished* event at the current playhead
  /// position. Computed by the controller from
  /// `playheadProgress * events.length`. Sub-steps 2b+ read this to walk
  /// the event list up to (but not past) the current frame.
  final int playheadIndex;

  /// Raw `0.0..1.0` fraction along the entire battle. The widget's
  /// `AnimationController` is the source of truth here — the controller
  /// receives it via [BattlePlaybackController.seekTo] on every frame.
  final double playheadProgress;

  /// Empty state — the match isn't in `battle` yet, or no batch arrived.
  static const BattleVisualState empty = BattleVisualState(
    batch: null,
    playheadIndex: 0,
    playheadProgress: 0.0,
  );

  /// `true` when the playhead has reached the end of the batch.
  bool get isFinished {
    final b = batch;
    return b != null && b.events.isEmpty
        ? true
        : (batch?.events.isNotEmpty ?? false) &&
            playheadIndex >= batch!.events.length - 1 &&
            playheadProgress >= 0.999;
  }

  BattleVisualState copyWith({
    Object? batch = _sentinel,
    int? playheadIndex,
    double? playheadProgress,
  }) =>
      BattleVisualState(
        batch: identical(batch, _sentinel) ? this.batch : batch as CombatEventBatch?,
        playheadIndex: playheadIndex ?? this.playheadIndex,
        playheadProgress: playheadProgress ?? this.playheadProgress,
      );
}

const _sentinel = Object();
