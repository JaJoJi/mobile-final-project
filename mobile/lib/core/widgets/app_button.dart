import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';

/// Button variants — design spec §3.1.
enum AppButtonVariant {
  /// `FilledButton` — the one primary action per screen.
  primary,

  /// `FilledButton.tonal` — frequent secondary action (e.g. refresh shop).
  secondary,

  /// `FilledButton` tinted with `colorScheme.error` — destructive, needs confirm.
  danger,

  /// `TextButton` — light navigation / link.
  ghost,
}

/// Button sizes — design spec §3.1.
enum AppButtonSize {
  /// 40 dp.
  sm,

  /// 48 dp (default).
  md,

  /// 56 dp — in-match actions.
  lg,
}

/// The shared button — design spec §3.1.
///
/// * `loading` swaps the label for a spinner, freezes the width and makes
///   the button non-tappable (double-submit guard) **[MUST]**.
/// * A disabled button (`onPressed == null`, not loading) **[MUST]** explain
///   itself: pass `disabledReason` and it is shown as a tooltip + helper
///   line below.
/// * Labels are verbs — never "OK" / "Submit".
class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.variant = AppButtonVariant.primary,
    this.size = AppButtonSize.md,
    this.loading = false,
    this.fullWidth = true,
    this.icon,
    this.disabledReason,
  });

  final VoidCallback? onPressed;
  final Widget child;
  final AppButtonVariant variant;
  final AppButtonSize size;
  final bool loading;
  final bool fullWidth;
  final IconData? icon;

  /// Shown when the button is disabled so the player knows why.
  final String? disabledReason;

  double get _height => switch (size) {
        AppButtonSize.sm => 40,
        AppButtonSize.md => 48,
        AppButtonSize.lg => 56,
      };

  bool get _isDisabled => onPressed == null && !loading;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final effectiveOnPressed = loading ? null : onPressed;

    final label = loading
        ? SizedBox(
            height: 16,
            width: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: variant == AppButtonVariant.ghost
                  ? scheme.primary
                  : scheme.onPrimary,
            ),
          )
        : child;

    final content = icon != null && !loading
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18),
              const SizedBox(width: AppSpacing.sm),
              Flexible(child: label),
            ],
          )
        : label;

    final minSize = fullWidth ? Size.fromHeight(_height) : Size(0, _height);

    Widget button = switch (variant) {
      AppButtonVariant.primary => FilledButton(
          onPressed: effectiveOnPressed,
          style: FilledButton.styleFrom(minimumSize: minSize),
          child: content,
        ),
      AppButtonVariant.secondary => FilledButton.tonal(
          onPressed: effectiveOnPressed,
          style: FilledButton.styleFrom(minimumSize: minSize),
          child: content,
        ),
      AppButtonVariant.danger => FilledButton(
          onPressed: effectiveOnPressed,
          style: FilledButton.styleFrom(
            minimumSize: minSize,
            backgroundColor: scheme.error,
            foregroundColor: scheme.onError,
          ),
          child: content,
        ),
      AppButtonVariant.ghost => TextButton(
          onPressed: effectiveOnPressed,
          style: TextButton.styleFrom(minimumSize: minSize),
          child: content,
        ),
    };

    if (_isDisabled && disabledReason != null) {
      button = Tooltip(message: disabledReason!, child: button);
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          button,
          const SizedBox(height: AppSpacing.xs),
          Text(
            disabledReason!,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      );
    }

    return button;
  }
}
