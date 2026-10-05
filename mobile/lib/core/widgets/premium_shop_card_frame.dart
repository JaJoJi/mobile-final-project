import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';

/// A code-native premium frame for shop offers.
///
/// The frame deliberately avoids bitmap chrome: its metallic rails, corner
/// cuts, inner highlight, and deep-blue card surface all scale cleanly at any
/// card size and device pixel ratio.
class PremiumShopCardFrame extends StatelessWidget {
  const PremiumShopCardFrame({
    super.key,
    required this.accent,
    required this.child,
  });

  final Color accent;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return RepaintBoundary(
      child: ClipRRect(
        borderRadius: AppRadius.allMd,
        child: CustomPaint(
          painter: _PremiumCardBackgroundPainter(
            accent: accent,
            surface: scheme.surface,
          ),
          foregroundPainter: _PremiumCardRailPainter(accent: accent),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xxs),
            child: ClipRRect(
              borderRadius: AppRadius.allSm,
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

class _PremiumCardBackgroundPainter extends CustomPainter {
  const _PremiumCardBackgroundPainter({
    required this.accent,
    required this.surface,
  });

  final Color accent;
  final Color surface;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    final shape = RRect.fromRectAndRadius(
      bounds,
      const Radius.circular(AppRadius.md),
    );
    final base = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color.alphaBlend(accent.withValues(alpha: 0.13), surface),
          const Color(0xFF102A43),
          const Color(0xFF071725),
        ],
        stops: const [0, 0.45, 1],
      ).createShader(bounds);
    canvas.drawRRect(shape, base);

    final glow = Paint()
      ..shader = RadialGradient(
        center: const Alignment(0, -0.65),
        radius: 0.85,
        colors: [
          accent.withValues(alpha: 0.2),
          accent.withValues(alpha: 0),
        ],
      ).createShader(bounds);
    canvas.drawRRect(shape, glow);

    // The unit collection uses quiet diagonal technical lines rather than a
    // flat texture. Keep them low-contrast so the compact hero stays primary.
    final pattern = Paint()
      ..color = accent.withValues(alpha: 0.055)
      ..strokeWidth = 1;
    final step = size.width / 3;
    for (var x = -size.height; x < size.width; x += step) {
      canvas.drawLine(
        Offset(x, size.height),
        Offset(x + size.height, 0),
        pattern,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _PremiumCardBackgroundPainter oldDelegate) =>
      oldDelegate.accent != accent || oldDelegate.surface != surface;
}

class _PremiumCardRailPainter extends CustomPainter {
  const _PremiumCardRailPainter({required this.accent});

  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    final outerRect = bounds.deflate(1);
    final outer = RRect.fromRectAndRadius(
      outerRect,
      const Radius.circular(AppRadius.md - 1),
    );
    final rail = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          accent.withValues(alpha: 0.72),
          Colors.white.withValues(alpha: 0.9),
          accent.withValues(alpha: 0.34),
          accent,
        ],
        stops: const [0, 0.24, 0.58, 1],
      ).createShader(bounds);
    canvas.drawRRect(outer, rail);

    final inner = RRect.fromRectAndRadius(
      bounds.deflate(4),
      const Radius.circular(AppRadius.sm),
    );
    canvas.drawRRect(
      inner,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.white.withValues(alpha: 0.13),
    );

    final topSheen = Paint()
      ..strokeWidth = 1
      ..shader = LinearGradient(
        colors: [
          Colors.transparent,
          Colors.white.withValues(alpha: 0.72),
          Colors.transparent,
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, 1));
    canvas.drawLine(
      Offset(size.width * 0.18, 2),
      Offset(size.width * 0.82, 2),
      topSheen,
    );
  }

  @override
  bool shouldRepaint(covariant _PremiumCardRailPainter oldDelegate) =>
      oldDelegate.accent != accent;
}
