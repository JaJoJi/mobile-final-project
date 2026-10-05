import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Quiet arena backdrop: the encounter popup remains the visual focus.
class MatchLoadingView extends StatelessWidget {
  const MatchLoadingView({super.key});

  static const _blue = Color(0xFF72D8F4);
  static const _red = Color(0xFFF48789);
  static const _gold = Color(0xFFF4CC70);

  @override
  Widget build(BuildContext context) => Semantics(
        label: 'กำลังเตรียมสนามรบ รอข้อมูลเกม',
        child: ExcludeSemantics(
          child: DecoratedBox(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xDD0B2234),
                  Color(0x9910202B),
                  Color(0xEE091C2B),
                ],
              ),
            ),
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xBB0C2335),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: _blue.withValues(alpha: .28)),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.shield_outlined, color: _blue, size: 24),
                          SizedBox(width: 14),
                          Expanded(child: _SideLine(color: _blue)),
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: 18),
                            child: Icon(
                              Icons.bolt_rounded,
                              color: _gold,
                              size: 26,
                            ),
                          ),
                          Expanded(child: _SideLine(color: _red)),
                          SizedBox(width: 14),
                          Icon(
                            Icons.local_fire_department_outlined,
                            color: _red,
                            size: 24,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Expanded(
                      child: SizedBox.expand(
                        child: CustomPaint(painter: _ArenaLoadingPainter()),
                      ),
                    ),
                    const SizedBox(height: 16),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 320),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'กำลังเตรียมสนามรบ',
                            textAlign: TextAlign.center,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                  color: const Color(0xFFFFE5A5),
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'รอข้อมูลเกม…',
                            style: TextStyle(
                              color: Color(0xFFAFC7D4),
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 12),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: MediaQuery.disableAnimationsOf(context)
                                  ? 1
                                  : null,
                              minHeight: 2,
                              color: _blue.withValues(alpha: .7),
                              backgroundColor: _blue.withValues(alpha: .12),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
}

class _SideLine extends StatelessWidget {
  const _SideLine({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        height: 2,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              color.withValues(alpha: .15),
              color.withValues(alpha: .65),
            ],
          ),
        ),
      );
}

class _ArenaLoadingPainter extends CustomPainter {
  const _ArenaLoadingPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect.deflate(1), const Radius.circular(24)),
      Paint()
        ..color = MatchLoadingView._blue.withValues(alpha: .16)
        ..style = PaintingStyle.stroke,
    );
    final cell = math.min(size.width / 4.2, size.height / 3.8);
    final center = rect.center;
    for (var row = 0; row < 3; row++) {
      for (var col = 0; col < 3; col++) {
        final point =
            center + Offset((col - 1) * cell * 1.15, (row - 1) * cell * 1.05);
        final color =
            Color.lerp(MatchLoadingView._red, MatchLoadingView._blue, row / 2)!;
        final tile = Rect.fromCenter(
          center: point,
          width: cell * .9,
          height: cell * .68,
        );
        canvas.drawOval(
          tile.inflate(cell * .2),
          Paint()
            ..shader = RadialGradient(
              colors: [
                color.withValues(alpha: .09),
                color.withValues(alpha: 0),
              ],
            ).createShader(tile.inflate(cell * .2)),
        );
        final path = Path();
        for (var i = 0; i < 8; i++) {
          final angle = math.pi / 8 + i * math.pi / 4;
          final x = point.dx + math.cos(angle) * tile.width / 2;
          final y = point.dy + math.sin(angle) * tile.height / 2;
          if (i == 0) {
            path.moveTo(x, y);
          } else {
            path.lineTo(x, y);
          }
        }
        path.close();
        canvas.drawPath(path, Paint()..color = color.withValues(alpha: .035));
        canvas.drawPath(
          path,
          Paint()
            ..color = color.withValues(alpha: .3)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2,
        );
        canvas.drawCircle(
          point,
          2,
          Paint()..color = color.withValues(alpha: .4),
        );
      }
    }
  }

  @override
  bool shouldRepaint(_ArenaLoadingPainter oldDelegate) => false;
}
