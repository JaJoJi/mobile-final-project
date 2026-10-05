import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/ws/ws_providers.dart';
import '../../shared/models/game_events.dart';
import '../match/match_entry_transition.dart';
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
  });

  final GoRouter router;
  final Widget child;

  @override
  ConsumerState<MatchmakingNavigationCoordinator> createState() =>
      _MatchmakingNavigationCoordinatorState();
}

class _MatchmakingNavigationCoordinatorState
    extends ConsumerState<MatchmakingNavigationCoordinator> {
  bool _navigating = false;
  MatchPhaseEvent? _matchedPhase;

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
      setState(() {
        _navigating = true;
        _matchedPhase = phase;
      });
    });

    final phase = _matchedPhase;
    return Stack(
      textDirection: TextDirection.ltr,
      children: [
        widget.child,
        if (phase != null)
          MatchEntryTransition(
            matchId: phase.matchId,
            leftName: _playerName(phase, 0, 'ผู้เล่น 1'),
            rightName: _playerName(phase, 1, 'ผู้เล่น 2'),
            onReady: () => _openMatch(phase.matchId),
          ),
      ],
    );
  }

  String _playerName(MatchPhaseEvent phase, int index, String fallback) {
    if (index >= phase.players.length) return fallback;
    final name = phase.players[index].username?.trim();
    return name == null || name.isEmpty ? fallback : name;
  }

  Future<void> _openMatch(String matchId) async {
    if (!mounted) return;

    widget.router.go('/match/${Uri.encodeComponent(matchId)}');
    // Keep the encounter above the outgoing page until routing has rebuilt
    // and the destination has painted. Completion can fire inside a frame.
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    setState(() {
      _matchedPhase = null;
      _navigating = false;
    });
  }
}
