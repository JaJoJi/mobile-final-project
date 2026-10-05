import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/ws/ws_providers.dart';
import '../../shared/models/game_events.dart';
import 'matchmaking_state.dart';

/// Keeps quick-match navigation alive above every authenticated screen.
///
/// The matchmaking queue deliberately survives navigation around the Player
/// Hub. The matching phase event therefore has to be observed above those
/// pages too; otherwise a player who leaves the lobby remains paired on the
/// server but never opens the match on this device.
class MatchmakingNavigationCoordinator extends ConsumerStatefulWidget {
  const MatchmakingNavigationCoordinator({
    super.key,
    required this.router,
    required this.child,
    this.navigationDelay = const Duration(milliseconds: 500),
  });

  final GoRouter router;
  final Widget child;
  final Duration navigationDelay;

  @override
  ConsumerState<MatchmakingNavigationCoordinator> createState() =>
      _MatchmakingNavigationCoordinatorState();
}

class _MatchmakingNavigationCoordinatorState
    extends ConsumerState<MatchmakingNavigationCoordinator> {
  bool _navigating = false;

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<MatchPhaseEvent>>(matchPhaseProvider, (_, next) {
      final phase = next.valueOrNull;
      if (phase == null || _navigating) return;

      final matchmaking = ref.read(matchmakingStateProvider);
      if (matchmaking != MatchmakingState.joining &&
          matchmaking != MatchmakingState.searching) {
        return;
      }

      ref.read(matchmakingStateProvider.notifier).markMatched();
      _navigating = true;
      unawaited(_openMatch(phase.matchId));
    });

    return widget.child;
  }

  Future<void> _openMatch(String matchId) async {
    await Future<void>.delayed(widget.navigationDelay);
    if (!mounted) return;

    widget.router.go('/match/${Uri.encodeComponent(matchId)}');
    _navigating = false;
  }
}
