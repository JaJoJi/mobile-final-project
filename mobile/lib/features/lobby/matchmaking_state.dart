import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ws/ws_client.dart';
import '../../core/ws/ws_providers.dart';
import '../../shared/models/game_events.dart';

/// Matchmaking state machine for the lobby screen.
///
/// * `idle`      — default. "Find match" button enabled.
/// * `joining`   — join request sent; waiting for the server ACK.
/// * `searching` — user tapped Find match. `game:matchmaking:join` was
///                 acknowledged; we're waiting for the server to pair us.
/// * `matched`   — server paired us. The lobby screen auto-navigates to
///                 `/match/<id>` after a short delay (set in
///                 `LobbyScreen`).
///
/// Transitions:
///   * `idle → joining → searching` via [beginSearch]
///     (emits `game:matchmaking:join` and waits for its acknowledgement)
///   * `searching → idle` via [cancelSearch] (emits `game:matchmaking:leave`)
///   * `searching → matched` via [markMatched] (called from the
///     `matchPhaseProvider` listener in `LobbyScreen`)
///
/// `matched → idle` happens when a fresh lobby screen mounts after the match.
enum MatchmakingState { idle, joining, searching, matched }

class MatchmakingStateNotifier extends StateNotifier<MatchmakingState> {
  MatchmakingStateNotifier(this._client) : super(MatchmakingState.idle) {
    _connectionSubscription = _client.connectionState.listen((connection) {
      if (connection != WsConnectionState.connected &&
          (state == MatchmakingState.joining ||
              state == MatchmakingState.searching)) {
        state = MatchmakingState.idle;
      }
    });
  }

  final WsClient _client;
  late final StreamSubscription<WsConnectionState> _connectionSubscription;

  /// Idle → searching + emit `game:matchmaking:join`.
  ///
  /// Idempotent: calling while already `searching` is a no-op (the button
  /// is disabled in that state, but defensive callers should be safe).
  Future<void> beginSearch() async {
    if (state != MatchmakingState.idle) return;
    // Socket.IO drops emits made before the namespace is connected. Keep the
    // UI honest instead of showing "Searching" for a request that never left
    // the device.
    if (!_client.isConnected) return;
    state = MatchmakingState.joining;
    try {
      await _client.emitWithAck(GameActions.matchmakingJoin);
      if (mounted && state == MatchmakingState.joining) {
        state = MatchmakingState.searching;
      }
    } on Object {
      if (mounted && state == MatchmakingState.joining) {
        state = MatchmakingState.idle;
      }
    }
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
    if (state != MatchmakingState.joining &&
        state != MatchmakingState.searching) {
      return;
    }
    state = MatchmakingState.matched;
  }

  /// Clears the completed match marker when the user returns to the lobby.
  ///
  /// Deliberately leaves `joining` and `searching` untouched so rebuilding
  /// the lobby can never cancel an active queue request by accident.
  void resetAfterMatch() {
    if (state == MatchmakingState.matched) {
      state = MatchmakingState.idle;
    }
  }

  @override
  void dispose() {
    unawaited(_connectionSubscription.cancel());
    super.dispose();
  }
}

final matchmakingStateProvider =
    StateNotifierProvider<MatchmakingStateNotifier, MatchmakingState>(
  (ref) => MatchmakingStateNotifier(ref.watch(wsClientProvider)),
);
