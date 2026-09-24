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
  const FindMatchButton({required this.enabled, super.key});

  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(matchmakingStateProvider);
    final notifier = ref.read(matchmakingStateProvider.notifier);

    final (label, onPressed) = switch (state) {
      MatchmakingState.idle => (
          const Text('จับคู่ด่วน'),
          enabled ? () => notifier.beginSearch() : null,
        ),
      MatchmakingState.joining => (
          const Text('กำลังเข้าคิว…'),
          null,
        ),
      MatchmakingState.searching => (
          const Text('ยกเลิก'),
          notifier.cancelSearch,
        ),
      MatchmakingState.matched => (
          const Text('พบคู่แข่งแล้ว!'),
          null, // disabled — auto-nav takes over
        ),
    };

    return AppButton(
      onPressed: onPressed,
      variant: state == MatchmakingState.searching
          ? AppButtonVariant.secondary
          : AppButtonVariant.primary,
      size: AppButtonSize.lg,
      icon: state == MatchmakingState.idle ? Icons.sports_martial_arts : null,
      child: label,
    );
  }
}
