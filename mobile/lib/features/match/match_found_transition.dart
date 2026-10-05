import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/app_spacing.dart';

/// A non-dismissible encounter popup shared by quick match and private rooms.
/// The current page remains visible behind it while both fighters clash.
class MatchFoundTransition extends StatefulWidget {
  const MatchFoundTransition({
    super.key,
    required this.leftName,
    required this.rightName,
    this.title = 'พบคู่ต่อสู้!',
    this.onCompleted,
  });

  final String leftName;
  final String rightName;
  final String title;
  final VoidCallback? onCompleted;

  @override
  State<MatchFoundTransition> createState() => _MatchFoundTransitionState();
}

class _MatchFoundTransitionState extends State<MatchFoundTransition>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2000),
    animationBehavior: AnimationBehavior.preserve,
  );

  @override
  void initState() {
    super.initState();
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        widget.onCompleted?.call();
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Positioned.fill(
        child: PopScope(
          canPop: false,
          child: Material(
            key: const ValueKey('match-found-transition'),
            color: Colors.transparent,
            child: Stack(
              fit: StackFit.expand,
              children: [
                const ModalBarrier(
                  dismissible: false,
                  color: Color(0x99030A12),
                ),
                SafeArea(
                  child: Center(
                    child: AnimatedBuilder(
                      animation: _controller,
                      builder: (context, _) {
                        final popup = Curves.easeOutCubic.transform(
                          (_controller.value / .10).clamp(0.0, 1.0),
                        );
                        final collision = _controller.value;
                        final reveal = const Cubic(.2, .8, .3, 1.15).transform(
                          ((_controller.value - .38) / .16).clamp(0.0, 1.0),
                        );
                        final flash = math.sin(
                          ((_controller.value - .25) / .10).clamp(0.0, 1.0) *
                              math.pi,
                        );
                        final impact =
                            ((_controller.value - .25) / .12).clamp(0.0, 1.0);
                        final shake = math.sin(impact * math.pi * 2) *
                            2.5 *
                            math.pow(1 - impact, 2);
                        return Transform(
                          alignment: Alignment.center,
                          transform: Matrix4.identity()
                            ..translateByDouble(shake, -flash * 2, 0, 1)
                            ..scaleByDouble(
                              .94 + popup * .06 + flash * .012,
                              .94 + popup * .06 + flash * .012,
                              1,
                              1,
                            ),
                          child: Opacity(
                            opacity: popup.clamp(0.0, 1.0),
                            child: _EncounterCard(
                              title: widget.title,
                              leftName: widget.leftName,
                              rightName: widget.rightName,
                              collision: collision,
                              reveal: reveal,
                              flash: flash,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

class _EncounterCard extends StatelessWidget {
  const _EncounterCard({
    required this.title,
    required this.leftName,
    required this.rightName,
    required this.collision,
    required this.reveal,
    required this.flash,
  });

  final String title;
  final String leftName;
  final String rightName;
  final double collision;
  final double reveal;
  final double flash;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Container(
            key: const ValueKey('match-found-popup-card'),
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: const Color(0xCCF2C14E), width: 1.5),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x8059B7E8),
                  blurRadius: 38,
                  offset: Offset(-12, 0),
                ),
                BoxShadow(
                  color: Color(0x80FF746D),
                  blurRadius: 38,
                  offset: Offset(12, 0),
                ),
                BoxShadow(
                  color: Color(0xB3000000),
                  blurRadius: 28,
                  offset: Offset(0, 14),
                ),
              ],
            ),
            child: Stack(
              children: [
                const Positioned.fill(child: _EncounterBackdrop()),
                Positioned.fill(
                  child: CustomPaint(
                    painter: _PopupClashPainter(
                      reveal: reveal,
                      flash: flash,
                      divider: ((collision - .25) / .035).clamp(0.0, 1.0),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.lg,
                    AppSpacing.lg,
                    AppSpacing.md,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: Divider(
                              color: Color(0xCC70D7FF),
                              thickness: 1.5,
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.md,
                            ),
                            child: Text(
                              title,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(
                                color: const Color(0xFFFFE7A3),
                                fontWeight: FontWeight.w900,
                                shadows: const [
                                  Shadow(
                                    color: Color(0x99F2C14E),
                                    blurRadius: 14,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const Expanded(
                            child: Divider(
                              color: Color(0xCCFF817B),
                              thickness: 1.5,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.md),
                      SizedBox(
                        height: 142,
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final width = constraints.maxWidth;
                            final resting = width / 4 + 22;
                            final double distance;
                            if (collision < .25) {
                              final t = Curves.easeInOutCubic.transform(
                                ((collision - .10) / .15).clamp(0.0, 1.0),
                              );
                              distance = (width / 2 + 45) * (1 - t) + 41 * t;
                            } else {
                              final t = const Cubic(.16, .8, .3, 1.1).transform(
                                ((collision - .25) / .16).clamp(0.0, 1.0),
                              );
                              distance = 41 + (resting - 41) * t;
                            }
                            return Stack(
                              alignment: Alignment.center,
                              clipBehavior: Clip.none,
                              children: [
                                Transform.translate(
                                  offset: Offset(-distance, 0),
                                  child: _ProfileBadge(
                                    key: const ValueKey('left-fighter-icon'),
                                    name: leftName,
                                    ally: true,
                                  ),
                                ),
                                Transform.translate(
                                  offset: Offset(distance, 0),
                                  child: _ProfileBadge(
                                    key: const ValueKey('right-fighter-icon'),
                                    name: rightName,
                                    ally: false,
                                  ),
                                ),
                                Transform.scale(
                                  scale: reveal,
                                  child: Opacity(
                                    opacity: reveal.clamp(0.0, 1.0),
                                    child: const _VsEmblem(),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                      Opacity(
                        opacity: reveal.clamp(0.0, 1.0),
                        child: Row(
                          children: [
                            Expanded(
                              child: _PlayerName(
                                name: leftName,
                                color: const Color(0xFF8EDCFF),
                              ),
                            ),
                            const SizedBox(width: 88),
                            Expanded(
                              child: _PlayerName(
                                name: rightName,
                                color: const Color(0xFFFFA19C),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Opacity(
                        opacity: reveal.clamp(0.0, 1.0),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Color(0xFFF2C14E),
                              ),
                            ),
                            SizedBox(width: AppSpacing.sm),
                            Text(
                              'กำลังเข้าสู่สนามรบ…',
                              style: TextStyle(
                                color: Color(0xFFB8CEF0),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Positioned.fill(
                  child: IgnorePointer(
                    child: ColoredBox(
                      color: Colors.white.withValues(alpha: flash * .18),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

class _EncounterBackdrop extends StatelessWidget {
  const _EncounterBackdrop();

  @override
  Widget build(BuildContext context) => const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Color(0xFA123A56),
              Color(0xFC071523),
              Color(0xFA4A242D),
            ],
            stops: [0, .5, 1],
          ),
        ),
      );
}

class _ProfileBadge extends StatelessWidget {
  const _ProfileBadge({super.key, required this.ally, required this.name});

  final bool ally;
  final String name;

  @override
  Widget build(BuildContext context) {
    final accent = ally ? const Color(0xFF70D7FF) : const Color(0xFFFF817B);
    return Transform.translate(
      offset: Offset.zero,
      child: Container(
        width: 82,
        height: 82,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: ally
                ? const [Color(0xFF2874A0), Color(0xFF111C3B)]
                : const [Color(0xFF8A3A40), Color(0xFF25141D)],
          ),
          border: Border.all(color: accent, width: 2.5),
          boxShadow: [
            BoxShadow(
              color: accent.withValues(alpha: .65),
              blurRadius: 26,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Text(
          name.trim().isEmpty
              ? '?'
              : name.trim().characters.first.toUpperCase(),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 32,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _PlayerName extends StatelessWidget {
  const _PlayerName({required this.name, required this.color});

  final String name;
  final Color color;

  @override
  Widget build(BuildContext context) => Text(
        name.trim().isEmpty ? 'ผู้เล่น' : name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w900,
          shadows: [Shadow(color: color, blurRadius: 12)],
        ),
      );
}

class _VsEmblem extends StatelessWidget {
  const _VsEmblem();

  @override
  Widget build(BuildContext context) => Container(
        key: const ValueKey('match-found-vs'),
        width: 76,
        height: 76,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xFF08111D),
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0xFFFFD35A), width: 3),
          boxShadow: const [
            BoxShadow(color: Color(0xDDF2C14E), blurRadius: 30),
            BoxShadow(color: Color(0x8859B7E8), blurRadius: 42),
            BoxShadow(color: Color(0x88FF746D), blurRadius: 42),
          ],
        ),
        child: Text(
          'VS',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: const Color(0xFFFFD35A),
                fontWeight: FontWeight.w900,
                fontStyle: FontStyle.italic,
              ),
        ),
      );
}

class _PopupClashPainter extends CustomPainter {
  const _PopupClashPainter({
    required this.reveal,
    required this.flash,
    required this.divider,
  });

  final double reveal;
  final double flash;
  final double divider;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final glow = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFFFFE9A8).withValues(alpha: .34 * reveal),
          const Color(0x00FFE9A8),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: size.width * .3));
    canvas.drawCircle(center, size.width * .3, glow);

    final bolt = Paint()
      ..color = const Color(0xFFFFE9A8)
          .withValues(alpha: divider * (.65 + flash * .35))
      ..strokeWidth = 2
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    final path = Path()
      ..moveTo(center.dx + 7, center.dy - 64)
      ..lineTo(center.dx - 9, center.dy - 18)
      ..lineTo(center.dx + 11, center.dy - 3)
      ..lineTo(center.dx - 7, center.dy + 64);
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFFF2C14E).withValues(alpha: divider * .4)
        ..strokeWidth = 5
        ..style = PaintingStyle.stroke
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );
    canvas.drawPath(path, bolt);
  }

  @override
  bool shouldRepaint(_PopupClashPainter oldDelegate) =>
      oldDelegate.reveal != reveal ||
      oldDelegate.flash != flash ||
      oldDelegate.divider != divider;
}
