import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/game_theme.dart';
import '../../../core/widgets/game_art_frame.dart';
import '../../../core/widgets/game_asset_button.dart';
import '../../../core/widgets/health_bar.dart';
import '../../../core/widgets/unit_avatar.dart';
import '../../../shared/models/match_damage.dart';
import '../../../shared/models/match_end.dart';
import '../../../shared/models/match_state.dart';
import '../../../shared/models/unit.dart';
import '../board/stone_board_tile.dart';

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

  /// Nine board slots in row-major order so the result preserves placement.
  final List<Unit?> finalTeam;
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
    final outcome = event.isDraw
        ? 'draw'
        : didWin == true
            ? 'win'
            : 'lose';
    return _OverlaySurface(
      accent: color,
      outcomeKey: ValueKey('result-$outcome'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            key: const ValueKey('result-trophy'),
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
          _FinalBoard(slots: finalTeam),
          const SizedBox(height: AppSpacing.md),
          HealthBar(
            current: finalState.hp,
            max: 100,
            size: HealthBarSize.lg,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text('HP สุดท้าย ${finalState.hp} / 100'),
          const SizedBox(height: AppSpacing.xl),
          GameAssetButton(
            onPressed: onPlayAgain,
            frameAsset: GameUiAssets.readyButtonFrame,
            minHeight: AppSpacing.huge + AppSpacing.sm,
            accentColor: color,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.replay, color: Color(0xFF392500)),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  'เล่นอีกครั้ง',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(color: const Color(0xFF392500)),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            key: const ValueKey('back-to-lobby-button'),
            width: double.infinity,
            height: AppSpacing.huge,
            child: OutlinedButton(
              onPressed: onBackToLobby,
              style: OutlinedButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.onSurface,
                backgroundColor: Theme.of(context)
                    .colorScheme
                    .surfaceContainerHighest
                    .withValues(alpha: 0.92),
                side: BorderSide(color: game.gold.withValues(alpha: 0.72)),
                shape: const RoundedRectangleBorder(
                  borderRadius: AppRadius.allMd,
                ),
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              ),
              child: Text(
                'กลับหน้าหลัก',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
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

class _FinalBoard extends StatelessWidget {
  const _FinalBoard({required this.slots});

  final List<Unit?> slots;

  @override
  Widget build(BuildContext context) {
    final board = List<Unit?>.generate(
      9,
      (index) => index < slots.length ? slots[index] : null,
      growable: false,
    );
    final hasUnits = board.any((unit) => unit != null);

    return Semantics(
      label: hasUnits ? 'กระดานทีมสุดท้าย 9 ช่อง' : 'กระดานทีมสุดท้ายว่าง',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 264),
              child: AspectRatio(
                key: const ValueKey('result-board'),
                aspectRatio: 1,
                child: GridView.builder(
                  physics: const NeverScrollableScrollPhysics(),
                  padding: EdgeInsets.zero,
                  itemCount: 9,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    mainAxisSpacing: AppSpacing.xxs,
                    crossAxisSpacing: AppSpacing.xxs,
                  ),
                  itemBuilder: (context, index) {
                    final unit = board[index];
                    return StoneBoardTile(
                      key: ValueKey('result-board-slot-$index'),
                      slot: index,
                      unitSide: unit == null ? null : UnitSide.ally,
                      child: unit == null
                          ? null
                          : SizedBox.expand(
                              child: UnitAvatar(
                                unitId: unit.unitId.toJson(),
                                star: unit.star,
                                expand: true,
                              ),
                            ),
                    );
                  },
                ),
              ),
            ),
          ),
          if (!hasUnits) ...[
            const SizedBox(height: AppSpacing.xs),
            const Text('ไม่มีตัวหมากบนกระดาน'),
          ],
        ],
      ),
    );
  }
}

class _OverlaySurface extends StatelessWidget {
  const _OverlaySurface({
    required this.child,
    required this.accent,
    required this.outcomeKey,
  });

  final Widget child;
  final Color accent;
  final Key outcomeKey;

  @override
  Widget build(BuildContext context) => Positioned.fill(
        child: DecoratedBox(
          decoration: const BoxDecoration(
            image: DecorationImage(
              image: AssetImage(GameBackgroundAssets.arenaBlurred),
              fit: BoxFit.cover,
            ),
          ),
          child: ColoredBox(
            color: Color.alphaBlend(
              accent.withValues(alpha: 0.08),
              Theme.of(context).colorScheme.scrim.withValues(alpha: 0.64),
            ),
            child: SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) => Center(
                  child: SizedBox(
                    key: outcomeKey,
                    width: constraints.constrainWidth(520),
                    height: constraints.constrainHeight(720),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: AppRadius.allLg,
                        boxShadow: [
                          BoxShadow(
                            color: accent.withValues(alpha: 0.48),
                            blurRadius: AppSpacing.xl,
                            spreadRadius: AppSpacing.xs,
                          ),
                        ],
                      ),
                      child: GameArtFrame(
                        frameAsset: GameUiAssets.resultPanelFrame,
                        centerSlice: const Rect.fromLTWH(42, 42, 108, 156),
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.xl,
                          AppSpacing.huge,
                          AppSpacing.xl,
                          AppSpacing.xl,
                        ),
                        child: SingleChildScrollView(child: child),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}
