import 'package:flutter/material.dart';

import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/game_theme.dart';
import '../../../core/widgets/unit_avatar.dart';

/// Visual layer for one board cell.
///
/// Interaction, semantics and sizing deliberately stay with the caller. This
/// widget only paints inside the constraints it receives, so loading a unit or
/// changing a highlight can never reflow the 3x3 grid.
class StoneBoardTile extends StatelessWidget {
  const StoneBoardTile({
    super.key,
    required this.slot,
    this.child,
    this.unitSide,
    this.selected = false,
    this.validDrop = false,
    this.broken = false,
    this.effect,
    this.fuseEffect = false,
  });

  static const stoneAssetPaths = <String>[
    'assets/images/board/board_tile_stone_01.png',
    'assets/images/board/board_tile_stone_02.png',
    'assets/images/board/board_tile_stone_03.png',
  ];
  static const brokenAssetPath = 'assets/images/board/board_tile_broken.png';
  static const allyBaseAssetPath = 'assets/images/board/unit_base_ally.png';
  static const enemyBaseAssetPath = 'assets/images/board/unit_base_enemy.png';

  static const allAssetPaths = <String>[
    ...stoneAssetPaths,
    brokenAssetPath,
    allyBaseAssetPath,
    enemyBaseAssetPath,
  ];

  final int slot;
  final Widget? child;
  final UnitSide? unitSide;
  final bool selected;
  final bool validDrop;
  final bool broken;
  final Animation<double>? effect;
  final bool fuseEffect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final game = theme.extension<GameTheme>()!;
    final glowColor = validDrop
        ? game.boardCellValidDrop
        : selected
            ? theme.colorScheme.primary
            : null;
    final tilePath = broken
        ? brokenAssetPath
        : stoneAssetPaths[slot % stoneAssetPaths.length];

    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: effect ?? const AlwaysStoppedAnimation<double>(0),
        builder: (context, _) {
          final effectValue = effect?.value ?? 0;
          final pulse = Curves.easeOut.transform(1 - effectValue);
          final effectColor = fuseEffect ? game.star2 : game.ally;
          return AnimatedContainer(
            duration: AppMotion.short2,
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              borderRadius: AppRadius.allMd,
              boxShadow: glowColor == null
                  ? null
                  : [
                      BoxShadow(
                        color: glowColor.withValues(alpha: 0.72),
                        blurRadius: validDrop ? 16 : 12,
                        spreadRadius: validDrop ? 2 : 1,
                      ),
                    ],
            ),
            child: Stack(
              fit: StackFit.expand,
              clipBehavior: Clip.none,
              children: [
                ExcludeSemantics(
                  child: Image.asset(
                    tilePath,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => DecoratedBox(
                      decoration: BoxDecoration(
                        color: game.boardCellEmpty,
                        borderRadius: AppRadius.allSm,
                        border:
                            Border.all(color: theme.colorScheme.outlineVariant),
                      ),
                    ),
                  ),
                ),
                if (unitSide != null)
                  Positioned.fill(
                    child: ExcludeSemantics(
                      child: FractionallySizedBox(
                        widthFactor: 0.94,
                        heightFactor: 0.94,
                        child: FractionalTranslation(
                          translation: const Offset(0, 0.05),
                          child: Image.asset(
                            unitSide == UnitSide.ally
                                ? allyBaseAssetPath
                                : enemyBaseAssetPath,
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) =>
                                const SizedBox.shrink(),
                          ),
                        ),
                      ),
                    ),
                  ),
                if (glowColor != null)
                  IgnorePointer(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.xxs),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: AppRadius.allMd,
                          border: Border.all(
                            color: glowColor.withValues(alpha: 0.95),
                            width: validDrop ? 3 : 2,
                          ),
                          gradient: RadialGradient(
                            colors: [
                              glowColor.withValues(alpha: 0.20),
                              glowColor.withValues(alpha: 0),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                if (child != null)
                  Positioned.fill(
                    child: FractionalTranslation(
                      // Unit PNGs carry transparent headroom and a low visual
                      // foot anchor. Lift the art so its feet meet the centre
                      // of the magic base instead of its front rim.
                      translation: const Offset(0, -0.31),
                      child: FractionallySizedBox(
                        widthFactor: 0.90,
                        heightFactor: 0.90,
                        child: child!,
                      ),
                    ),
                  ),
                if (effectValue > 0)
                  IgnorePointer(
                    child: Opacity(
                      opacity: pulse.clamp(0, 1),
                      child: Transform.scale(
                        scale: 0.88 + (effectValue * 0.22),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: AppRadius.allMd,
                            border: Border.all(color: effectColor, width: 3),
                            gradient: RadialGradient(
                              colors: [
                                effectColor.withValues(alpha: 0.42),
                                effectColor.withValues(alpha: 0),
                              ],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color:
                                    effectColor.withValues(alpha: pulse * 0.8),
                                blurRadius: 22,
                                spreadRadius: 3,
                              ),
                            ],
                          ),
                          child: fuseEffect
                              ? const Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceEvenly,
                                  children: [
                                    Icon(Icons.star, color: Color(0xFFFFD34E)),
                                    Icon(Icons.star, color: Color(0xFFFFE58A)),
                                    Icon(Icons.star, color: Color(0xFFFFD34E)),
                                  ],
                                )
                              : null,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
