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
  });

  final String title;
  final Widget trailing;
  final String? subtitle;
  final IconData? leading;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        children: [
          if (leading != null) ...[
            Icon(leading, size: 20, color: t.colorScheme.onSurfaceVariant),
            const SizedBox(width: AppSpacing.md),
          ],
          Expanded(
            child: Column(
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
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          trailing,
        ],
      ),
    );
  }
}
