import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';
import '../theme/app_theme.dart';
import 'game_art_frame.dart';

/// Shared low-noise fantasy presentation for screens outside the match.
/// Text and controls stay as Flutter widgets; artwork is decorative only.
class FantasyBackdrop extends StatelessWidget {
  const FantasyBackdrop({
    super.key,
    required this.child,
    this.lighter = false,
  });

  final Widget child;
  final bool lighter;

  @override
  Widget build(BuildContext context) => Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            GameBackgroundAssets.arenaBlurred,
            key: const ValueKey('fantasy-page-background'),
            fit: BoxFit.cover,
            excludeFromSemantics: true,
            errorBuilder: (_, __, ___) => const ColoredBox(
              color: Color(0xFF081522),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: lighter
                    ? const [
                        Color(0x6605111D),
                        Color(0x8C0A1B2B),
                        Color(0xB308111B),
                      ]
                    : const [
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

/// A restrained blue-stone surface with a faint texture and no heavy frame.
class FantasyPanel extends StatelessWidget {
  const FantasyPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.xl),
    this.translucent = false,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool translucent;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          color:
              translucent ? const Color(0xAD10283B) : const Color(0xED10283B),
          borderRadius: AppRadius.allLg,
          border: Border.all(color: const Color(0x806FA5C4)),
          boxShadow: [
            BoxShadow(
              color: translucent
                  ? const Color(0x66000000)
                  : const Color(0x99000000),
              blurRadius: AppSpacing.xl,
              offset: const Offset(0, AppSpacing.sm),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: AppRadius.allLg,
          child: Stack(
            children: [
              Positioned.fill(
                child: Opacity(
                  opacity: translucent ? 0.14 : 0.22,
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

/// Dark fantasy surface colours with gold reserved for the primary action and
/// input focus. This keeps contrast stable over artwork in light and dark app
/// themes alike.
ThemeData fantasySurfaceTheme(BuildContext context) {
  final dark = buildTheme(Brightness.dark);
  const gold = Color(0xFFF2C14E);
  return dark.copyWith(
    colorScheme: dark.colorScheme.copyWith(
      primary: gold,
      onPrimary: const Color(0xFF211A08),
    ),
    inputDecorationTheme: dark.inputDecorationTheme.copyWith(
      filled: true,
      fillColor: const Color(0xB30A1724),
      focusedBorder: const OutlineInputBorder(
        borderRadius: AppRadius.allSm,
        borderSide: BorderSide(color: gold, width: 2),
      ),
    ),
  );
}

class FantasyErrorBanner extends StatelessWidget {
  const FantasyErrorBanner({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Semantics(
        liveRegion: true,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.errorContainer,
            borderRadius: AppRadius.allSm,
          ),
          child: Row(
            children: [
              Icon(
                Icons.error_outline,
                color: Theme.of(context).colorScheme.onErrorContainer,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  message,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onErrorContainer,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
}
