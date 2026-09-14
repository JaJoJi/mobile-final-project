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

/// Local-space center of board [slot] (0-8, row-major) inside a 3x3 grid
/// sized [boardWidth] x [boardHeight], with [spacing] between cells
/// (matching the `GridView`'s `mainAxisSpacing`/`crossAxisSpacing`).
///
/// [reverseRows] mirrors the opponent board's row order (see
/// `_BoardPreview`'s `reverseRows` in `battle_view.dart`).
Offset tileLocalCenter({
  required int slot,
  required double boardWidth,
  required double boardHeight,
  required double spacing,
  bool reverseRows = false,
}) {
  final tileWidth = (boardWidth - 2 * spacing) / 3;
  final tileHeight = (boardHeight - 2 * spacing) / 3;
  final row = slot ~/ 3;
  final col = slot % 3;
  final displayRow = reverseRows ? 2 - row : row;
  return Offset(
    col * (tileWidth + spacing) + tileWidth / 2,
    displayRow * (tileHeight + spacing) + tileHeight / 2,
  );
}
