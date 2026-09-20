/// Pure, widget-free math for the combat effects overlay (P4-FE-01).
///
/// Kept separate from `combat_effects_overlay.dart` so it can be unit
/// tested without mounting any widget tree. Nothing in this file reads
/// live layout — the one function that does (`_tileCenterRelativeTo`)
/// lives in `combat_effects_overlay.dart` and calls `tileLocalCenter`
/// below.
library;

import 'dart:ui' show Offset;

import '../../../shared/models/combat_event.dart';
import '../../../shared/models/unit.dart';

/// The combat event active at [playheadProgress] (0.0-1.0 across the
/// whole batch) and how far through that event's own fixed-duration
/// window we are (0.0 = just started, 1.0 = about to advance).
///
/// Returns `null` for an empty [events] list.
({CombatEvent event, int index, double subProgress})? currentEventEffect(
  List<CombatEvent> events,
  double playheadProgress,
) {
  if (events.isEmpty) return null;
  final exact = playheadProgress.clamp(0.0, 1.0) * events.length;
  final index = exact.floor().clamp(0, events.length - 1);
  final subProgress = (exact - index).clamp(0.0, 1.0);
  return (event: events[index], index: index, subProgress: subProgress);
}

/// Triangle wave: 0→1 over the first half of [subProgress], 1→0 over the
/// second half. Drives "there and back" motion (the melee lunge) from a
/// single progress value instead of a separate one-shot
/// `AnimationController`.
double triangleWave(double subProgress) {
  final t = subProgress.clamp(0.0, 1.0);
  return t <= 0.5 ? t * 2 : (1 - t) * 2;
}

/// Smooth acceleration and braking, with the original impact at 50%.
/// Zero velocity at departure, impact and return avoids a sharp reversal.
double meleeTravel(double subProgress) {
  final t = triangleWave(subProgress);
  return t * t * (3 - 2 * t);
}

/// Local-space center of board [slot] (0-8, row-major: depth = slot ~/ 3
/// front..back, lane = slot % 3) inside a 3x3 grid sized [boardWidth] x
/// [boardHeight], with [spacing] between cells (matching the `GridView`'s
/// `mainAxisSpacing`/`crossAxisSpacing`).
///
/// [reverseRows] mirrors the opponent board's depth order (see
/// `_BoardPreview`'s `reverseRows` in `battle_view.dart`) so both sides'
/// front rows land next to the VS divider.
///
/// [landscape] must match the boards' own orientation: side-by-side
/// boards put depth on the *column* axis instead of the row axis (the
/// divider between them is vertical, not horizontal), or an attack drawn
/// by this function would travel toward the wrong screen edge — see
/// `_BoardPreview`'s `itemBuilder`, which this mirrors.
Offset tileLocalCenter({
  required int slot,
  required double boardWidth,
  required double boardHeight,
  required double spacing,
  bool reverseRows = false,
  bool landscape = false,
}) {
  final tileWidth = (boardWidth - 2 * spacing) / 3;
  final tileHeight = (boardHeight - 2 * spacing) / 3;
  final depth = slot ~/ 3;
  final lane = slot % 3;
  final int displayRow;
  final int displayCol;
  if (landscape) {
    displayCol = reverseRows ? depth : 2 - depth;
    displayRow = lane;
  } else {
    displayRow = reverseRows ? 2 - depth : depth;
    displayCol = lane;
  }
  return Offset(
    displayCol * (tileWidth + spacing) + tileWidth / 2,
    displayRow * (tileHeight + spacing) + tileHeight / 2,
  );
}

/// Where inside an event's window its outcome lands on the target — the
/// moment the damage, the floating number and the hit shake belong.
///
/// Effects used to be applied for the whole of an event's window, so the
/// target was already hit before the attacker had moved: a projectile
/// flew toward a unit whose HP had dropped at launch (#215). Pinning the
/// outcome to the moment of arrival is what makes a hit read as a hit.
///
/// Melee lands at the peak of [triangleWave], which is exactly where the
/// travelling sprite stands on the target's tile. A projectile lands just
/// short of the end of its flight, so it is still on screen when it
/// connects and only then disappears. Anything without travel — heals,
/// lifesteal, pierce, cycle bookkeeping — lands immediately.
double impactFraction(CombatEvent event) {
  if (event is! AttackEvent) return 0.0;
  final attackerUnitId = event.attackerUnitId;
  if (attackerUnitId == null) return 0.0;
  final isMelee =
      attackerUnitId == UnitId.fighter || attackerUnitId == UnitId.tank;
  return isMelee ? 0.5 : kProjectileImpactFraction;
}

/// Fraction of an event's window a projectile spends in flight. The
/// remainder is the beat after the hit, with the icon already gone —
/// short of 1.0 so an impact is a distinct moment rather than something
/// that happens as the next event starts.
const double kProjectileImpactFraction = 0.9;

/// Flight progress of a projectile from [subProgress] of its window: 0 at
/// the muzzle, 1 standing on the target. The shot completes its travel at
/// [kProjectileImpactFraction] rather than being still 10% short when it
/// connects, so the icon really does reach the target tile before it
/// disappears (#215).
double projectileTravel(double subProgress) =>
    (subProgress.clamp(0.0, 1.0) / kProjectileImpactFraction).clamp(0.0, 1.0);

/// Whether [event]'s outcome has landed by [subProgress] of its window.
/// A `null` event has nothing in flight.
bool hasImpacted(CombatEvent? event, double subProgress) =>
    event == null || subProgress >= impactFraction(event);
