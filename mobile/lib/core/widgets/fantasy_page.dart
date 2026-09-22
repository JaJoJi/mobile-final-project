import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';
import '../theme/app_theme.dart';
import 'game_art_frame.dart';

/// Decorative arena treatment for player-facing hub screens.
class FantasyBackdrop extends StatelessWidget {
  const FantasyBackdrop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            GameBackgroundAssets.arenaBlurred,
            fit: BoxFit.cover,
            excludeFromSemantics: true,
            errorBuilder: (_, __, ___) => const ColoredBox(
              color: Color(0xFF081522),
            ),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xB305111D),
                  Color(0xD90A1B2B),
                  Color(0xF208111B),
                ],
              ),
            ),
          ),
          child,
        ],
      );
}

/// Blue-stone surface used over the arena background.
class FantasyPanel extends StatelessWidget {
  const FantasyPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xED10283B),
          borderRadius: AppRadius.allLg,
          border: Border.all(color: const Color(0x806FA5C4)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x99000000),
              blurRadius: AppSpacing.xl,
              offset: Offset(0, AppSpacing.sm),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: AppRadius.allLg,
          child: Stack(
            children: [
              Positioned.fill(
                child: Opacity(
                  opacity: 0.22,
                  child: Image.asset(
                    GameUiAssets.panelTextureBlue,
                    fit: BoxFit.cover,
                    excludeFromSemantics: true,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ),
              ),
              Padding(padding: padding, child: child),
            ],
          ),
        ),
      );
}

ThemeData fantasySurfaceTheme(BuildContext context) {
  final dark = buildTheme(Brightness.dark);
  const gold = Color(0xFFF2C14E);
  return dark.copyWith(
    colorScheme: dark.colorScheme.copyWith(
      primary: gold,
      onPrimary: const Color(0xFF211A08),
    ),
  );
}
