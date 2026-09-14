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

/// Preferred duration for each combat event on the playhead. Bumped from
/// the original 600ms (locked Step 2 plan) to 1000ms after live testing
/// showed combat resolving too fast to follow (P4-FE-01 follow-up).
///
/// This is a *preferred* rate, not a guarantee — see [kMaxCombatPlayback]
/// and [combatPlaybackDuration].
const Duration kCombatEventDuration = Duration(milliseconds: 1000);

/// Hard ceiling on one round's replay. The server abandons a round after
/// `COMBAT_DONE_TIMEOUT_MS` (60s) if it hasn't received both clients'
/// `combat_done` acks, so a replay longer than that hangs the match: a
/// real 77-event round at the preferred rate would run 77s. Long rounds
/// compress rather than overrun.
const Duration kMaxCombatPlayback = Duration(seconds: 30);

/// Total playback time for [eventCount] events: the preferred rate, or a
/// compressed rate when that would exceed [kMaxCombatPlayback].
Duration combatPlaybackDuration(int eventCount) {
  final preferred = kCombatEventDuration * eventCount;
  return preferred > kMaxCombatPlayback ? kMaxCombatPlayback : preferred;
}

class BattlePlaybackController extends StateNotifier<BattleVisualState> {
  BattlePlaybackController() : super(BattleVisualState.empty);

  /// Load a fresh batch from the server. Resets the playhead to 0.
  ///
  /// Filters out `cycle_end` and `battle_end` events which have no visual
  /// representation and would otherwise waste 600 ms each on the playhead.
  void loadBatch(CombatEventBatch batch) {
    final effective = batch.events
        .where((e) => e is! CycleEndEvent && e is! BattleEndEvent)
        .toList(growable: false);
    state = BattleVisualState(
      batch: CombatEventBatch(
        matchId: batch.matchId,
        round: batch.round,
        cycleCount: batch.cycleCount,
        endedAt: batch.endedAt,
        events: effective,
      ),
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
