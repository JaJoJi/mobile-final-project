import 'package:flutter/material.dart';

/// Colour foundations — design spec §2.1.
///
/// The whole palette is generated from one seed so tonal harmony and
/// contrast come for free. **[MUST]** Read colours through their M3 role
/// (`Theme.of(context).colorScheme.x`) or through [GameTheme] — never a
/// literal hex under `features/**`.
abstract final class AppColors {
  /// Royal periwinkle — the cool light used by the midnight chess arena.
  static const Color seed = Color(0xFF6F7FE8);

  static final ColorScheme light = ColorScheme.fromSeed(seedColor: seed);

  /// "Midnight Royal" keeps the medieval unit illustrations readable:
  /// ink-blue surfaces, moonlit indigo controls and restrained ivory ink.
  static final ColorScheme dark = ColorScheme.fromSeed(
    seedColor: seed,
    brightness: Brightness.dark,
  ).copyWith(
    primary: const Color(0xFFAEBBFF),
    onPrimary: const Color(0xFF172252),
    primaryContainer: const Color(0xFF2D396F),
    onPrimaryContainer: const Color(0xFFE0E5FF),
    secondary: const Color(0xFFCABBEA),
    onSecondary: const Color(0xFF302A43),
    secondaryContainer: const Color(0xFF46405A),
    onSecondaryContainer: const Color(0xFFE9DFFB),
    surface: const Color(0xFF0E111A),
    surfaceDim: const Color(0xFF0A0D14),
    surfaceBright: const Color(0xFF343849),
    surfaceContainerLowest: const Color(0xFF090C12),
    surfaceContainerLow: const Color(0xFF141824),
    surfaceContainer: const Color(0xFF1C2130),
    surfaceContainerHigh: const Color(0xFF252B3C),
    surfaceContainerHighest: const Color(0xFF30374A),
    outline: const Color(0xFF8D93A5),
    outlineVariant: const Color(0xFF3D4458),
  );
}
