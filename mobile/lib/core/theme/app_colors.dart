import 'package:flutter/material.dart';

/// Colour foundations — design spec §2.1.
///
/// The whole palette is generated from one seed so tonal harmony and
/// contrast come for free. **[MUST]** Read colours through their M3 role
/// (`Theme.of(context).colorScheme.x`) or through [GameTheme] — never a
/// literal hex under `features/**`.
abstract final class AppColors {
  /// Indigo — matches the seed the app already shipped with.
  static const Color seed = Color(0xFF3F51B5);

  static final ColorScheme light = ColorScheme.fromSeed(seedColor: seed);

  static final ColorScheme dark =
      ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.dark);
}
