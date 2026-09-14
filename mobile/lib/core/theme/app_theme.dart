import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_spacing.dart';
import 'app_typography.dart';
import 'game_theme.dart';

/// Assembles the light / dark [ThemeData] — design spec §2 + §16.2.
///
/// **[MUST]** Component styling is configured here once; screens never
/// pass a `style:` of their own.
ThemeData buildTheme(Brightness brightness) {
  final scheme =
      brightness == Brightness.light ? AppColors.light : AppColors.dark;

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    textTheme: AppTypography.textTheme.apply(
      bodyColor: scheme.onSurface,
      displayColor: scheme.onSurface,
    ),
    scaffoldBackgroundColor: scheme.surface,
    extensions: [GameTheme.of(brightness)],
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.allMd),
        textStyle: AppTypography.textTheme.labelLarge,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.allMd),
        textStyle: AppTypography.textTheme.labelLarge,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(48, 48),
        textStyle: AppTypography.textTheme.labelLarge,
      ),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: AppRadius.allSm),
    ),
    cardTheme: const CardThemeData(
      elevation: AppElevation.level1,
      shape: RoundedRectangleBorder(borderRadius: AppRadius.allMd),
      clipBehavior: Clip.antiAlias,
    ),
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: AppRadius.allMd),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      showDragHandle: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
    ),
    dialogTheme: const DialogThemeData(
      shape: RoundedRectangleBorder(borderRadius: AppRadius.allLg),
    ),
  );
}
