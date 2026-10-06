import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/game_theme.dart';
import '../../../core/widgets/fantasy_page.dart';
import '../../../core/widgets/health_bar.dart';
import '../../../core/widgets/unit_avatar.dart';
import '../../../shared/models/match_damage.dart';
import '../../../shared/models/match_end.dart';
import '../../../shared/models/match_phase.dart';
import '../../../shared/models/match_state.dart';
import '../../../shared/models/unit.dart';
import '../board/stone_board_tile.dart';
import '../match_found_transition.dart';

class RoundResultOverlay extends StatefulWidget {
  const RoundResultOverlay({
    super.key,
    required this.damage,
    required this.mySide,
    required this.phase,
    required this.readySubmitted,
    required this.onNextRound,
    required this.onSurrender,
  });

  final MatchDamageEvent damage;
  final String mySide;
  final MatchPhaseEvent? phase;
  final bool readySubmitted;
  final VoidCallback onNextRound;
  final VoidCallback onSurrender;

  @override
  State<RoundResultOverlay> createState() => _RoundResultOverlayState();
}

class _RoundResultOverlayState extends State<RoundResultOverlay> {
  Timer? _countdownTimer;
  int _countdown = 0;
  bool _minimized = false;

  @override
  void initState() {
    super.initState();
    _syncCountdown();
  }

  @override
  void didUpdateWidget(RoundResultOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.phase?.timer != widget.phase?.timer ||
        oldWidget.damage.round != widget.damage.round) {
      _syncCountdown();
    }
  }

  void _syncCountdown() {
    _countdownTimer?.cancel();
    _countdown = widget.phase?.phase == GamePhase.resolved
        ? widget.phase?.timer ?? 0
        : 0;
    if (_countdown <= 0) return;
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (_countdown <= 1) {
        timer.cancel();
        setState(() => _countdown = 0);
      } else {
        setState(() => _countdown--);
      }
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mine = widget.mySide == 'p2' ? widget.damage.p2 : widget.damage.p1;
    final opponent =
        widget.mySide == 'p2' ? widget.damage.p1 : widget.damage.p2;
    final won = widget.damage.winner?.name == widget.mySide;
    final game = Theme.of(context).extension<GameTheme>()!;
    final (icon, title, color) = mine.tie
        ? (Icons.handshake_outlined, 'เสมอรอบนี้', game.warning)
        : won
            ? (Icons.emoji_events_outlined, 'ชนะรอบนี้!', game.success)
            : (
                Icons.heart_broken_outlined,
                'แพ้รอบนี้',
                Theme.of(context).colorScheme.error,
              );
    final detail = mine.tie
        ? 'ทั้งสองฝ่ายเสีย ${mine.damageApplied} HP'
        : won
            ? 'สร้างความเสียหาย ${opponent.damageApplied} HP'
            : 'ได้รับความเสียหาย ${mine.damageApplied} HP';
    final mineIndex = widget.mySide == 'p2' ? 1 : 0;
    final players = widget.phase?.players ?? const <PhasePlayer>[];
    final mineReady = widget.readySubmitted ||
        (mineIndex < players.length && players[mineIndex].ready);
    final bothAtSummary = widget.phase?.phase == GamePhase.resolved;
    final someoneReady = bothAtSummary && players.any((player) => player.ready);
    if (_minimized) {
      return Positioned(
        left: AppSpacing.lg,
        right: AppSpacing.lg,
        bottom: AppSpacing.lg,
        child: SafeArea(
          child: FantasyPanel(
            key: const ValueKey('round-summary-minimized-panel'),
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: [
                Icon(icon, color: color),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    someoneReady
                        ? 'รอบถัดไปใน $_countdown วินาที'
                        : 'สรุปรอบ ${widget.damage.round} · $title',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                IconButton(
                  key: const ValueKey('expand-round-summary'),
                  tooltip: 'เปิดสรุปผล',
                  onPressed: () => setState(() => _minimized = false),
                  icon: Icon(Icons.open_in_full_rounded, color: game.gold),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return Positioned.fill(
      child: ColoredBox(
        color: Theme.of(context).colorScheme.scrim.withValues(alpha: 0.48),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 430),
                child: FantasyPanel(
                  key: const ValueKey('round-summary-panel'),
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'สรุปรอบ ${widget.damage.round}',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(
                                    color: game.gold,
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
                          ),
                          IconButton(
                            key: const ValueKey('minimize-round-summary'),
                            tooltip: 'ย่อเพื่อดูสนามรบ',
                            onPressed: () => setState(() => _minimized = true),
                            icon: Icon(
                              Icons.close_fullscreen_rounded,
                              color: game.gold,
                            ),
                          ),
                        ],
                      ),
                      const Divider(),
                      Icon(icon, size: 44, color: color),
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        title,
                        style:
                            Theme.of(context).textTheme.headlineSmall?.copyWith(
                                  color: color,
                                  fontWeight: FontWeight.w900,
                                ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        detail,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      Container(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: const Color(0x335F91B5)),
                        ),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                const Expanded(child: Text('พลังชีวิตของคุณ')),
                                const SizedBox(width: AppSpacing.sm),
                                Text(
                                  '${mine.hpBefore}  →  ${mine.hpAfter}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            HealthBar(
                              current: mine.hpAfter,
                              max: 100,
                              size: HealthBarSize.lg,
                            ),
                          ],
                        ),
                      ),
                      if (!bothAtSummary) ...[
                        const SizedBox(height: AppSpacing.md),
                        Text(
                          'รอคู่แข่งเข้าสู่หน้าสรุปผล…',
                          key: const ValueKey('waiting-for-opponent-summary'),
                          style:
                              Theme.of(context).textTheme.titleSmall?.copyWith(
                                    color: game.ally,
                                    fontWeight: FontWeight.w700,
                                  ),
                        ),
                      ] else if (someoneReady) ...[
                        const SizedBox(height: AppSpacing.md),
                        Text(
                          _countdown > 0
                              ? 'เริ่มรอบถัดไปใน $_countdown วินาที'
                              : 'กำลังเริ่มรอบถัดไป…',
                          key: const ValueKey('round-ready-countdown'),
                          style:
                              Theme.of(context).textTheme.titleSmall?.copyWith(
                                    color: game.gold,
                                    fontWeight: FontWeight.w800,
                                  ),
                        ),
                      ],
                      const SizedBox(height: AppSpacing.lg),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          key: const ValueKey('next-round-button'),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(48),
                            backgroundColor: game.gold,
                            foregroundColor: const Color(0xFF211A08),
                            disabledBackgroundColor: const Color(0xFF263A4A),
                            disabledForegroundColor: const Color(0xFF9AAEBD),
                            shape: const RoundedRectangleBorder(
                              borderRadius: AppRadius.allMd,
                            ),
                          ),
                          onPressed: !bothAtSummary || mineReady
                              ? null
                              : widget.onNextRound,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                !bothAtSummary || mineReady
                                    ? Icons.hourglass_top_rounded
                                    : Icons.arrow_forward_rounded,
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              Text(
                                !bothAtSummary
                                    ? 'รอคู่แข่ง'
                                    : mineReady
                                        ? 'รอคู่แข่ง'
                                        : 'รอบถัดไป',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          key: const ValueKey('surrender-button'),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(48),
                            backgroundColor: const Color(0xFF102536),
                            foregroundColor: game.enemy,
                            side: BorderSide(
                              color: game.enemy.withValues(alpha: 0.55),
                            ),
                            shape: const RoundedRectangleBorder(
                              borderRadius: AppRadius.allMd,
                            ),
                          ),
                          onPressed: _confirmSurrender,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.flag_outlined, color: game.enemy),
                              const SizedBox(width: AppSpacing.sm),
                              Text(
                                'ยอมแพ้',
                                style: TextStyle(
                                  color: game.enemy,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
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

  Future<void> _confirmSurrender() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(AppSpacing.lg),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: FantasyPanel(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(
                  Icons.flag_outlined,
                  color: Color(0xFFFFA19C),
                  size: AppSpacing.xxl,
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  'ยืนยันการยอมแพ้?',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: AppSpacing.sm),
                const Text(
                  'การแข่งขันจะจบทันทีและคู่แข่งจะเป็นผู้ชนะ',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.xl),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context, false),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFB8CEF0),
                          side: const BorderSide(color: Color(0x806FA5C4)),
                        ),
                        child: const Text('เล่นต่อ'),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFE6817C),
                          foregroundColor: const Color(0xFF251112),
                        ),
                        child: const Text('ยอมแพ้'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (confirmed == true) widget.onSurrender();
  }
}

class MatchEndOverlay extends StatelessWidget {
  const MatchEndOverlay({
    super.key,
    required this.event,
    required this.didWin,
    required this.mySide,
    required this.playerName,
    required this.opponentName,
    required this.finalTeam,
    required this.rounds,
    required this.duration,
    required this.onPlayAgain,
    required this.onBackToLobby,
  });

  final MatchEndEvent event;
  final bool? didWin;
  final MatchSide mySide;
  final String playerName;
  final String opponentName;

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
            ? (Icons.emoji_events_outlined, 'คุณชนะ', game.success)
            : (
                Icons.heart_broken_rounded,
                'คุณแพ้',
                Theme.of(context).colorScheme.error,
              );
    final finalState = mySide == MatchSide.p1 ? event.finalP1 : event.finalP2;
    final ratingChange =
        mySide == MatchSide.p1 ? event.ratingP1 : event.ratingP2;
    final outcome = event.isDraw
        ? 'draw'
        : didWin == true
            ? 'win'
            : 'lose';
    return _OverlaySurface(
      outcomeKey: ValueKey('result-$outcome'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            key: const ValueKey('match-result-divider'),
            children: [
              const Expanded(
                child: Divider(color: Color(0xCC70D7FF), thickness: 1.5),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                child: Text(
                  'ผลการแข่งขัน',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: const Color(0xFFFFE5A4),
                        fontWeight: FontWeight.w900,
                      ),
                ),
              ),
              const Expanded(
                child: Divider(color: Color(0xCCFF8E88), thickness: 1.5),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          _AnimatedResultDuel(
            key: ValueKey('result-duel-${event.matchId}'),
            playerName: playerName,
            opponentName: opponentName,
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                key: const ValueKey('result-trophy'),
                icon,
                size: AppSpacing.xxl,
                color: color,
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                label,
                key: const ValueKey('match-result-headline'),
                style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                      color: color,
                      fontWeight: FontWeight.w900,
                    ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            _reasonText(event.reason, didWin),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          if (ratingChange != null) ...[
            const SizedBox(height: AppSpacing.md),
            _RatingChangeCard(change: ratingChange, outcomeColor: color),
          ],
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: Text(
                  'ทีมสุดท้าย',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Text(
                'รอบที่ $rounds',
                key: const ValueKey('match-result-round'),
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: const Color(0xFFFFE5A4),
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ],
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
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              key: const ValueKey('play-again-button'),
              onPressed: onPlayAgain,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(AppSpacing.huge),
                backgroundColor: game.gold,
                foregroundColor: const Color(0xFF211A08),
                shape: const RoundedRectangleBorder(
                  borderRadius: AppRadius.allMd,
                ),
                textStyle: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              icon: const Icon(Icons.replay_rounded),
              label: const Text('เล่นอีกครั้ง'),
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
                foregroundColor: const Color(0xFFB8CEF0),
                backgroundColor: const Color(0xFF102536),
                side: const BorderSide(color: Color(0x806FA5C4)),
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
}

class _AnimatedResultDuel extends StatefulWidget {
  const _AnimatedResultDuel({
    super.key,
    required this.playerName,
    required this.opponentName,
  });

  final String playerName;
  final String opponentName;

  @override
  State<_AnimatedResultDuel> createState() => _AnimatedResultDuelState();
}

class _AnimatedResultDuelState extends State<_AnimatedResultDuel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2000),
    animationBehavior: AnimationBehavior.preserve,
  );

  @override
  void initState() {
    super.initState();
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
  Widget build(BuildContext context) => SizedBox(
        key: const ValueKey('match-result-duel-animation'),
        width: double.infinity,
        height: 112,
        child: LayoutBuilder(
          builder: (context, constraints) => AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              final motion = profileClashMotion(_controller.value);
              final distance = profileClashDistance(
                progress: motion.collision,
                width: constraints.maxWidth,
              );
              return SizedBox.expand(
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.topCenter,
                  children: [
                    const Positioned(
                      left: -AppSpacing.lg,
                      top: -80,
                      child: SizedBox(
                        key: ValueKey('result-ally-glow'),
                        width: 250,
                        height: 340,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: RadialGradient(
                              center: Alignment(-0.75, -0.15),
                              radius: 0.95,
                              colors: [
                                Color(0xB359B7E8),
                                Color(0x70254562),
                                Color(0x0010283B),
                              ],
                              stops: [0, 0.42, 0.82],
                            ),
                          ),
                        ),
                      ),
                    ),
                    const Positioned(
                      right: -AppSpacing.lg,
                      top: -80,
                      child: SizedBox(
                        key: ValueKey('result-enemy-glow'),
                        width: 250,
                        height: 340,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: RadialGradient(
                              center: Alignment(0.75, -0.15),
                              radius: 0.95,
                              colors: [
                                Color(0xB3FF746D),
                                Color(0x8046252F),
                                Color(0x0010283B),
                              ],
                              stops: [0, 0.42, 0.82],
                            ),
                          ),
                        ),
                      ),
                    ),
                    Transform.translate(
                      offset: Offset(-(constraints.maxWidth / 4 + 22), 0),
                      child: _ResultPlayer(
                        name: widget.playerName,
                        mine: true,
                        avatarOffset: constraints.maxWidth / 4 + 22 - distance,
                      ),
                    ),
                    Transform.translate(
                      offset: Offset(constraints.maxWidth / 4 + 22, 0),
                      child: _ResultPlayer(
                        name: widget.opponentName,
                        mine: false,
                        avatarOffset:
                            distance - (constraints.maxWidth / 4 + 22),
                      ),
                    ),
                    if (motion.flash > 0.001)
                      Positioned(
                        top: -12,
                        child: IgnorePointer(
                          child: Opacity(
                            opacity: motion.flash * .65,
                            child: const SizedBox(
                              width: 96,
                              height: 96,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: RadialGradient(
                                    colors: [
                                      Color(0xE6FFFFFF),
                                      Color(0x99FFE9A8),
                                      Color(0x00FFE9A8),
                                    ],
                                    stops: [0, 0.18, 1],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    Positioned(
                      top: AppSpacing.md,
                      child: Transform.scale(
                        scale: motion.reveal,
                        child: Opacity(
                          opacity: motion.reveal.clamp(0.0, 1.0),
                          child: const _ResultVsEmblem(),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      );
}

class _ResultVsEmblem extends StatelessWidget {
  const _ResultVsEmblem();

  @override
  Widget build(BuildContext context) {
    final game = Theme.of(context).extension<GameTheme>()!;
    return Container(
      key: const ValueKey('match-result-vs'),
      width: AppSpacing.huge,
      height: AppSpacing.huge,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFF111B2A),
        border: Border.all(color: const Color(0xFFF2C14E), width: 2),
        boxShadow: const [
          BoxShadow(
            color: Color(0xDDF2C14E),
            blurRadius: AppSpacing.xl,
          ),
          BoxShadow(
            color: Color(0x8859B7E8),
            blurRadius: AppSpacing.xxl,
            offset: Offset(-AppSpacing.sm, 0),
          ),
          BoxShadow(
            color: Color(0x88FF746D),
            blurRadius: AppSpacing.xxl,
            offset: Offset(AppSpacing.sm, 0),
          ),
        ],
      ),
      child: Text(
        'VS',
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: game.gold,
              fontWeight: FontWeight.w900,
              fontStyle: FontStyle.italic,
            ),
      ),
    );
  }
}

class _RatingChangeCard extends StatelessWidget {
  const _RatingChangeCard({
    required this.change,
    required this.outcomeColor,
  });

  final RatingChange change;
  final Color outcomeColor;

  @override
  Widget build(BuildContext context) {
    final deltaText = change.delta > 0 ? '+${change.delta}' : '${change.delta}';
    final deltaColor = change.delta == 0
        ? Theme.of(context).colorScheme.onSurfaceVariant
        : outcomeColor;
    return Semantics(
      label:
          'คะแนนแรงค์จาก ${change.before} เป็น ${change.after} เปลี่ยนแปลง $deltaText',
      child: Container(
        key: const ValueKey('match-result-rating-change'),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: const Color(0xFF0D2333).withValues(alpha: 0.88),
          borderRadius: AppRadius.allMd,
          border: Border.all(color: deltaColor.withValues(alpha: 0.68)),
          boxShadow: [
            BoxShadow(
              color: deltaColor.withValues(alpha: 0.15),
              blurRadius: AppSpacing.md,
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(Icons.emoji_events_rounded, color: deltaColor),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'คะแนนแรงค์',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: const Color(0xFFB8CEF0),
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  Text(
                    '${_formatRating(change.before)}  →  ${_formatRating(change.after)}',
                    key: const ValueKey('match-result-rating-range'),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: const Color(0xFFF4F7FF),
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                ],
              ),
            ),
            Container(
              key: const ValueKey('match-result-rating-delta'),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.xs,
              ),
              decoration: BoxDecoration(
                color: deltaColor.withValues(alpha: 0.14),
                borderRadius: AppRadius.allSm,
              ),
              child: Text(
                deltaText,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: deltaColor,
                      fontWeight: FontWeight.w900,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _formatRating(int value) => value.toString().replaceAllMapped(
        RegExp(r'\B(?=(\d{3})+(?!\d))'),
        (_) => ',',
      );
}

class _ResultPlayer extends StatelessWidget {
  const _ResultPlayer({
    required this.name,
    required this.mine,
    this.avatarOffset = 0,
  });

  final String name;
  final bool mine;
  final double avatarOffset;

  @override
  Widget build(BuildContext context) {
    final sideColor = mine ? const Color(0xFF70D7FF) : const Color(0xFFFF8E88);
    final displayName = name.trim().isEmpty ? (mine ? 'คุณ' : 'คู่แข่ง') : name;
    return Column(
      children: [
        Transform.translate(
          offset: Offset(avatarOffset, 0),
          child: Container(
            key: ValueKey(
              mine ? 'result-player-avatar' : 'result-opponent-avatar',
            ),
            width: AppSpacing.huge + AppSpacing.xl,
            height: AppSpacing.huge + AppSpacing.xl,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: mine
                    ? const [Color(0xFF214C70), Color(0xFF172454)]
                    : const [Color(0xFF49252B), Color(0xFF171622)],
              ),
              border: Border.all(color: sideColor, width: 2),
              boxShadow: [
                BoxShadow(
                  color: sideColor.withValues(alpha: 0.40),
                  blurRadius: AppSpacing.xl,
                  spreadRadius: AppSpacing.xxs,
                ),
              ],
            ),
            child: Text(
              displayName.characters.first.toUpperCase(),
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: const Color(0xFFF4F7FF),
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Tooltip(
          message: displayName,
          child: Text(
            displayName,
            key: ValueKey(mine ? 'result-player-name' : 'result-opponent-name'),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
        ),
      ],
    );
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
              constraints: BoxConstraints(
                maxWidth:
                    (MediaQuery.sizeOf(context).height * 0.28).clamp(120, 264),
              ),
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
    required this.outcomeKey,
  });

  final Widget child;
  final Key outcomeKey;

  @override
  Widget build(BuildContext context) => Positioned.fill(
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(
              color:
                  Theme.of(context).colorScheme.scrim.withValues(alpha: 0.40),
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: LayoutBuilder(
                    builder: (context, constraints) => Center(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: SizedBox(
                          width: constraints.maxWidth.clamp(0, 430),
                          child: _ResultPanelImpact(
                            child: FantasyPanel(
                              key: outcomeKey,
                              padding: const EdgeInsets.all(AppSpacing.lg),
                              child: child,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
}

/// Runs on the same post-frame clock as the profile collision, above the
/// result panel, clipped to its rounded border.
class _ResultPanelImpact extends StatefulWidget {
  const _ResultPanelImpact({required this.child});

  final Widget child;

  @override
  State<_ResultPanelImpact> createState() => _ResultPanelImpactState();
}

class _ResultPanelImpactState extends State<_ResultPanelImpact>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2000),
    animationBehavior: AnimationBehavior.preserve,
  );

  @override
  void initState() {
    super.initState();
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
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _controller,
        child: widget.child,
        builder: (context, child) {
          final motion = profileClashMotion(_controller.value);
          return Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..translateByDouble(motion.shake, -motion.flash * 2, 0, 1)
              ..scaleByDouble(
                1 + motion.flash * .012,
                1 + motion.flash * .012,
                1,
                1,
              ),
            child: Stack(
              children: [
                child!,
                Positioned.fill(
                  child: IgnorePointer(
                    child: ClipRRect(
                      borderRadius: AppRadius.allLg,
                      child: ColoredBox(
                        color:
                            Colors.white.withValues(alpha: motion.flash * .08),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      );
}
