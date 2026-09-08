import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../theme/app_typography.dart';
import '../theme/game_theme.dart';

/// Circular phase countdown — design spec §3.6.
///
/// **[MUST]** driven by a *deadline*, never by decrementing a counter, so
/// it can't drift or lie after the app returns from the background
/// (§5.2). Pass either [deadline] or [durationSeconds] (a deadline is then
/// computed once on mount).
///
/// States:
/// * normal — stroke `primary`, sweeps down.
/// * urgent ≤ 10 s — stroke `warning`; ≤ 5 s stroke `error` + pulse
///   1.0→1.08 per second + a light haptic at 5 / 3 / 2 / 1.
/// * waiting — at 0 it switches to an indeterminate spinner with
///   “รอเซิร์ฟเวอร์…” and never freezes on 0.
class PhaseTimerRing extends StatefulWidget {
  const PhaseTimerRing({
    super.key,
    this.deadline,
    this.durationSeconds,
    required this.onExpire,
    this.size = 56,
    this.stroke = 6,
    this.clock,
  }) : assert(deadline != null || durationSeconds != null,
            'provide deadline or durationSeconds');

  final DateTime? deadline;
  final int? durationSeconds;
  final VoidCallback onExpire;
  final double size;
  final double stroke;

  /// Wall clock — override in tests. The countdown is always derived from a
  /// deadline vs. `now`, never a decrementing counter (design spec §5.2).
  final DateTime Function()? clock;

  @override
  State<PhaseTimerRing> createState() => _PhaseTimerRingState();
}

class _PhaseTimerRingState extends State<PhaseTimerRing>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  late DateTime _deadline;
  late Duration _total;
  late final Ticker _ticker = createTicker(_onTick);
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1000),
  );

  Duration _remaining = Duration.zero;
  bool _expired = false;
  int _lastHapticSecond = 99;

  DateTime _now() => (widget.clock ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initDeadline();
    _recompute();
    _ticker.start();
  }

  void _initDeadline() {
    final now = _now();
    _deadline =
        widget.deadline ?? now.add(Duration(seconds: widget.durationSeconds!));
    _total = widget.deadline != null
        ? widget.deadline!.difference(now)
        : Duration(seconds: widget.durationSeconds!);
    if (_total <= Duration.zero) _total = const Duration(seconds: 1);
  }

  @override
  void didUpdateWidget(covariant PhaseTimerRing old) {
    super.didUpdateWidget(old);
    if (widget.deadline != old.deadline ||
        widget.durationSeconds != old.durationSeconds) {
      _expired = false;
      _lastHapticSecond = 99;
      _initDeadline();
      _recompute();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _recompute(); // never trust the gap
  }

  void _onTick(Duration _) => _recompute();

  void _recompute() {
    final left = _deadline.difference(_now());
    final clamped = left.isNegative ? Duration.zero : left;
    final secs = clamped.inSeconds;

    if (!_expired && clamped <= Duration.zero) {
      _expired = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => widget.onExpire());
    }

    if (secs <= 5 &&
        secs != _lastHapticSecond &&
        (secs == 5 || secs <= 3) &&
        secs > 0) {
      HapticFeedback.lightImpact();
    }
    _lastHapticSecond = secs;

    final wantPulse = secs <= 5 && secs > 0;
    if (wantPulse && !_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    } else if (!wantPulse && _pulse.isAnimating) {
      _pulse
        ..stop()
        ..value = 0;
    }

    if (mounted) setState(() => _remaining = clamped);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final game = t.extension<GameTheme>()!;
    final secs = _remaining.inSeconds;
    final ceilSecs = (_remaining.inMilliseconds / 1000).ceil();

    if (_expired && _remaining <= Duration.zero) {
      return Semantics(
        label: 'รอเซิร์ฟเวอร์',
        excludeSemantics: true,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: widget.size,
              height: widget.size,
              child: CircularProgressIndicator(strokeWidth: widget.stroke),
            ),
            const SizedBox(height: 4),
            Text(
              'รอเซิร์ฟเวอร์…',
              textAlign: TextAlign.center,
              style: t.textTheme.labelMedium,
            ),
          ],
        ),
      );
    }

    final progress =
        (_remaining.inMilliseconds / _total.inMilliseconds).clamp(0.0, 1.0);
    final ringColor = secs <= 5
        ? t.colorScheme.error
        : secs <= 10
            ? game.warning
            : t.colorScheme.primary;

    final ring = SizedBox(
      width: widget.size,
      height: widget.size,
      child: CustomPaint(
        painter: _RingPainter(
          progress: progress,
          color: ringColor,
          track: t.colorScheme.outlineVariant,
          stroke: widget.stroke,
        ),
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(widget.stroke),
            child: FittedBox(
              child: Text(
                '$ceilSecs',
                style: AppTypography.tabular(
                  t.textTheme.titleLarge ?? const TextStyle(),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    return Semantics(
      label: 'เหลือเวลา $ceilSecs วินาที',
      excludeSemantics: true,
      child: secs <= 5 && !MediaQuery.disableAnimationsOf(context)
          ? ScaleTransition(
              scale: Tween<double>(begin: 1.0, end: 1.08).animate(
                CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
              ),
              child: ring,
            )
          : ring,
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.progress,
    required this.color,
    required this.track,
    required this.stroke,
  });

  final double progress;
  final Color color;
  final Color track;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final center = rect.center;
    final radius = (size.shortestSide - stroke) / 2;

    final trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = track;
    canvas.drawCircle(center, radius, trackPaint);

    final arcPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = color;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      -2 * math.pi * progress,
      false,
      arcPaint,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress || old.color != color;
}
