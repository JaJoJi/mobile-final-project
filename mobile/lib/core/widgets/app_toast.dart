import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';

/// Toast variants — design spec §3.7.
enum AppToastVariant { info, success, danger }

/// Transient one-line messages — design spec §3.7.
///
/// A floating `SnackBar`, 4 s, one line + optional action.
///
/// **[MUST]** never for form-validation errors (those are inline), and
/// **[MUST]** never during a timed game phase — use the in-match banner.
abstract final class AppToast {
  static void show(
    BuildContext context,
    String message, {
    AppToastVariant variant = AppToastVariant.info,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    final scheme = Theme.of(context).colorScheme;

    final (icon, fg, bg) = switch (variant) {
      AppToastVariant.info => (
          Icons.info_outline,
          scheme.onSurface,
          scheme.surfaceContainerHigh,
        ),
      AppToastVariant.success => (
          Icons.check_circle_outline,
          scheme.onSurface,
          scheme.surfaceContainerHigh,
        ),
      AppToastVariant.danger => (
          Icons.error_outline,
          scheme.onErrorContainer,
          scheme.errorContainer,
        ),
    };

    final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        backgroundColor: bg,
        content: Row(
          children: [
            Icon(icon, size: 20, color: fg),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                message,
                style:
                    Theme.of(context).textTheme.bodyMedium?.copyWith(color: fg),
              ),
            ),
          ],
        ),
        action: (actionLabel != null && onAction != null)
            ? SnackBarAction(
                label: actionLabel,
                textColor: fg,
                onPressed: onAction,
              )
            : null,
      ),
    );
  }
}
