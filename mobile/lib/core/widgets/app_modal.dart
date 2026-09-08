import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';

/// Dialogs and bottom sheets — design spec §3.8.
///
/// **[MUST]** Destructive confirms put the safe (cancel) action on the
/// left and give it default focus. **[MUST]** Nothing here may be opened
/// while a phase timer is running — the match screen uses a top banner or
/// a translucent overlay that keeps the board visible.
abstract final class AppModal {
  /// A yes/no confirm. Returns `true` only if the user picks [confirmLabel].
  ///
  /// [destructive] tints the confirm button with the error colour; the
  /// cancel button stays on the left with autofocus either way.
  static Future<bool> confirm(
    BuildContext context, {
    required String title,
    required String message,
    required String confirmLabel,
    String cancelLabel = 'ยกเลิก',
    bool destructive = false,
  }) async {
    final scheme = Theme.of(context).colorScheme;
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          // safe action first → renders left
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(cancelLabel),
          ),
          FilledButton(
            style: destructive
                ? FilledButton.styleFrom(
                    backgroundColor: scheme.error,
                    foregroundColor: scheme.onError,
                  )
                : null,
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  /// A detail bottom sheet with a drag handle (from theme) and rounded top.
  static Future<T?> sheet<T>(
    BuildContext context, {
    required WidgetBuilder builder,
    bool dismissible = true,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      isDismissible: dismissible,
      enableDrag: dismissible,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            0,
            AppSpacing.lg,
            AppSpacing.lg,
          ),
          child: builder(context),
        ),
      ),
    );
  }
}
