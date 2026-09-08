import 'package:flutter/widgets.dart';

/// Spacing, radius and elevation tokens — design spec §2.3.
///
/// **[MUST]** Nothing under `features/**` may use a raw padding, radius or
/// elevation value. Use these, or a value derived from a constraint
/// (e.g. `constraints.maxWidth * 0.5`).
abstract final class AppSpacing {
  /// 2 — badge inner padding.
  static const double xxs = 2;

  /// 4 — icon ↔ label gap.
  static const double xs = 4;

  /// 8 — gap between cards / buttons.
  static const double sm = 8;

  /// 12 — card padding.
  static const double md = 12;

  /// 16 — default screen padding.
  static const double lg = 16;

  /// 24 — gap between sections.
  static const double xl = 24;

  /// 32 — around empty-state art.
  static const double xxl = 32;

  /// 48 — above a terminal CTA.
  static const double huge = 48;
}

/// Corner radii — design spec §2.3.
abstract final class AppRadius {
  /// 4 — badge, chip.
  static const double xs = 4;

  /// 8 — text field, board cell.
  static const double sm = 8;

  /// 12 — unit card, shop card, button.
  static const double md = 12;

  /// 16 — modal, bottom sheet.
  static const double lg = 16;

  /// 999 — avatar, pill, timer ring.
  static const double full = 999;

  static const BorderRadius allXs = BorderRadius.all(Radius.circular(xs));
  static const BorderRadius allSm = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius allMd = BorderRadius.all(Radius.circular(md));
  static const BorderRadius allLg = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius allFull = BorderRadius.all(Radius.circular(full));
}

/// Material elevation steps — design spec §2.3.
abstract final class AppElevation {
  /// 0 — page background.
  static const double level0 = 0;

  /// 1 — card.
  static const double level1 = 1;

  /// 3 — selected / dragging card.
  static const double level2 = 3;

  /// 6 — modal, sheet.
  static const double level3 = 6;
}
