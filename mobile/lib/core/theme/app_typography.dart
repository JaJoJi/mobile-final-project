import 'package:flutter/material.dart';

/// Type scale — design spec §2.2.
///
/// MVP ships **no bundled font** (same rationale as sprite art in §6 — not
/// on the one-month critical path). The platform default is used; when
/// Inter + Noto Sans Thai land, set [fontFamily] here only. Line-heights
/// already satisfy the Thai stacked-vowel minimum (≥ 1.4 on body).
///
/// **[MUST]** No `fontSize:` under `features/**` — read `textTheme.x`.
abstract final class AppTypography {
  static const String? fontFamily = null; // platform default for MVP

  static const TextTheme textTheme = TextTheme(
    // h1 — WIN · LOSE
    displaySmall: TextStyle(
      fontSize: 36,
      fontWeight: FontWeight.w700,
      height: 1.2,
    ),
    // h2 — screen titles
    headlineMedium: TextStyle(
      fontSize: 28,
      fontWeight: FontWeight.w600,
      height: 1.25,
    ),
    // h3 — modal titles, section heads
    titleLarge: TextStyle(
      fontSize: 22,
      fontWeight: FontWeight.w600,
      height: 1.3,
    ),
    // subtitle — unit name, list row title
    titleMedium: TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w600,
      height: 1.4,
    ),
    // body — default text everywhere
    bodyLarge: TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w400,
      height: 1.5,
    ),
    // body-sm — secondary description
    bodyMedium: TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w400,
      height: 1.5,
    ),
    // button — button labels
    labelLarge: TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w600,
      height: 1.2,
    ),
    // caption — timestamps, helper text
    labelMedium: TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w500,
      height: 1.4,
    ),
    // micro — badges only
    labelSmall: TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w500,
      height: 1.3,
    ),
  );

  /// Tabular-figures variant — **[MUST]** for any number that ticks
  /// (HP, gold, timer) so digits don't jitter.
  static TextStyle tabular(TextStyle base) => base.copyWith(
        fontFeatures: const [FontFeature.tabularFigures()],
      );
}
