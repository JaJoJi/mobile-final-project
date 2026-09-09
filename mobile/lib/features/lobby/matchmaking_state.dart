import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ws/ws_client.dart';
import '../../core/ws/ws_providers.dart';
import '../../shared/models/game_events.dart';

/// Matchmaking state machine for the lobby screen.
///
/// * `idle`      — default. "Find match" button enabled.
/// * `searching` — user tapped Find match. `game:matchmaking:join` was
///                 emitted; we're waiting for the server to pair us.
/// * `matched`   — server paired us. The lobby screen auto-navigates to
///                 `/match/<id>` after a short delay (set in
///                 `LobbyScreen`).
///
/// Transitions:
///   * `idle → searching` via [beginSearch] (emits `game:matchmaking:join`)
///   * `searching → idle` via [cancelSearch] (emits `game:matchmaking:leave`)
///   * `searching → matched` via [markMatched] (called from the
///     `matchPhaseProvider` listener in `LobbyScreen`)
///
/// `idle → matched` and `matched → idle` are intentionally not supported:
/// the lobby isn't meant to be on screen while a match is in flight.
enum MatchmakingState { idle, searching, matched }

class MatchmakingStateNotifier extends StateNotifier<MatchmakingState> {
  MatchmakingStateNotifier(this._client) : super(MatchmakingState.idle);

  final WsClient _client;

  /// Idle → searching + emit `game:matchmaking:join`.
  ///
  /// Idempotent: calling while already `searching` is a no-op (the button
  /// is disabled in that state, but defensive callers should be safe).
  void beginSearch() {
    if (state == MatchmakingState.searching) return;
    _client.emit(GameActions.matchmakingJoin, const {});
    state = MatchmakingState.searching;
  }

  /// Searching → idle + emit `game:matchmaking:leave`.
  ///
  /// Idempotent: calling while already `idle` is a no-op.
  void cancelSearch() {
    if (state != MatchmakingState.searching) return;
    _client.emit(GameActions.matchmakingLeave, const {});
    state = MatchmakingState.idle;
  }

  /// Searching → matched.
  ///
  /// Called from `LobbyScreen` when a `game:match:phase` event lands while
  /// we're in the `searching` state. Calling outside of `searching` is
  /// a no-op so a stale event arriving after navigation can't unhelpfully
  /// reset state.
  void markMatched() {
    if (state != MatchmakingState.searching) return;
    state = MatchmakingState.matched;
  }
}

final matchmakingStateProvider =
    StateNotifierProvider<MatchmakingStateNotifier, MatchmakingState>(
  (ref) => MatchmakingStateNotifier(ref.watch(wsClientProvider)),
);
