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

/// Preferred duration for each combat event on the playhead.
///
/// This deliberately sits close to the compressed rate of a real dense
/// battle. The old 1600ms preference made sparse boards play at 1600ms per
/// action while a 77-event board hit the round cap and fell to ~675ms per
/// action — so adding units visibly doubled animation speed. A 900ms target
/// keeps sparse and dense boards in the same visual range while leaving each
/// hit readable with the local impact animations layered on top.
const Duration kCombatEventDuration = Duration(milliseconds: 900);

/// Hard ceiling on one round's replay. The server abandons a round after
/// `COMBAT_DONE_TIMEOUT_MS` (60s) if it hasn't received both clients'
/// `combat_done` acks, so a replay longer than that hangs the match: a
/// real 77-event round at the preferred rate would run over two minutes.
/// Long rounds compress rather than overrun.
///
/// Kept below the server's 60-second acknowledgement timeout. At this cap a
/// known 77-event dense round runs at ~714ms per event, only ~21% faster than
/// a sparse round's 900ms instead of the old 2.37x difference.
const Duration kMaxCombatPlayback = Duration(seconds: 55);

/// Most of a replay a late client is allowed to fast-forward past so it
/// can line up with the client that got the batch first.
///
/// Catch-up exists to absorb *delivery* latency — the tens of
/// milliseconds between the server publishing a batch and a client
/// painting its first frame of it — by comparing the server's `endedAt`
/// against the client's own clock. Those are two different machines'
/// wall clocks, and nothing keeps them in step: a backend container
/// whose clock has drifted, or a batch that sat in a throttled tab,
/// makes the difference arbitrarily large.
///
/// Capping it is what stops that difference from being mistaken for
/// "this replay is already over". Without a cap, any disagreement larger
/// than one replay skipped combat entirely and acked `combat_done`
/// roughly two seconds in, so the round resolved before a single attack
/// was drawn.
///
/// The cost of the cap is that a genuine mid-replay reconnect now
/// over-plays instead of catching up, and may miss the server's
/// `COMBAT_DONE_TIMEOUT_MS` window — in which case the server advances
/// the round itself. Playing combat and occasionally falling back to the
/// server timeout is the better failure of the two.
const Duration kMaxPlaybackCatchUp = Duration(seconds: 3);

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
  /// Filters out `cycle_end`/`battle_end` (no visual representation,
  /// would otherwise waste a full event slot on the playhead) and
  /// `death` (the backend's `applyDamage` emits `death` immediately
  /// before its own `attack` event for the SAME lethal hit — the
  /// `attack` event already carries `targetHpAfter: 0` and a snapshot
  /// with the target dead, so `death` has nothing left for the client to
  /// show). Left in, `death` became its own playhead slot that revealed
  /// the target as dead a full event *before* the attacker's own
  /// travel/impact animation for that exact kill played, so every single
  /// kill looked like a still-alive unit attacking a target the board
  /// was already showing as dead.
  void loadBatch(CombatEventBatch batch) {
    final effective = batch.events
        .where(
          (e) =>
              e is! CycleEndEvent && e is! BattleEndEvent && e is! DeathEvent,
        )
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
