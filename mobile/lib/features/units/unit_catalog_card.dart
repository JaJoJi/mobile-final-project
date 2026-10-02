import 'package:flutter/material.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/theme/game_theme.dart';
import '../../core/widgets/fantasy_page.dart';
import '../../shared/models/unit_catalog.dart';

/// A tappable card that represents one unit in the catalog list.
class UnitCatalogCard extends StatelessWidget {
  const UnitCatalogCard({
    super.key,
    required this.entry,
    required this.onTap,
  });

  final UnitCatalogEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final game = theme.extension<GameTheme>()!;

    return Semantics(
      button: true,
      label: '${entry.name} — ${entry.role}',
      child: FantasyPanel(
        translucent: true,
        padding: EdgeInsets.zero,
        child: ClipRRect(
          borderRadius: AppRadius.allLg,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // ── Content ─────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Stack(
                  children: [
                    // Glowing circular backdrop for the unit
                    Positioned.fill(
                      bottom: 40,
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [
                              theme.colorScheme.primary.withValues(alpha: 0.25),
                              Colors.transparent,
                            ],
                            radius: 0.7,
                          ),
                        ),
                      ),
                    ),

                    // Main layout: Image + Text
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(
                              top: AppSpacing.md,
                              bottom: AppSpacing.sm,
                            ),
                            child: Image.asset(
                              'assets/images/units/${entry.id.name}_1.png',
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),
                        Text(
                          entry.name,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          entry.role,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),

                    // Top Left: Star Badge
                    Positioned(
                      top: 0,
                      left: 0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0A1724),
                          border: Border.all(color: game.star1),
                          borderRadius: AppRadius.allFull,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.5),
                              blurRadius: 3,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Icon(Icons.star, size: 12, color: game.star1),
                      ),
                    ),

                    // Top Right: Cost Badge
                    Positioned(
                      top: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0A1724),
                          border: Border.all(
                            color: game.gold.withValues(alpha: 0.8),
                          ),
                          borderRadius: AppRadius.allFull,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.5),
                              blurRadius: 3,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.monetization_on,
                              size: 12,
                              color: game.gold,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              '${entry.cost}',
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: game.gold,
                                fontWeight: FontWeight.w800,
                                height: 1.0,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // ── InkWell Overlay ──────────────────────────────────────
              Positioned.fill(
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: onTap,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
