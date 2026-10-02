import 'package:flutter/material.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/theme/game_theme.dart';
import '../../shared/models/unit.dart';
import '../../shared/models/unit_catalog.dart';

/// A compact fantasy collection card for one unit archetype.
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
    final accent = _unitAccent(entry.id);
    final gold = Theme.of(context).extension<GameTheme>()!.gold;

    return Semantics(
      button: true,
      label: '${entry.name} — ${entry.role} ราคา ${entry.cost} ทอง',
      child: Container(
        decoration: BoxDecoration(
          borderRadius: AppRadius.allLg,
          border: Border.all(
            color: const Color(0x8C6FA5C4),
            width: 1.1,
          ),
          boxShadow: [
            BoxShadow(
              color: accent.withValues(alpha: 0.06),
              blurRadius: AppSpacing.md,
            ),
            const BoxShadow(
              color: Color(0xA6000000),
              blurRadius: AppSpacing.lg,
              offset: Offset(0, AppSpacing.sm),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: AppRadius.allLg,
          child: Material(
            color: const Color(0xF20A1724),
            child: InkWell(
              onTap: onTap,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Color.lerp(const Color(0xFF10283B), accent, 0.06)!,
                          const Color(0xFF0D2030),
                          const Color(0xFF07111B),
                        ],
                      ),
                    ),
                  ),
                  CustomPaint(painter: _CardTechPainter(accent: accent)),
                  Column(
                    children: [
                      _CardMetaBar(entry: entry, accent: accent, gold: gold),
                      Expanded(
                        child: _UnitArtwork(entry: entry, accent: accent),
                      ),
                      _CardFooter(entry: entry),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CardMetaBar extends StatelessWidget {
  const _CardMetaBar({
    required this.entry,
    required this.accent,
    required this.gold,
  });

  final UnitCatalogEntry entry;
  final Color accent;
  final Color gold;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.sm,
          AppSpacing.sm,
          AppSpacing.sm,
          0,
        ),
        child: Row(
          children: [
            _MetaBadge(
              icon: _unitIcon(entry.id),
              color: accent,
            ),
            const Spacer(),
            _MetaBadge(
              icon: Icons.monetization_on_rounded,
              label: '${entry.cost}',
              color: gold,
            ),
          ],
        ),
      );
}

class _MetaBadge extends StatelessWidget {
  const _MetaBadge({
    required this.icon,
    required this.color,
    this.label,
  });

  final IconData icon;
  final Color color;
  final String? label;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: const Color(0xE607131F),
          borderRadius: AppRadius.allFull,
          border: Border.all(color: color.withValues(alpha: 0.5)),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.06),
              blurRadius: AppSpacing.xs,
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: color),
            if (label != null) ...[
              const SizedBox(width: AppSpacing.xs),
              Text(
                label!,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: color,
                      fontWeight: FontWeight.w900,
                      height: 1,
                    ),
              ),
            ],
          ],
        ),
      );
}

class _UnitArtwork extends StatelessWidget {
  const _UnitArtwork({required this.entry, required this.accent});

  final UnitCatalogEntry entry;
  final Color accent;

  @override
  Widget build(BuildContext context) => Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 180,
            height: 180,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  accent.withValues(alpha: 0.24),
                  accent.withValues(alpha: 0.08),
                  Colors.transparent,
                ],
                stops: const [0, 0.52, 1],
              ),
              boxShadow: [
                BoxShadow(
                  color: accent.withValues(alpha: 0.12),
                  blurRadius: AppSpacing.xxl,
                  spreadRadius: AppSpacing.sm,
                ),
              ],
            ),
          ),
          Positioned(
            left: AppSpacing.lg,
            right: AppSpacing.lg,
            bottom: AppSpacing.xs,
            child: Container(
              height: AppSpacing.xs,
              decoration: BoxDecoration(
                borderRadius: AppRadius.allFull,
                gradient: LinearGradient(
                  colors: [
                    Colors.transparent,
                    accent.withValues(alpha: 0.3),
                    Colors.transparent,
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.18),
                    blurRadius: AppSpacing.xs,
                  ),
                ],
              ),
            ),
          ),
          Positioned.fill(
            left: AppSpacing.xs,
            right: AppSpacing.xs,
            bottom: AppSpacing.xs,
            child: Transform.scale(
              scale: 1.2,
              alignment: Alignment.bottomCenter,
              child: Image.asset(
                'assets/images/units/${entry.id.name}_1.png',
                fit: BoxFit.contain,
                alignment: Alignment.bottomCenter,
                filterQuality: FilterQuality.high,
              ),
            ),
          ),
        ],
      );
}

class _CardFooter extends StatelessWidget {
  const _CardFooter({required this.entry});

  final UnitCatalogEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      decoration: const BoxDecoration(
        border: Border(
          top: BorderSide(color: Color(0x526FA5C4)),
        ),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xF20A1A29), Color(0xFF07131F)],
        ),
      ),
      child: Column(
        children: [
          Text(
            entry.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              color: const Color(0xFFFFF7DD),
              fontWeight: FontWeight.w900,
              height: 1.1,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            entry.role,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: const Color(0xFFB8CEF0),
            ),
          ),
        ],
      ),
    );
  }
}

class _CardTechPainter extends CustomPainter {
  const _CardTechPainter({required this.accent});

  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = const Color(0x126FA5C4)
      ..strokeWidth = 1;
    final step = size.width / 4;
    for (var x = -size.height; x < size.width; x += step) {
      canvas.drawLine(
        Offset(x, size.height),
        Offset(x + size.height, 0),
        line,
      );
    }

    final corner = Paint()
      ..color = const Color(0x666FA5C4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    const length = AppSpacing.lg;
    canvas.drawLine(const Offset(0, length), Offset.zero, corner);
    canvas.drawLine(Offset.zero, const Offset(length, 0), corner);
    canvas.drawLine(
      Offset(size.width - length, size.height),
      Offset(size.width, size.height),
      corner,
    );
    canvas.drawLine(
      Offset(size.width, size.height),
      Offset(size.width, size.height - length),
      corner,
    );
  }

  @override
  bool shouldRepaint(covariant _CardTechPainter oldDelegate) =>
      oldDelegate.accent != accent;
}

Color _unitAccent(UnitId id) => switch (id) {
      UnitId.fighter => const Color(0xFFE88989),
      UnitId.healer => const Color(0xFFF0B66A),
      UnitId.ranger => const Color(0xFF82B9A5),
      UnitId.tank => const Color(0xFF88AADB),
    };

IconData _unitIcon(UnitId id) => switch (id) {
      UnitId.fighter => Icons.sports_martial_arts_rounded,
      UnitId.healer => Icons.health_and_safety_rounded,
      UnitId.ranger => Icons.gps_fixed_rounded,
      UnitId.tank => Icons.shield_rounded,
    };
