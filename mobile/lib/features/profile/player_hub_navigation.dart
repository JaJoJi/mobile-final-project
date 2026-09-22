import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_spacing.dart';

/// Persistent V2 navigation for player hub screens.
class PlayerHubNavigation extends StatelessWidget {
  const PlayerHubNavigation({super.key});

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(AppSpacing.xl),
      ),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: AppSpacing.lg, sigmaY: AppSpacing.lg),
        child: Container(
          key: const ValueKey('player-hub-navigation'),
          padding: EdgeInsets.fromLTRB(
            AppSpacing.sm,
            AppSpacing.xs,
            AppSpacing.sm,
            AppSpacing.xs + bottomInset,
          ),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xE6173853), Color(0xF20A1B2E)],
            ),
            border: Border(top: BorderSide(color: Color(0xB359B7E8))),
          ),
          child: MediaQuery.withClampedTextScaling(
            maxScaleFactor: 1.3,
            child: Row(
              children: [
                _NavItem(
                  label: 'หน้าหลัก',
                  icon: Icons.home_outlined,
                  onTap: () => context.go('/lobby'),
                ),
                const _NavItem(label: 'ยูนิต', icon: Icons.shield_outlined),
                _NavItem(
                  label: 'ประวัติ',
                  icon: Icons.history_outlined,
                  onTap: () => context.go('/history'),
                ),
                const _NavItem(
                  label: 'โปรไฟล์',
                  icon: Icons.person_rounded,
                  selected: true,
                ),
              ].map((item) => Expanded(child: item)).toList(),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.label,
    required this.icon,
    this.selected = false,
    this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    const gold = Color(0xFFFFD35A);
    final color = selected ? gold : const Color(0xFFB8CEF0);
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.allMd,
        child: Container(
          constraints: const BoxConstraints(minHeight: 64),
          decoration: selected
              ? BoxDecoration(
                  borderRadius: AppRadius.allMd,
                  border: Border.all(color: const Color(0x4DFFD35A)),
                )
              : null,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: AppSpacing.xl),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.fade,
                softWrap: false,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: color,
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
