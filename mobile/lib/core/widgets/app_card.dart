import 'package:flutter/material.dart';

import '../theme/app_motion.dart';
import '../theme/app_spacing.dart';

/// Card variants — design spec §3.2.
enum AppCardVariant {
  /// level1, 1 dp divider border on light theme.
  flat,

  /// level2 — for selected / dragging content.
  raised,

  /// adds an `InkWell` + ripple.
  interactive,
}

/// The shared surface for grouped content — design spec §3.2.
///
/// States: `default` · `selected` (2 dp `primary` border) ·
/// `disabled` (40 % opacity) · `dragging` (scale 1.05, level2).
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.variant = AppCardVariant.flat,
    this.selected = false,
    this.disabled = false,
    this.dragging = false,
    this.onTap,
    this.padding = const EdgeInsets.all(AppSpacing.md),
  });

  final Widget child;
  final AppCardVariant variant;
  final bool selected;
  final bool disabled;
  final bool dragging;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isLight = Theme.of(context).brightness == Brightness.light;

    final elevation = (variant == AppCardVariant.raised || dragging)
        ? AppElevation.level2
        : AppElevation.level1;

    final border = selected
        ? Border.all(color: scheme.primary, width: 2)
        : (variant == AppCardVariant.flat && isLight)
            ? Border.all(color: scheme.outlineVariant)
            : null;

    Widget surface = Material(
      color: scheme.surfaceContainer,
      elevation: elevation,
      borderRadius: AppRadius.allMd,
      clipBehavior: Clip.antiAlias,
      child: DecoratedBox(
        decoration:
            BoxDecoration(border: border, borderRadius: AppRadius.allMd),
        child: variant == AppCardVariant.interactive || onTap != null
            ? InkWell(
                onTap: disabled ? null : onTap,
                child: Padding(padding: padding, child: child),
              )
            : Padding(padding: padding, child: child),
      ),
    );

    if (dragging) {
      surface = AnimatedScale(
        scale: 1.05,
        duration: AppMotion.short4,
        curve: AppMotion.emphasized,
        child: surface,
      );
    }

    if (disabled) {
      surface = Opacity(opacity: 0.4, child: surface);
    }

    return surface;
  }
}
