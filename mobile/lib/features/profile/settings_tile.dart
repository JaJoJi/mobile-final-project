import 'package:flutter/material.dart';

import '../../core/theme/app_spacing.dart';

/// One row in the profile settings list — P1-FE-02.
///
/// `title` on the left, an arbitrary [trailing] control (Switch, segmented
/// button, text) on the right, optional [subtitle] below the title.
class SettingsTile extends StatelessWidget {
  const SettingsTile({
    super.key,
    required this.title,
    required this.trailing,
    this.subtitle,
    this.leading,
    this.stackTrailing = false,
  });

  final String title;
  final Widget trailing;
  final String? subtitle;
  final IconData? leading;

  /// Render [trailing] full-width below the title instead of to its right.
  /// Use for wide controls (a segmented button) that would overflow the row
  /// at large text scales.
  final bool stackTrailing;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);

    final titleBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: t.textTheme.bodyLarge),
        if (subtitle != null)
          Text(
            subtitle!,
            style: t.textTheme.bodyMedium
                ?.copyWith(color: t.colorScheme.onSurfaceVariant),
          ),
      ],
    );

    final leadingIcon = leading != null
        ? Padding(
            padding: const EdgeInsets.only(right: AppSpacing.md),
            child:
                Icon(leading, size: 20, color: t.colorScheme.onSurfaceVariant),
          )
        : const SizedBox.shrink();

    // Merge so the control (Switch etc.) inherits the title as its label.
    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: stackTrailing
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [leadingIcon, Expanded(child: titleBlock)]),
                  const SizedBox(height: AppSpacing.sm),
                  // Wide control — let it scroll rather than overflow at
                  // large text scales / narrow screens.
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: trailing,
                  ),
                ],
              )
            : Row(
                children: [
                  leadingIcon,
                  Expanded(child: titleBlock),
                  const SizedBox(width: AppSpacing.md),
                  trailing,
                ],
              ),
      ),
    );
  }
}
