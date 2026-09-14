/// Visual state for the in-match combat player (P0-FE-05).
///
/// Uses server-authoritative `unitStates` snapshots from every combat event.
/// The FE no longer tracks state locally — it renders directly from the
/// snapshot, eliminating phantom-unit bugs caused by state divergence.
library;

import 'package:flutter/material.dart' show Color;

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

/// Persistent debuff status on a unit.
class UnitDebuff {
  const UnitDebuff({required this.type, required this.color});

  final String type;
  final Color color;
}

/// Per-unit visual state derived from the server snapshot at the current
/// playhead position. Consumed by [BattleTile] to render the correct
/// sprite, HP bar, and alive/dead state.
class UnitVisualState {
  const UnitVisualState({
    required this.unitId,
    required this.star,
    required this.hp,
    required this.maxHp,
    required this.alive,
    this.floatingDamage,
    this.floatingIsHeal = false,
    this.healEventIndex,
    this.lastDamageEventIndex,
    this.recoilEventIndex,
    this.recoilDx = 0,
    this.recoilDy = 0,
    this.isMeleeAttacking = false,
    this.debuff,
  });

  final UnitId unitId;
  final int star;
  final int hp;
  final int maxHp;
  final bool alive;
  final int? floatingDamage;
  final bool floatingIsHeal;

  /// Index of the heal/lifesteal event currently active on this unit.
  /// [BattleTile] uses this as a trigger key for the heal bubble animation.
  final int? healEventIndex;

  /// Index of the most recent damage event targeting this unit.
  /// [BattleTile] uses this as a trigger key for the hit shake animation.
  final int? lastDamageEventIndex;

  /// Index of the most recent melee attack event this unit was the
  /// attacker in. [BattleTile] uses this as a trigger key for a small
  /// in-place recoil — the cross-board attack streak itself lives in
  /// [CombatEffectsOverlay], but the attacker's own sprite needs to move
  /// too for the attack to read clearly (P4-FE-01 follow-up).
  final int? recoilEventIndex;

  /// Normalized recoil direction toward the target (-1 = left, +1 =
  /// right); 0 when this unit isn't a melee attacker.
  final double recoilDx;

  /// Normalized recoil direction toward the target (-1 = up toward
  /// enemy, +1 = down); 0 when this unit isn't a melee attacker.
  final double recoilDy;

  /// True only while this unit is the melee attacker of the event playing
  /// *right now*. [CombatEffectsOverlay] draws its sprite travelling to
  /// the target during that window, so the home tile hides its own copy
  /// to avoid rendering the unit twice.
  final bool isMeleeAttacking;

  /// Active debuff on this unit (e.g. slow). Persistent until the debuff
  /// expires (precomputed via healer attack scan).
  final UnitDebuff? debuff;

  double get hpFraction => maxHp <= 0 ? 0 : (hp / maxHp).clamp(0.0, 1.0);
}

/// Derive per-unit visual states by using the server-authoritative
/// `unitStates` snapshot from the most recent event at or before the
/// playhead. The FE no longer tracks state locally.
///
/// Additionally precomputes:
/// - Debuff expirations (slow clears when the healer attacks again)
/// - Heal event trigger keys (for transient bubble animation)
/// - Damage event trigger keys (for hit shake animation)
Map<UnitKey, UnitVisualState> deriveUnitStates({
  required List<CombatEvent> events,
  required int playheadIndex,
  required List<Unit?> playerBoard,
  required List<Unit?> opponentBoard,
  required MatchSide mySide,
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

  // --- Precompute debuff expirations ---
  // Slow persists until the Healer attacks again (per combat spec §2.3).
  // Build: slowStart[healerInstanceId] = [{ targetKey, applyIndex }].
  final slowStart = <String, List<_SlowEntry>>{};
  for (var i = 0; i < events.length; i++) {
    final e = events[i];
    if (e is SlowEvent &&
        e.by != null &&
        e.targetSide != null &&
        e.targetSlot != null) {
      final key = UnitKey(side: e.targetSide!, slot: e.targetSlot!);
      slowStart.putIfAbsent(e.by!, () => []).add(_SlowEntry(key, i));
    }
  }
  // debuffExpiry[targetKey] = event index where debuff clears.
  final debuffExpiry = <UnitKey, int>{};
  for (final entry in slowStart.entries) {
    final healerId = entry.key;
    final targets = entry.value;
    // Find the next attack by this healer after each slow apply.
    for (final slow in targets) {
      for (var i = slow.index + 1; i < events.length; i++) {
        final e = events[i];
        if (e is AttackEvent && e.attacker == healerId) {
          debuffExpiry[slow.key] = i;
          break;
        }
      }
    }
  }

  // --- Precompute heal event trigger keys ---
  // healEventIndex[unitKey] = most recent heal/lifesteal event index ≤ limit.
  final healEventIndex = <UnitKey, int>{};
  for (var i = 0; i <= limit; i++) {
    final e = events[i];
    UnitKey? target;
    if (e is HealEvent && e.targetSide != null && e.targetSlot != null) {
      target = UnitKey(side: e.targetSide!, slot: e.targetSlot!);
    } else if (e is LifestealEvent &&
        e.unitSide != null &&
        e.unitSlot != null) {
      target = UnitKey(side: e.unitSide!, slot: e.unitSlot!);
    }
    if (target != null) {
      healEventIndex[target] = i;
    }
  }

  // --- Precompute last damage event trigger keys ---
  // lastDamage[unitKey] = most recent attack/pierce event index targeting
  // this unit at or before limit.
  final lastDamage = <UnitKey, int>{};
  for (var i = 0; i <= limit; i++) {
    final e = events[i];
    UnitKey? target;
    if (e is AttackEvent && e.targetSide != null && e.targetSlot != null) {
      target = UnitKey(side: e.targetSide!, slot: e.targetSlot!);
    } else if (e is PierceEvent &&
        e.targetSide != null &&
        e.targetSlot != null) {
      target = UnitKey(side: e.targetSide!, slot: e.targetSlot!);
    }
    if (target != null) {
      lastDamage[target] = i;
    }
  }

  // --- Precompute melee-attacker recoil trigger keys ---
  // recoil[attackerKey] = most recent melee attack index this unit was
  // the attacker in (≤ limit), plus the normalized direction toward its
  // target — same column/row-direction formula the removed cross-board
  // lunge used, just for a small in-place nudge now (P4-FE-01 follow-up).
  final recoil = <UnitKey, ({int index, double dx, double dy})>{};
  for (var i = 0; i <= limit; i++) {
    final e = events[i];
    if (e is! AttackEvent) continue;
    final attackerSide = e.attackerSide;
    final attackerSlot = e.attackerSlot;
    final attackerUnitId = e.attackerUnitId;
    final targetSlot = e.targetSlot;
    if (attackerSide == null ||
        attackerSlot == null ||
        attackerUnitId == null ||
        targetSlot == null) {
      continue;
    }
    final isMelee =
        attackerUnitId == UnitId.fighter || attackerUnitId == UnitId.tank;
    if (!isMelee) continue;
    final aCol = attackerSlot % 3;
    final tCol = targetSlot % 3;
    var dCol = (tCol - aCol).toDouble();
    if (dCol.abs() > 1) dCol = dCol > 0 ? 1.0 : -1.0;
    // Viewer-relative, NOT absolute side: every client renders its own
    // board at the bottom and the opponent's on top, so "toward the
    // enemy" is up (-1) for the viewer's own units and down (+1) for the
    // opponent's — regardless of whether the viewer happens to be p1 or
    // p2. Keying this off the absolute side instead made every recoil
    // point backwards for whichever player was p2.
    final dRow = attackerSide == mySide ? -1.0 : 1.0;
    recoil[UnitKey(side: attackerSide, slot: attackerSlot)] =
        (index: i, dx: dCol, dy: dRow);
  }

  // Apply floating damage/heal from the current event.
  if (events.isNotEmpty && limit < events.length) {
    final current = events[limit];

    switch (current) {
      case AttackEvent():
        // Floating damage on target. Lunge/projectile visuals are driven
        // directly from the event stream by CombatEffectsOverlay, not
        // from UnitVisualState (P4-FE-01).
        _setFloating(
          current.targetSide,
          current.targetSlot,
          current.damage,
          false,
          map,
        );
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

  // --- Enrich with computed trigger keys and debuff state ---
  for (final entry in map.entries) {
    final key = entry.key;
    final existing = entry.value;

    // Active debuff check: applied at or before limit, not yet expired.
    UnitDebuff? debuff;
    final expiryIdx = debuffExpiry[key];
    if (expiryIdx != null) {
      // Debuff expires at expiryIdx; still active before that.
      // We need the apply index to confirm it was applied before limit.
      for (var i = 0; i <= limit; i++) {
        final e = events[i];
        if (e is SlowEvent &&
            e.targetSide == key.side &&
            e.targetSlot == key.slot) {
          if (i < expiryIdx && expiryIdx > limit) {
            debuff = const UnitDebuff(type: 'slow', color: Color(0xFF42A5F5));
          }
          break;
        }
      }
    } else {
      // No expiry found — debuff persists indefinitely (healer never
      // attacked again). Check if any slow was applied before limit.
      for (var i = 0; i <= limit; i++) {
        final e = events[i];
        if (e is SlowEvent &&
            e.targetSide == key.side &&
            e.targetSlot == key.slot) {
          debuff = const UnitDebuff(type: 'slow', color: Color(0xFF42A5F5));
          break;
        }
      }
    }

    final r = recoil[key];
    map[key] = UnitVisualState(
      unitId: existing.unitId,
      star: existing.star,
      hp: existing.hp,
      maxHp: existing.maxHp,
      alive: existing.alive,
      floatingDamage: existing.floatingDamage,
      floatingIsHeal: existing.floatingIsHeal,
      healEventIndex: healEventIndex[key],
      lastDamageEventIndex: lastDamage[key],
      recoilEventIndex: r?.index,
      recoilDx: r?.dx ?? 0,
      recoilDy: r?.dy ?? 0,
      isMeleeAttacking: r != null && r.index == limit,
      debuff: debuff,
    );
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
        batch: identical(batch, _sentinel)
            ? this.batch
            : batch as CombatEventBatch?,
        playheadIndex: playheadIndex ?? this.playheadIndex,
        playheadProgress: playheadProgress ?? this.playheadProgress,
      );
}

const _sentinel = Object();

class _SlowEntry {
  const _SlowEntry(this.key, this.index);
  final UnitKey key;
  final int index;
}
