/// Visual state for the in-match combat player (P0-FE-05).
///
/// Uses server-authoritative `unitStates` snapshots from every combat event.
/// The FE no longer tracks state locally — it renders directly from the
/// snapshot, eliminating phantom-unit bugs caused by state divergence.
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

/// Per-unit visual state derived from the server snapshot at the current
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
    this.lungeDx = 0,
    this.lungeDy = 0,
    this.isShooting = false,
    this.projectileTargetSlot,
    this.projectileIcon = Icons.arrow_forward,
    this.floatingDamage,
    this.floatingIsHeal = false,
  });

  final UnitId unitId;
  final int star;
  final int hp;
  final int maxHp;
  final bool alive;
  final bool isLunging;
  final int? lungeTargetSlot;
  /// Normalized horizontal lunge direction (-1 = left, +1 = right).
  final double lungeDx;
  /// Normalized vertical lunge direction (-1 = up toward enemy, +1 = down).
  final double lungeDy;
  final bool isShooting;
  final int? projectileTargetSlot;
  final IconData projectileIcon;
  final int? floatingDamage;
  final bool floatingIsHeal;

  double get hpFraction => maxHp <= 0 ? 0 : (hp / maxHp).clamp(0.0, 1.0);
}

/// Derive per-unit visual states by using the server-authoritative
/// `unitStates` snapshot from the most recent event at or before the
/// playhead. The FE no longer tracks state locally.
Map<UnitKey, UnitVisualState> deriveUnitStates({
  required List<CombatEvent> events,
  required int playheadIndex,
  required List<Unit?> playerBoard,
  required List<Unit?> opponentBoard,
}) {
  if (events.isEmpty) return const {};

  final limit = playheadIndex.clamp(0, events.length - 1);

  // Find the most recent event at or before the playhead that has a snapshot.
  CombatEvent? snapshotEvent;
  for (var i = limit; i >= 0; i--) {
    if (events[i].unitStates != null && events[i].unitStates!.isNotEmpty) {
      snapshotEvent = events[i];
      break;
    }
  }

  if (snapshotEvent == null) return const {};

  // Build the map from the server snapshot.
  final map = <UnitKey, UnitVisualState>{};
  for (final snap in snapshotEvent.unitStates!) {
    final key = UnitKey(side: snap.side, slot: snap.slot);
    map[key] = UnitVisualState(
      unitId: snap.unitId,
      star: snap.star,
      hp: snap.hp,
      maxHp: snap.maxHp,
      alive: snap.alive,
    );
  }

  // Apply animation flags from the current event (lunge, shoot, floating).
  if (events.isNotEmpty && limit < events.length) {
    final current = events[limit];

    switch (current) {
      case AttackEvent():
        // Floating damage on target.
        _setFloating(
          current.targetSide,
          current.targetSlot,
          current.damage,
          false,
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
            if (isMelee && current.targetSlot != null) {
              // Melee always attacks cross-board, so vertical direction
              // is simply toward the opponent side.
              final attackerSlot = current.attackerSlot!;
              final targetSlot = current.targetSlot!;
              final aCol = attackerSlot % 3;
              final tCol = targetSlot % 3;
              var dCol = (tCol - aCol).toDouble();
              // Normalize horizontal to -1..+1.
              if (dCol.abs() > 1) dCol = dCol > 0 ? 1.0 : -1.0;
              // Vertical: player lunges UP, enemy lunges DOWN.
              final dRow = current.attackerSide == MatchSide.p2 ? 1.0 : -1.0;
              map[key] = UnitVisualState(
                unitId: existing.unitId,
                star: existing.star,
                hp: existing.hp,
                maxHp: existing.maxHp,
                alive: existing.alive,
                isLunging: true,
                lungeTargetSlot: current.targetSlot,
                lungeDx: dCol,
                lungeDy: dRow,
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
          current.amount,
          true,
          map,
        );
      case LifestealEvent():
        _setFloating(
          current.unitSide,
          current.unitSlot,
          current.amount,
          true,
          map,
        );
      case PierceEvent():
        _setFloating(
          current.targetSide,
          current.targetSlot,
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

/// Set a floating damage/heal number on a unit.
void _setFloating(
  MatchSide? side,
  int? slot,
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

  final CombatEventBatch? batch;
  final int playheadIndex;
  final double playheadProgress;

  static const BattleVisualState empty = BattleVisualState(
    batch: null,
    playheadIndex: 0,
    playheadProgress: 0.0,
  );

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
