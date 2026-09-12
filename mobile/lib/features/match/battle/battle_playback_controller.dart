/// `BattlePlaybackController` — owns the loaded `CombatEventBatch` and
/// the current playhead position for the in-match combat player.
///
/// For 2a this is a `StateNotifier` that the widget's `AnimationController`
/// pushes values into (via [seekTo]). The widget owns the `vsync`; the
/// controller just holds derived state. Sub-steps 2b–2e will replace
/// [BattleVisualState] with per-unit visual state without changing the
/// controller's public surface.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/combat_event.dart';
import 'battle_visual_state.dart';

/// One-shot duration for every combat event on the playhead. Per the
/// locked Step 2 plan, 600 ms is the single global constant; speed
/// multipliers are explicitly out of scope for the MVP.
const Duration kCombatEventDuration = Duration(milliseconds: 600);

class BattlePlaybackController extends StateNotifier<BattleVisualState> {
  BattlePlaybackController() : super(BattleVisualState.empty);

  /// Load a fresh batch from the server. Resets the playhead to 0.
  void loadBatch(CombatEventBatch batch) {
    state = BattleVisualState(
      batch: batch,
      playheadIndex: 0,
      playheadProgress: 0.0,
    );
  }

  /// Update the playhead. Called by the widget's `AnimationController`
  /// listener on every frame.
  void seekTo(double progress) {
    final batch = state.batch;
    if (batch == null) return;
    final clamped = progress.clamp(0.0, 1.0);
    final index = (clamped * batch.events.length).floor().clamp(
          0,
          batch.events.isEmpty ? 0 : batch.events.length - 1,
        );
    state = state.copyWith(
      playheadIndex: index,
      playheadProgress: clamped,
    );
  }

  /// Fast-forward straight to the end (the skip button calls this).
  void finish() {
    final batch = state.batch;
    if (batch == null) return;
    state = state.copyWith(
      playheadIndex: batch.events.isEmpty ? 0 : batch.events.length - 1,
      playheadProgress: 1.0,
    );
  }

  /// Read-only view of the loaded events. `null` when no batch arrived.
  List<CombatEvent>? get events => state.batch?.events;
}
