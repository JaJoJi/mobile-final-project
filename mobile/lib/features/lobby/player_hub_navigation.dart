import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/widgets/app_toast.dart';

enum PlayerHubTab { home, units, history, profile }

/// Full-width premium glass navigation shared by all Player Hub screens.
class PlayerHubNavigation extends StatelessWidget {
  const PlayerHubNavigation({super.key, required this.selected});

  final PlayerHubTab selected;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(AppSpacing.xl),
      ),
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: AppSpacing.lg,
          sigmaY: AppSpacing.lg,
        ),
        child: Container(
          key: const ValueKey('player-hub-navigation'),
          constraints: BoxConstraints(minHeight: 76 + bottomInset),
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
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(AppSpacing.xl),
            ),
            border: Border(
              top: BorderSide(color: Color(0xB359B7E8)),
            ),
            boxShadow: [
              BoxShadow(
                color: Color(0x99000000),
                blurRadius: AppSpacing.xl,
                offset: Offset(0, -AppSpacing.xs),
              ),
              BoxShadow(
                color: Color(0x241BD7FF),
                blurRadius: AppSpacing.lg,
                spreadRadius: AppSpacing.xxs,
              ),
            ],
          ),
          child: MediaQuery.withClampedTextScaling(
            maxScaleFactor: 1.3,
            child: Row(
              children: PlayerHubTab.values
                  .map(
                    (tab) => Expanded(
                      child: _NavigationItem(
                        tab: tab,
                        selected: tab == selected,
                        onTap: () => _select(context, tab),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        ),
      ),
    );
  }

  void _select(BuildContext context, PlayerHubTab next) {
    if (next == selected) return;
    switch (next) {
      case PlayerHubTab.home:
        context.go('/lobby');
      case PlayerHubTab.units:
        AppToast.show(context, 'ระบบยูนิตจะเปิดให้ใช้งานเร็ว ๆ นี้');
      case PlayerHubTab.history:
        context.go('/history');
      case PlayerHubTab.profile:
        context.go('/profile');
    }
  }
}

class _NavigationItem extends StatelessWidget {
  const _NavigationItem({
    required this.tab,
    required this.selected,
    required this.onTap,
  });

  final PlayerHubTab tab;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (label, icon, selectedIcon) = switch (tab) {
      PlayerHubTab.home => (
          'หน้าหลัก',
          Icons.home_outlined,
          Icons.home_rounded
        ),
      PlayerHubTab.units => (
          'ยูนิต',
          Icons.shield_outlined,
          Icons.shield_rounded,
        ),
      PlayerHubTab.history => (
          'ประวัติ',
          Icons.history_outlined,
          Icons.history_rounded,
        ),
      PlayerHubTab.profile => (
          'โปรไฟล์',
          Icons.person_outline_rounded,
          Icons.person_rounded,
        ),
    };
    final foreground =
        selected ? const Color(0xFFFFD35A) : const Color(0xFFB8CEF0);

    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadius.allMd,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            constraints: const BoxConstraints(minHeight: 64),
            decoration: BoxDecoration(
              gradient: selected
                  ? const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0x38FFD35A), Color(0x0AFFD35A)],
                    )
                  : null,
              borderRadius: AppRadius.allMd,
              border:
                  selected ? Border.all(color: const Color(0x4DFFD35A)) : null,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  width: selected ? AppSpacing.xxl : 0,
                  height: AppSpacing.xxs,
                  decoration: BoxDecoration(
                    color:
                        selected ? const Color(0xFFFFD35A) : Colors.transparent,
                    borderRadius: AppRadius.allFull,
                    boxShadow: selected
                        ? const [
                            BoxShadow(
                              color: Color(0x99FFD35A),
                              blurRadius: AppSpacing.sm,
                            ),
                          ]
                        : null,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Icon(
                  selected ? selectedIcon : icon,
                  color: foreground,
                  size: AppSpacing.xl,
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.fade,
                  softWrap: false,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: foreground,
                        fontWeight:
                            selected ? FontWeight.w800 : FontWeight.w600,
                        letterSpacing: selected ? 0.6 : 0.2,
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
