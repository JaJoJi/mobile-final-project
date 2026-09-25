import 'package:flutter/material.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/widgets/fantasy_page.dart';

/// Shared arena shell used by Player Hub destinations.
class PlayerHubShell extends StatelessWidget {
  const PlayerHubShell({
    super.key,
    required this.title,
    required this.subtitle,
    required this.body,
    required this.navigation,
    this.badge,
    this.headerAction,
  });

  final String title;
  final String subtitle;
  final String? badge;
  final Widget? headerAction;
  final Widget body;
  final Widget navigation;

  @override
  Widget build(BuildContext context) => Theme(
        data: fantasySurfaceTheme(context),
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: FantasyBackdrop(
            child: SafeArea(
              child: Column(
                children: [
                  _PlayerHubHeader(
                    title: title,
                    subtitle: subtitle,
                    badge: badge,
                    action: headerAction,
                  ),
                  Expanded(child: body),
                  navigation,
                ],
              ),
            ),
          ),
        ),
      );
}

class _PlayerHubHeader extends StatelessWidget {
  const _PlayerHubHeader({
    required this.title,
    required this.subtitle,
    required this.badge,
    required this.action,
  });

  final String title;
  final String subtitle;
  final String? badge;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.md,
          AppSpacing.lg,
          AppSpacing.md,
        ),
        decoration: const BoxDecoration(
          color: Color(0xB3071220),
          border: Border(bottom: BorderSide(color: Color(0x4D82A9C7))),
        ),
        child: MediaQuery.withClampedTextScaling(
          maxScaleFactor: 1.25,
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
              if (action != null) ...[
                const SizedBox(width: AppSpacing.sm),
                action!,
              ],
              if (badge != null) ...[
                const SizedBox(width: AppSpacing.sm),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: AppSpacing.xs,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(color: const Color(0x80F2C14E)),
                    borderRadius: AppRadius.allSm,
                  ),
                  child: Text(badge!),
                ),
              ],
            ],
          ),
        ),
      );
}
