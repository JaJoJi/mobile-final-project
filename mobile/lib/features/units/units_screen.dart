import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/widgets/fantasy_page.dart';
import '../../shared/models/unit.dart';
import '../../shared/models/unit_catalog.dart';
import '../lobby/player_hub_header.dart';
import '../lobby/player_hub_navigation.dart';
import 'unit_catalog_card.dart';
import 'unit_detail_screen.dart';

/// `/units` — browse the four unit archetypes in the Player Hub visual
/// language. Tapping a card pushes [UnitDetailScreen].
class UnitsScreen extends StatelessWidget {
  const UnitsScreen({super.key});

  static const path = '/units';

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: fantasySurfaceTheme(context),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: FantasyBackdrop(
          lighter: true,
          child: SafeArea(
            bottom: false,
            child: Column(
              children: [
                const PlayerHubHeader(),
                _UnitsHeader(),
                Expanded(
                  child: MediaQuery.withClampedTextScaling(
                    maxScaleFactor: 1.3,
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 480),
                        child: GridView.builder(
                          padding: const EdgeInsets.fromLTRB(
                            AppSpacing.lg,
                            AppSpacing.xs,
                            AppSpacing.lg,
                            AppSpacing.xl,
                          ),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            mainAxisSpacing: AppSpacing.md,
                            crossAxisSpacing: AppSpacing.md,
                            childAspectRatio: 0.85,
                          ),
                          itemCount: UnitId.values.length,
                          itemBuilder: (context, index) {
                            final id = UnitId.values[index];
                            return UnitCatalogCard(
                              entry: unitCatalog[id]!,
                              onTap: () => context.push(
                                UnitDetailScreen.path
                                    .replaceFirst(':unitId', id.name),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
                const PlayerHubNavigation(selected: PlayerHubTab.units),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _UnitsHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.lg,
          AppSpacing.xs,
        ),
        child: Row(
          children: [
            const Icon(
              Icons.shield_rounded,
              size: AppSpacing.xl,
              color: Color(0xFFFFD35A),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'คลังยูนิต',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: const Color(0xFFFFF5D6),
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.3,
                        ),
                  ),
                  Text(
                    'เรียนรู้ยูนิตทั้ง ${UnitId.values.length} ประเภท',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: const Color(0xFFB8CEF0),
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}
