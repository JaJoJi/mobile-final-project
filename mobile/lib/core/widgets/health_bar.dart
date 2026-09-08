import 'package:flutter/material.dart';

import '../theme/app_motion.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import '../theme/game_theme.dart';

/// Health-bar sizes — design spec §3.4.
enum HealthBarSize {
  /// 4 dp — over a unit.
  sm,

  /// 8 dp — player HUD.
  md,

  /// 12 dp — result screen.
  lg,
}

/// Animated HP bar — design spec §3.4.
///
/// * Fill colour: `hp.high` > 50 % · `hp.mid` 20–50 % · `hp.low` < 20 %.
/// * Width tweens over `short4` with `emphasized`.
/// * A "ghost" of damage just taken lingers in `error @40 %` for 500 ms.
/// * Below 20 % the bar pulses once per second and shows a warning icon —
///   **[MUST]** never colour alone.
/// * Numerals are always shown (unless [showText] is false) with tabular
///   figures; the row carries a Thai semantics label.
class HealthBar extends StatefulWidget {
  const HealthBar({
    super.key,
    required this.current,
    required this.max,
    this.size = HealthBarSize.md,
    this.width,
    this.showText = true,
  }) : assert(max > 0);

  final int current;
  final int max;
  final HealthBarSize size;
  final double? width;
  final bool showText;

  double get thickness => switch (size) {
        HealthBarSize.sm => 4,
        HealthBarSize.md => 8,
        HealthBarSize.lg => 12,
      };

  @override
  State<HealthBar> createState() => _HealthBarState();
}

class _HealthBarState extends State<HealthBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1000),
  );

  double _fraction = 0;
  double _ghostFraction = 0;

  static double _frac(int current, int max) => (current / max).clamp(0.0, 1.0);

  bool get _isLow => _fraction < 0.2;

  @override
  void initState() {
    super.initState();
    _fraction = _frac(widget.current, widget.max);
    _ghostFraction = _fraction;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncPulse();
  }

  @override
  void didUpdateWidget(covariant HealthBar old) {
    super.didUpdateWidget(old);
    final next = _frac(widget.current, widget.max);
    if (next != _fraction) {
      setState(() {
        if (next < _fraction) _ghostFraction = _fraction;
        _fraction = next;
      });
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) setState(() => _ghostFraction = _fraction);
      });
    }
    _syncPulse();
  }

  void _syncPulse() {
    final reduce = MediaQuery.disableAnimationsOf(context);
    if (_isLow && !reduce) {
      if (!_pulse.isAnimating) _pulse.repeat(reverse: true);
    } else if (_pulse.isAnimating) {
      _pulse
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final game = t.extension<GameTheme>()!;
    final reduce = MediaQuery.disableAnimationsOf(context);

    final fillColor = _fraction > 0.5
        ? game.hpHigh
        : _fraction >= 0.2
            ? game.hpMid
            : game.hpLow;

    final bar = LayoutBuilder(
      builder: (context, constraints) {
        final track = widget.width ?? constraints.maxWidth;
        return SizedBox(
          width: widget.width,
          height: widget.thickness,
          child: Stack(
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: t.colorScheme.outlineVariant,
                  borderRadius: AppRadius.allFull,
                ),
                child: const SizedBox.expand(),
              ),
              Container(
                width: track.isFinite ? track * _ghostFraction : 0,
                decoration: BoxDecoration(
                  color: t.colorScheme.error.withValues(alpha: 0.4),
                  borderRadius: AppRadius.allFull,
                ),
              ),
              AnimatedContainer(
                duration: reduce ? Duration.zero : AppMotion.short4,
                curve: AppMotion.emphasized,
                width: track.isFinite ? track * _fraction : 0,
                decoration: BoxDecoration(
                  color: fillColor,
                  borderRadius: AppRadius.allFull,
                ),
              ),
            ],
          ),
        );
      },
    );

    final animatedBar = (_isLow && !reduce)
        ? ScaleTransition(
            scale: Tween<double>(begin: 1.0, end: 1.04).animate(
              CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
            ),
            child: bar,
          )
        : bar;

    return Semantics(
      label: 'พลังชีวิต ${widget.current} จาก ${widget.max}',
      excludeSemantics: true,
      child: MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.3,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_isLow) ...[
              Icon(Icons.warning_amber_rounded,
                  size: widget.thickness + 8, color: game.hpLow),
              const SizedBox(width: AppSpacing.xs),
            ],
            Flexible(child: animatedBar),
            if (widget.showText) ...[
              const SizedBox(width: AppSpacing.sm),
              Text(
                '${widget.current} / ${widget.max}',
                style: AppTypography.tabular(
                  t.textTheme.bodyMedium ?? const TextStyle(),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
