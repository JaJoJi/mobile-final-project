import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Mirrors the HTML bootstrap in web/index.html, including its SVG crest.
class LaunchBackdrop extends StatefulWidget {
  const LaunchBackdrop({super.key});

  @override
  State<LaunchBackdrop> createState() => _LaunchBackdropState();
}

class _LaunchBackdropState extends State<LaunchBackdrop>
    with SingleTickerProviderStateMixin {
  late final _progress = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1150),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _progress.stop();
    } else if (!_progress.isAnimating) {
      _progress.repeat();
    }
  }

  @override
  void dispose() {
    _progress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final reduced = MediaQuery.disableAnimationsOf(context);
    final kickerSize = (width * .034).clamp(13.0, 15.0);
    final titleSize = (width * .1).clamp(40.0, 52.0);
    final statusSize = (width * .038).clamp(15.0, 17.0);
    return Semantics(
      label: 'กำลังโหลด Rival Arena',
      liveRegion: true,
      child: ExcludeSemantics(
        child: CustomPaint(
          painter: const _LaunchBackgroundPainter(),
          child: SafeArea(
            minimum: const EdgeInsets.all(24),
            child: Center(
              child: SingleChildScrollView(
                child: SizedBox(
                  width: math.min(width * .82, 390),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        key: const ValueKey('launch-emblem'),
                        width: 88,
                        height: 88,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: const Color(0xB35BC1EB)),
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [Color(0xEB143E5B), Color(0xF5071827)],
                          ),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x73000000),
                              blurRadius: 46,
                              offset: Offset(0, 18),
                            ),
                            BoxShadow(color: Color(0x292AADE0), blurRadius: 28),
                          ],
                        ),
                        child: const SizedBox(
                          width: 54,
                          height: 54,
                          child: CustomPaint(painter: _LaunchCrestPainter()),
                        ),
                      ),
                      const SizedBox(height: 22),
                      Text(
                        'เตรียมเข้าสู่สนาม',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'LaunchSarabun',
                          fontSize: kickerSize,
                          color: const Color(0xFF77D8FF),
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Rival Arena',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'LaunchSarabun',
                          fontSize: titleSize,
                          height: 1.3,
                          letterSpacing: 0,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFFF5F1E7),
                          shadows: const [
                            Shadow(
                              color: Color(0xB3000000),
                              blurRadius: 18,
                              offset: Offset(0, 4),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 22),
                      Text(
                        'กำลังเตรียมสนามรบ…',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'LaunchSarabun',
                          fontSize: statusSize,
                          color: const Color(0xFFB9CEE0),
                          fontWeight: FontWeight.w500,
                          letterSpacing: 0,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 6,
                        width: double.infinity,
                        child: CustomPaint(
                          key: const ValueKey('launch-progress'),
                          painter: _LaunchProgressPainter(_progress, reduced),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LaunchCrestPainter extends CustomPainter {
  const _LaunchCrestPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 64, size.height / 64);
    final pen = Paint()
      ..color = const Color(0xFFFFD45F)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(
      Path()
        ..moveTo(32, 5)
        ..lineTo(51, 12)
        ..lineTo(51, 27)
        ..cubicTo(51, 40, 43.2, 51.4, 32, 58)
        ..cubicTo(20.8, 51.4, 13, 40, 13, 27)
        ..lineTo(13, 12)
        ..close(),
      pen,
    );
    canvas.drawPath(
      Path()
        ..moveTo(21, 42)
        ..lineTo(43, 20)
        ..moveTo(21, 20)
        ..lineTo(43, 42)
        ..moveTo(18, 17)
        ..lineTo(25, 24)
        ..moveTo(46, 17)
        ..lineTo(39, 24),
      pen,
    );
    canvas.drawLine(
      const Offset(28, 31),
      const Offset(36, 31),
      pen..color = const Color(0xFF68D8FF),
    );
  }

  @override
  bool shouldRepaint(_LaunchCrestPainter oldDelegate) => false;
}

class _LaunchBackgroundPainter extends CustomPainter {
  const _LaunchBackgroundPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF102B40), Color(0xFF081A2A), Color(0xFF050F19)],
          stops: [0, .52, 1],
        ).createShader(rect),
    );
    // CSS circle uses the farthest corner as its 100% radius.
    final radius = math
        .sqrt(math.pow(size.width * .5, 2) + math.pow(size.height * .62, 2));
    final glow = Rect.fromCircle(
      center: Offset(size.width * .5, size.height * .38),
      radius: radius,
    );
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0x47287EA4), Color(0x00287EA4)],
          stops: [0, .34],
        ).createShader(glow),
    );
    for (final mirror in [false, true]) {
      canvas.save();
      if (mirror) {
        canvas.translate(size.width, 0);
        canvas.scale(-1, 1);
      }
      final panel = Rect.fromLTWH(
        -size.width * .08,
        size.height * .62,
        size.width * .42,
        size.height * .38,
      );
      canvas.drawRect(
        panel,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment(-.574, -.819),
            end: Alignment(.574, .819),
            colors: [
              Color(0x00020910),
              Color(0x00020910),
              Color(0x47020910),
              Color(0x47020910),
              Color(0x00020910),
              Color(0x00020910),
            ],
            stops: [0, .24, .25, .62, .63, 1],
          ).createShader(panel),
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_LaunchBackgroundPainter oldDelegate) => false;
}

class _LaunchProgressPainter extends CustomPainter {
  _LaunchProgressPainter(this.progress, this.reduced)
      : super(repaint: progress);
  final Animation<double> progress;
  final bool reduced;

  @override
  void paint(Canvas canvas, Size size) {
    final track = RRect.fromRectAndRadius(
      (Offset.zero & size).deflate(.5),
      const Radius.circular(999),
    );
    canvas.drawRRect(track, Paint()..color = const Color(0x9E01080E));
    canvas.save();
    canvas.clipRRect(track);
    final width = size.width * (reduced ? .72 : .42);
    final t = const Cubic(.42, 0, .58, 1).transform(progress.value);
    final left =
        reduced ? (size.width - width) / 2 : width * (-1.25 + 4.65 * t);
    final bar = Rect.fromLTWH(left, 1, width, size.height - 2);
    canvas.drawRect(
      bar,
      Paint()
        ..shader = const LinearGradient(
          colors: [
            Color(0x004FC8F2),
            Color(0xFF4FC8F2),
            Color(0xFFFFD45F),
            Color(0x00FFD45F),
          ],
          stops: [0, .36, .72, 1],
        ).createShader(bar),
    );
    canvas.restore();
    canvas.drawRRect(
      track,
      Paint()
        ..color = const Color(0x4D5CB8E0)
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(_LaunchProgressPainter oldDelegate) =>
      oldDelegate.reduced != reduced;
}
