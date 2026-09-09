import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets/app_button.dart';
import 'matchmaking_state.dart';

/// The lobby's primary CTA.
///
/// Reads [matchmakingStateProvider] for current state. Label + onPressed
/// delegate to the state notifier, so all WS emit lives in one place
/// (`MatchmakingStateNotifier.beginSearch` / `.cancelSearch`).
///
/// States:
///   * `idle`      → "Find match" (primary, lg)
///   * `searching` → "Cancel"     (secondary, lg)
///   * `matched`   → "Match found!" (disabled, lg) — the screen auto-navigates
///                 away within ~500 ms so this state is rarely seen.
class FindMatchButton extends ConsumerWidget {
  const FindMatchButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(matchmakingStateProvider);
    final notifier = ref.read(matchmakingStateProvider.notifier);

    final (label, onPressed) = switch (state) {
      MatchmakingState.idle => (
        const Text('Find match'),
        notifier.beginSearch,
      ),
      MatchmakingState.searching => (
        const Text('Cancel'),
        notifier.cancelSearch,
      ),
      MatchmakingState.matched => (
        const Text('Match found!'),
        null, // disabled — auto-nav takes over
      ),
    };

    return AppButton(
      onPressed: onPressed,
      variant: state == MatchmakingState.searching
          ? AppButtonVariant.secondary
          : AppButtonVariant.primary,
      size: AppButtonSize.lg,
      child: label,
    );
  }
}
