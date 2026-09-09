import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/widgets/app_scaffold.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/widgets/state_views.dart';
import '../../core/ws/ws_client.dart';
import '../../core/ws/ws_providers.dart';
import '../../shared/models/game_events.dart';
import 'find_match_button.dart';
import 'logout_button.dart';
import 'matchmaking_state.dart';
import 'profile_card.dart';

/// The authenticated landing screen — `/lobby`.
///
/// Layout (top to bottom):
///   * AppBar — title + [LogoutButton] action
///   * [ProfileCard] — fetched once on mount
///   * spacer (lg)
///   * [FindMatchButton] — the only primary CTA
///   * status text under the button ("Searching…", "Match found!")
///
/// State machine ([MatchmakingState]):
///   * `idle`      — button "Find match"
///   * `searching` — button "Cancel", status text "Searching…"
///   * `matched`   — 500 ms "Match found!" toast, then `context.go('/match/<id>')`
///
/// Auto-navigation: a `ref.listen` on `matchPhaseProvider` flips the
/// state to `matched` when a phase event arrives while we're `searching`.
/// The screen itself watches the state and triggers the nav + toast.
class LobbyScreen extends ConsumerStatefulWidget {
  const LobbyScreen({super.key});

  static const path = '/lobby';

  /// Delay between the "Match found!" toast and the navigation. Long
  /// enough for the user to see the toast, short enough to feel snappy.
  static const _navDelay = Duration(milliseconds: 500);

  @override
  ConsumerState<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends ConsumerState<LobbyScreen> {
  bool _navigating = false;

  @override
  Widget build(BuildContext context) {
    // React to phase events landing while we're searching.
    ref.listen<AsyncValue<MatchPhaseEvent>>(matchPhaseProvider, (prev, next) {
      final phase = next.valueOrNull;
      if (phase == null) return;
      final state = ref.read(matchmakingStateProvider);
      if (state != MatchmakingState.searching) return;
      _onMatchFound(phase);
    });

    final state = ref.watch(matchmakingStateProvider);
    final wsState = ref.watch(wsConnectionStateProvider);
    final connectionStatus = switch (wsState.valueOrNull) {
      WsConnectionState.connected => ConnectionStatus.connected,
      WsConnectionState.connecting => ConnectionStatus.connecting,
      WsConnectionState.reconnecting => ConnectionStatus.reconnecting,
      WsConnectionState.disconnected => ConnectionStatus.disconnected,
      null => ConnectionStatus.connected, // initial frame before first emit
    };

    return AppScaffold(
      title: 'Auto Chess',
      actions: const [LogoutButton()],
      connectionStatus: connectionStatus,
      onReconnect: () {
        // No-op — the WsClient owns reconnection; the banner just surfaces it.
      },
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const ProfileCard(),
          const Spacer(),
          const Center(child: FindMatchButton()),
          const SizedBox(height: AppSpacing.md),
          Center(child: _StatusText(state: state)),
          const Spacer(),
        ],
      ),
    );
  }

  Future<void> _onMatchFound(MatchPhaseEvent phase) async {
    if (_navigating) return;
    _navigating = true;

    ref.read(matchmakingStateProvider.notifier).markMatched();

    if (mounted) {
      AppToast.show(
        context,
        'Match found!',
        variant: AppToastVariant.success,
      );
    }

    // Auto-navigate after the toast has had time to register visually.
    await Future<void>.delayed(LobbyScreen._navDelay);
    if (!mounted) return;
    context.go('/match/${phase.matchId}');
  }
}

/// Status line under the Find match button.
class _StatusText extends StatelessWidget {
  const _StatusText({required this.state});

  final MatchmakingState state;

  @override
  Widget build(BuildContext context) {
    final (text, style) = switch (state) {
      MatchmakingState.idle => (
        null,
        Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.outline,
            ),
      ),
      MatchmakingState.searching => (
        'Searching…',
        Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w500,
            ),
      ),
      MatchmakingState.matched => (
        'Match found!',
        Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w700,
            ),
      ),
    };
    return SizedBox(
      height: AppSpacing.xl,
      child: text == null
          ? const SizedBox.shrink()
          : Text(text, style: style),
    );
  }
}
