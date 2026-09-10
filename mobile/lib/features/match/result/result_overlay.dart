import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/game_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/health_bar.dart';
import '../../../core/widgets/unit_avatar.dart';
import '../../../shared/models/match_damage.dart';
import '../../../shared/models/match_end.dart';
import '../../../shared/models/match_state.dart';
import '../../../shared/models/unit.dart';

class RoundResultOverlay extends StatefulWidget {
  const RoundResultOverlay({
    super.key,
    required this.damage,
    required this.mySide,
    required this.onDismiss,
  });

  final MatchDamageEvent damage;
  final String mySide;
  final VoidCallback onDismiss;

  @override
  State<RoundResultOverlay> createState() => _RoundResultOverlayState();
}

class _RoundResultOverlayState extends State<RoundResultOverlay> {
  Timer? _dismissTimer;

  @override
  void initState() {
    super.initState();
    _scheduleDismiss();
  }

  @override
  void didUpdateWidget(RoundResultOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.damage.round != widget.damage.round) _scheduleDismiss();
  }

  void _scheduleDismiss() {
    _dismissTimer?.cancel();
    _dismissTimer = Timer(AppMotion.roundResult, widget.onDismiss);
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mine = widget.mySide == 'p2' ? widget.damage.p2 : widget.damage.p1;
    final won = widget.damage.winner?.name == widget.mySide;
    final game = Theme.of(context).extension<GameTheme>()!;
    final (icon, title, color) = mine.tie
        ? (Icons.handshake_outlined, 'เสมอรอบนี้', game.warning)
        : won
            ? (Icons.emoji_events_outlined, 'ชนะรอบนี้!', game.success)
            : (
                Icons.heart_broken_outlined,
                'เสีย ${mine.damageApplied} HP',
                Theme.of(context).colorScheme.error,
              );
    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onDismiss,
        child: ColoredBox(
          color: Theme.of(context).colorScheme.scrim.withValues(alpha: 0.58),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, size: AppSpacing.huge, color: color),
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        title,
                        style: Theme.of(context)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(color: color),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      HealthBar(
                        current: mine.hpAfter,
                        max: 100,
                        size: HealthBarSize.lg,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text('HP ${mine.hpBefore} → ${mine.hpAfter}'),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        'แตะเพื่อดูสนามต่อ',
                        style: Theme.of(context).textTheme.bodySmall,
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

class MatchEndOverlay extends StatelessWidget {
  const MatchEndOverlay({
    super.key,
    required this.event,
    required this.didWin,
    required this.mySide,
    required this.finalTeam,
    required this.rounds,
    required this.duration,
    required this.onPlayAgain,
    required this.onBackToLobby,
  });

  final MatchEndEvent event;
  final bool? didWin;
  final MatchSide mySide;
  final List<Unit> finalTeam;
  final int rounds;
  final Duration duration;
  final VoidCallback onPlayAgain;
  final VoidCallback onBackToLobby;

  @override
  Widget build(BuildContext context) {
    final game = Theme.of(context).extension<GameTheme>()!;
    final (icon, label, color) = event.isDraw
        ? (Icons.handshake_outlined, 'เสมอ', game.warning)
        : didWin == true
            ? (Icons.emoji_events_outlined, 'ชนะ!', game.success)
            : (
                Icons.sentiment_dissatisfied_outlined,
                'แพ้',
                Theme.of(context).colorScheme.error,
              );
    final finalState = mySide == MatchSide.p1 ? event.finalP1 : event.finalP2;
    return _OverlaySurface(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: AppSpacing.huge + AppSpacing.lg,
            color: color,
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            label,
            style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                  color: color,
                ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '${_reasonText(event.reason, didWin)} · $rounds รอบ · ${_durationText(duration)}',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.xl),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'ทีมสุดท้าย',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            height: AppSpacing.huge,
            child: finalTeam.isEmpty
                ? const Center(child: Text('ไม่มีตัวหมากบนกระดาน'))
                : ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: finalTeam.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(width: AppSpacing.xs),
                    itemBuilder: (context, index) => UnitAvatar(
                      unitId: finalTeam[index].unitId.toJson(),
                      star: finalTeam[index].star,
                      size: UnitAvatarSize.sm,
                      variant: UnitAvatarVariant.bench,
                    ),
                  ),
          ),
          const SizedBox(height: AppSpacing.md),
          HealthBar(
            current: finalState.hp,
            max: 100,
            size: HealthBarSize.lg,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text('HP สุดท้าย ${finalState.hp} / 100'),
          const SizedBox(height: AppSpacing.xl),
          AppButton(
            onPressed: onPlayAgain,
            size: AppButtonSize.lg,
            icon: Icons.replay,
            child: const Text('เล่นอีกครั้ง'),
          ),
          const SizedBox(height: AppSpacing.sm),
          AppButton(
            onPressed: onBackToLobby,
            variant: AppButtonVariant.secondary,
            child: const Text('กลับหน้าหลัก'),
          ),
        ],
      ),
    );
  }

  static String _reasonText(MatchEndReason reason, bool? didWin) =>
      switch (reason) {
        MatchEndReason.hpZero => 'พลังชีวิตหมด',
        MatchEndReason.forfeit =>
          didWin == true ? 'คู่แข่งยอมแพ้' : 'คุณยอมแพ้',
        MatchEndReason.disconnect =>
          didWin == true ? 'คู่แข่งหลุดการเชื่อมต่อ' : 'การเชื่อมต่อของคุณหลุด',
        MatchEndReason.unknown => 'การแข่งขันจบแล้ว',
      };

  static String _durationText(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}

class _OverlaySurface extends StatelessWidget {
  const _OverlaySurface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Positioned.fill(
        child: ColoredBox(
          color: Theme.of(context).colorScheme.scrim.withValues(alpha: 0.78),
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  child: child,
                ),
              ),
            ),
          ),
        ),
      );
}
