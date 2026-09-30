import 'package:flutter/material.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/widgets/unit_avatar.dart';
import '../../core/widgets/unit_detail_sheet.dart';
import '../../shared/models/unit_catalog.dart';
import '../lobby/player_hub_navigation.dart';
import '../player_hub/player_hub_shell.dart';

class UnitsScreen extends StatelessWidget {
  const UnitsScreen({super.key});

  static const path = '/units';

  @override
  Widget build(BuildContext context) => PlayerHubShell(
        title: 'สารานุกรมยูนิต',
        subtitle: 'รู้จักนักรบทั้งสี่ก่อนจัดทีม',
        body: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 700;
            final cardWidth = wide
                ? (constraints.maxWidth - AppSpacing.lg * 3) / 2
                : constraints.maxWidth - AppSpacing.lg * 2;
            return SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'เลือกยูนิตเพื่อดูค่าพลังและความสามารถแต่ละระดับดาว',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Wrap(
                    spacing: AppSpacing.lg,
                    runSpacing: AppSpacing.lg,
                    children: [
                      for (final entry in UnitCatalogEntry.entries)
                        SizedBox(
                          width: cardWidth,
                          child: _UnitCard(entry: entry),
                        ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
        navigation: const PlayerHubNavigation(selected: PlayerHubTab.units),
      );
}

class _UnitCard extends StatelessWidget {
  const _UnitCard({required this.entry});

  final UnitCatalogEntry entry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: '${entry.name} ${entry.role} ราคา ${entry.cost} ทอง ดูรายละเอียด',
      child: Material(
        color: scheme.surfaceContainerLow.withValues(alpha: 0.82),
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.allMd,
          side: BorderSide(color: scheme.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: ValueKey('unit-card-${entry.id.name}'),
          onTap: () => showUnitDetailSheet(
            context,
            unitId: entry.id,
            star: 0,
            selectableTiers: true,
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    UnitAvatar(
                      unitId: entry.id.toJson(),
                      star: 0,
                      variant: UnitAvatarVariant.bench,
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            entry.name,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          Text(
                            entry.role,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '${entry.cost} ทอง',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(entry.summary),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'แตะเพื่อดูรายละเอียด 1–3 ดาว',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: scheme.primary,
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
