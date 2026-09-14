import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';

/// One tab — label + icon (**[MUST]** never colour alone).
class AppTab {
  const AppTab({required this.label, required this.icon});

  final String label;
  final IconData icon;
}

/// Segmented tab control — design spec §3.9.
///
/// Height 48 dp, 3 dp `primary` indicator, `labelLarge` text, selected in
/// `onSurface` / unselected in `onSurfaceVariant`, each tab ≥ 48 dp wide
/// with an icon + text.
class AppTabBar extends StatelessWidget {
  const AppTabBar({
    super.key,
    required this.tabs,
    required this.currentIndex,
    required this.onChanged,
  }) : assert(tabs.length >= 2);

  final List<AppTab> tabs;
  final int currentIndex;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          for (var i = 0; i < tabs.length; i++)
            Expanded(
              child: _Tab(
                tab: tabs[i],
                selected: i == currentIndex,
                onTap: () => onChanged(i),
              ),
            ),
        ],
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({required this.tab, required this.selected, required this.onTap});

  final AppTab tab;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final fg =
        selected ? t.colorScheme.onSurface : t.colorScheme.onSurfaceVariant;

    return Semantics(
      button: true,
      selected: selected,
      label: tab.label,
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minWidth: 48),
          decoration: BoxDecoration(
            border: Border(
              bottom: selected
                  ? BorderSide(width: 3, color: t.colorScheme.primary)
                  : BorderSide.none,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(tab.icon, size: 18, color: fg),
              const SizedBox(width: AppSpacing.xs),
              Flexible(
                child: Text(
                  tab.label,
                  overflow: TextOverflow.ellipsis,
                  style: t.textTheme.labelLarge?.copyWith(color: fg),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
