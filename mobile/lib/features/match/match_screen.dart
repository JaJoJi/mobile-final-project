import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/audio/game_audio.dart';
import '../../core/theme/app_motion.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_typography.dart';
import '../../core/theme/game_theme.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_scaffold.dart';
import '../../core/widgets/game_art_frame.dart';
import '../../core/widgets/game_asset_button.dart';
import '../../core/widgets/health_bar.dart';
import '../../core/widgets/phase_timer_ring.dart';
import '../../core/widgets/state_views.dart';
import '../../core/ws/ws_client.dart';
import '../../core/ws/ws_providers.dart';
import '../../shared/models/game_events.dart';
import '../lobby/matchmaking_state.dart';
import 'battle/battle_view.dart';
import 'board/board_tab.dart';
import 'match_controller.dart';
import 'result/result_overlay.dart';
import 'shop/shop_tab.dart';

/// `/match/:id` — shop, placement board and match results.
/// Battle playback is mounted into the battle-phase body by P0-FE-05.
class MatchScreen extends ConsumerStatefulWidget {
  const MatchScreen({super.key, required this.matchId});

  final String matchId;

  @override
  ConsumerState<MatchScreen> createState() => _MatchScreenState();
}

class _MatchScreenState extends ConsumerState<MatchScreen> {
  DateTime? _deadline;
  String? _phaseKey;
  final DateTime _openedAt = DateTime.now();
  bool _didPrecacheHud = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didPrecacheHud) return;
    _didPrecacheHud = true;
    for (final path in [...GameUiAssets.hud, ...GameBackgroundAssets.all]) {
      precacheImage(AssetImage(path), context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = matchControllerProvider(widget.matchId);
    final view = ref.watch(provider);
    final controller = ref.read(provider.notifier);
    final audio = ref.read(gameAudioProvider);
    final ws = ref.watch(wsConnectionStateProvider).valueOrNull ??
        WsConnectionState.connected;
    final connection = switch (ws) {
      WsConnectionState.connected => ConnectionStatus.connected,
      WsConnectionState.connecting => ConnectionStatus.connecting,
      WsConnectionState.reconnecting => ConnectionStatus.reconnecting,
      WsConnectionState.disconnected => ConnectionStatus.disconnected,
    };
    _syncDeadline(view.phase);
    final matchTheme = _buildArenaTheme();
    final arenaBackground =
        MediaQuery.orientationOf(context) == Orientation.landscape
            ? GameBackgroundAssets.arenaLandscape
            : GameBackgroundAssets.arenaPortrait;

    return Theme(
      data: matchTheme,
      child: AppScaffold(
        padded: false,
        connectionStatus: connection,
        onReconnect: () => ref.read(wsClientProvider).connect(),
        body: DecoratedBox(
          decoration: BoxDecoration(
            image: DecorationImage(
              image: AssetImage(arenaBackground),
              fit: BoxFit.cover,
            ),
            color: matchTheme.colorScheme.surface,
            backgroundBlendMode: BlendMode.srcOver,
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  matchTheme.colorScheme.surface.withValues(alpha: 0.16),
                  matchTheme.colorScheme.surface.withValues(alpha: 0.38),
                ],
              ),
            ),
            child: Stack(
              children: [
                if (view.loading)
                  const _MatchSkeleton()
                else
                  _MatchContent(
                    view: view,
                    deadline: _deadline!,
                    controller: controller,
                    audio: audio,
                  ),
                if (view.errorMessage != null)
                  _InMatchError(
                    message: view.errorMessage!,
                    onDismiss: controller.clearError,
                  ),
                if (view.damage != null && view.match != null)
                  RoundResultOverlay(
                    damage: view.damage!,
                    mySide: view.match!.yourSide.name,
                    onDismiss: controller.clearRoundResult,
                  ),
                if (view.end != null && view.match != null)
                  MatchEndOverlay(
                    event: view.end!,
                    didWin: _didWin(view),
                    mySide: view.match!.yourSide,
                    finalTeam: view.match!.roster.board,
                    rounds: view.match!.round,
                    duration: DateTime.now().difference(_openedAt),
                    onPlayAgain: _returnToLobby,
                    onBackToLobby: _returnToLobby,
                  ),
                if (connection == ConnectionStatus.disconnected)
                  _DisconnectedOverlay(onBack: _returnToLobby),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _syncDeadline(MatchPhaseEvent? phase) {
    if (phase == null) return;
    final key = '${phase.round}:${phase.phase.name}:${phase.timer}';
    if (_phaseKey == key) return;
    _phaseKey = key;
    _deadline = DateTime.now().add(Duration(seconds: phase.timer));
  }

  bool? _didWin(MatchViewState view) {
    final winner = view.end?.winnerId;
    final phase = view.phase;
    final match = view.match;
    if (winner == null || phase == null || match == null) return null;
    final index = match.yourSide == MatchSide.p1 ? 0 : 1;
    if (index >= phase.players.length) return null;
    return winner == phase.players[index].id;
  }

  void _returnToLobby() {
    ScaffoldMessenger.maybeOf(context)?.clearSnackBars();
    ref.read(matchmakingStateProvider.notifier).resetAfterMatch();
    context.go('/lobby');
  }
}

ThemeData _buildArenaTheme() {
  final base = buildTheme(Brightness.dark);
  final scheme = base.colorScheme.copyWith(
    primary: const Color(0xFF8EDCFF),
    onPrimary: const Color(0xFF04324A),
    primaryContainer: const Color(0xFF075E88),
    onPrimaryContainer: const Color(0xFFE7F8FF),
    secondary: const Color(0xFFFFD36A),
    onSecondary: const Color(0xFF4B3600),
    surface: const Color(0xFF06324B),
    surfaceDim: const Color(0xFF04283D),
    surfaceBright: const Color(0xFF25779A),
    surfaceContainerLowest: const Color(0xFF052B41),
    surfaceContainerLow: const Color(0xFF0A405C),
    surfaceContainer: const Color(0xFF0C4A68),
    surfaceContainerHigh: const Color(0xFF105876),
    surfaceContainerHighest: const Color(0xFF176987),
    outline: const Color(0xFF8EDCFF),
    outlineVariant: const Color(0xFF4FA8C8),
  );
  return base.copyWith(
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    cardTheme: base.cardTheme.copyWith(
      color: const Color(0xE60A405C),
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.allMd,
        side: BorderSide(color: scheme.outlineVariant, width: 1.2),
      ),
    ),
    extensions: [
      GameTheme.of(Brightness.dark).copyWith(
        boardCellEmpty: const Color(0xC42B5870),
        boardCellValidDrop: const Color(0xCC3B83A7),
      ),
    ],
  );
}

class _MatchContent extends StatelessWidget {
  const _MatchContent({
    required this.view,
    required this.deadline,
    required this.controller,
    required this.audio,
  });

  final MatchViewState view;
  final DateTime deadline;
  final MatchController controller;
  final GameAudio audio;

  @override
  Widget build(BuildContext context) {
    final phase = view.phase!;
    final match = view.match!;
    final shopPlace = phase.phase == GamePhase.shopPlace;
    return Column(
      children: [
        _MatchHud(phase: phase, match: match, deadline: deadline),
        Expanded(
          child: AnimatedSwitcher(
            duration: AppMotion.long2,
            child: shopPlace
                ? OrientationBuilder(
                    key: const ValueKey('shop-place'),
                    builder: (context, orientation) {
                      final board = BoardTab(
                        match: match,
                        enabled: view.canAct,
                        ready: view.readySubmitted,
                        selection: view.selection,
                        onSelect: controller.select,
                        onDrop: controller.place,
                        onSell: controller.sell,
                      );
                      final shop = ShopTab(
                        shop: view.shop,
                        roster: match.roster,
                        enabled: view.canAct,
                        refreshUsed: view.refreshUsed,
                        onBuy: (index) {
                          audio.play(GameSfx.purchase);
                          controller.buy(index);
                        },
                        onRefresh: () {
                          audio.play(GameSfx.refresh);
                          controller.refresh();
                        },
                      );
                      return _PlanningHost(
                        key: const ValueKey('shop-place-scroll'),
                        orientation: orientation,
                        board: board,
                        shop: shop,
                      );
                    },
                  )
                : BattleView(
                    match: match,
                    matchId: match.matchId,
                    skipSubmitted: view.combatDoneSubmitted,
                    onSkip: controller.skipCombat,
                  ),
          ),
        ),
        if (shopPlace)
          _ActionBar(
            gold: match.roster.gold,
            readyCount: match.readyCount,
            ready: view.readySubmitted,
            enabled: view.canAct,
            refreshUsed: view.refreshUsed,
            onRefresh: () {
              audio.play(GameSfx.refresh);
              controller.refresh();
            },
            onReady: () {
              audio.play(GameSfx.ready);
              controller.toggleReady();
            },
          ),
      ],
    );
  }
}

class _PlanningHost extends StatelessWidget {
  const _PlanningHost({
    super.key,
    required this.orientation,
    required this.board,
    required this.shop,
  });

  final Orientation orientation;
  final Widget board;
  final Widget shop;

  @override
  Widget build(BuildContext context) {
    final panelColor = Theme.of(context)
        .colorScheme
        .surfaceContainerLow
        .withValues(alpha: 0.84);
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: orientation == Orientation.landscape
          ? Row(
              children: [
                Expanded(flex: 6, child: board),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  flex: 4,
                  child: ColoredBox(color: panelColor, child: shop),
                ),
              ],
            )
          : LayoutBuilder(
              builder: (context, constraints) {
                final shopHeight =
                    (constraints.maxHeight * 0.24).clamp(112.0, 160.0);
                return Column(
                  children: [
                    Expanded(child: board),
                    const SizedBox(height: AppSpacing.xs),
                    SizedBox(
                      height: shopHeight,
                      child: ColoredBox(color: panelColor, child: shop),
                    ),
                  ],
                );
              },
            ),
    );
  }
}

class _MatchHud extends StatelessWidget {
  const _MatchHud({
    required this.phase,
    required this.match,
    required this.deadline,
  });

  final MatchPhaseEvent phase;
  final MatchState match;
  final DateTime deadline;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final game = theme.extension<GameTheme>()!;
    return Material(
      color: Colors.transparent,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.sm,
            AppSpacing.sm,
            AppSpacing.sm,
            0,
          ),
          child: SizedBox(
            height: AppSpacing.huge + AppSpacing.xxl,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: theme.colorScheme.surface.withValues(alpha: 0.72),
                borderRadius: AppRadius.allMd,
                border: Border.all(
                  color: theme.colorScheme.outline.withValues(alpha: 0.28),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.18),
                    blurRadius: AppSpacing.md,
                    offset: const Offset(0, AppSpacing.xs),
                  ),
                ],
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _PlayerHp(
                          label: 'คุณ',
                          hp: match.roster.hp,
                          icon: Icons.shield_outlined,
                          color: game.ally,
                          valueKey: const ValueKey('player-hp-value'),
                        ),
                      ),
                      const SizedBox(
                        width: AppSpacing.huge + AppSpacing.lg,
                      ),
                      Expanded(
                        child: _PlayerHp(
                          label: 'คู่แข่ง',
                          hp: match.opponent.hp,
                          icon: Icons.sports_martial_arts_outlined,
                          color: game.enemy,
                          labelAtEnd: true,
                          valueKey: const ValueKey('opponent-hp-value'),
                        ),
                      ),
                    ],
                  ),
                  SizedBox.square(
                    key: const ValueKey('hud-timer-medallion'),
                    dimension: AppSpacing.huge + AppSpacing.lg,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: theme.colorScheme.surfaceContainerHighest
                            .withValues(alpha: 0.92),
                        border: Border.all(
                          color: game.ally.withValues(alpha: 0.64),
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'รอบ ${phase.round}',
                            maxLines: 1,
                            style: theme.textTheme.labelSmall,
                          ),
                          PhaseTimerRing(
                            deadline: deadline,
                            onExpire: () {},
                            size: AppSpacing.xxl,
                            stroke: AppSpacing.xs,
                            compact: true,
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
    );
  }
}

class _PlayerHp extends StatelessWidget {
  const _PlayerHp({
    required this.label,
    required this.hp,
    required this.icon,
    required this.color,
    required this.valueKey,
    this.labelAtEnd = false,
  });

  final String label;
  final int hp;
  final IconData icon;
  final Color color;
  final Key valueKey;
  final bool labelAtEnd;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              children: [
                if (!labelAtEnd)
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Row(
                        children: [
                          Icon(icon, size: 18, color: color),
                          const SizedBox(width: AppSpacing.xs),
                          Expanded(
                            child: Text(
                              label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                TweenAnimationBuilder<int>(
                  tween: IntTween(begin: hp, end: hp),
                  duration: MediaQuery.disableAnimationsOf(context)
                      ? Duration.zero
                      : AppMotion.short4,
                  curve: AppMotion.emphasized,
                  builder: (context, value, _) => Text(
                    '$value',
                    key: valueKey,
                    style: AppTypography.tabular(
                      Theme.of(context).textTheme.labelLarge ??
                          const TextStyle(),
                    ),
                  ),
                ),
                if (labelAtEnd)
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.right,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          Icon(icon, size: 18, color: color),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            HealthBar(
              current: hp,
              max: 100,
              showText: false,
            ),
          ],
        ),
      );
}

class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.gold,
    required this.readyCount,
    required this.ready,
    required this.enabled,
    required this.refreshUsed,
    required this.onRefresh,
    required this.onReady,
  });

  final int gold;
  final int readyCount;
  final bool ready;
  final bool enabled;
  final bool refreshUsed;
  final VoidCallback onRefresh;
  final VoidCallback onReady;

  @override
  Widget build(BuildContext context) {
    final game = Theme.of(context).extension<GameTheme>()!;
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Material(
        key: const ValueKey('action-bar-frame'),
        color: scheme.surface.withValues(alpha: 0.78),
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.allMd,
          side: BorderSide(color: scheme.outline.withValues(alpha: 0.36)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xs),
          child: SizedBox(
            height: AppSpacing.huge + AppSpacing.sm,
            child: Row(
              children: [
                _AnimatedGoldBadge(gold: gold),
                const SizedBox(width: AppSpacing.sm),
                SizedBox.square(
                  dimension: AppSpacing.huge + AppSpacing.sm,
                  child: GameAssetButton(
                    onPressed: enabled && !refreshUsed ? onRefresh : null,
                    disabledReason: refreshUsed
                        ? 'ใช้รีเฟรชรอบนี้แล้ว'
                        : !enabled
                            ? 'จัดทีมได้เฉพาะช่วงวางแผน'
                            : null,
                    stretchFrame: false,
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    child: Icon(refreshUsed ? Icons.done : Icons.refresh),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: GameAssetButton(
                    key: const ValueKey('ready-button'),
                    onPressed: enabled && readyCount < 2 ? onReady : null,
                    frameAsset: GameUiAssets.readyButtonFrame,
                    minHeight: AppSpacing.huge + AppSpacing.sm,
                    selected: ready,
                    accentColor: game.success,
                    disabledReason:
                        readyCount >= 2 ? 'กำลังเริ่มการต่อสู้' : null,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        ready
                            ? 'ยกเลิกพร้อม ($readyCount/2)'
                            : 'พร้อม ($readyCount/2)',
                        maxLines: 1,
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(color: const Color(0xFF392500)),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AnimatedGoldBadge extends StatefulWidget {
  const _AnimatedGoldBadge({required this.gold});

  final int gold;

  @override
  State<_AnimatedGoldBadge> createState() => _AnimatedGoldBadgeState();
}

class _AnimatedGoldBadgeState extends State<_AnimatedGoldBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _flash;

  @override
  void initState() {
    super.initState();
    _flash = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
  }

  @override
  void didUpdateWidget(covariant _AnimatedGoldBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.gold != widget.gold &&
        !MediaQuery.disableAnimationsOf(context)) {
      _flash.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _flash.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final game = Theme.of(context).extension<GameTheme>()!;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return AnimatedBuilder(
      animation: _flash,
      builder: (context, child) {
        final pulse = math.sin(_flash.value * math.pi);
        return Transform.scale(
          scale: 1 + (pulse * 0.07),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: AppRadius.allMd,
              border: Border.all(color: game.gold),
              boxShadow: _flash.isAnimating
                  ? [
                      BoxShadow(
                        color: game.gold.withValues(alpha: pulse * 0.75),
                        blurRadius: 14,
                        spreadRadius: 2,
                      ),
                    ]
                  : null,
            ),
            child: child,
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        child: Row(
          children: [
            Icon(Icons.monetization_on_outlined, color: game.gold),
            const SizedBox(width: AppSpacing.xs),
            TweenAnimationBuilder<int>(
              tween: IntTween(begin: widget.gold, end: widget.gold),
              duration: AppMotion.maybe(
                AppMotion.short4,
                reduceMotion: reduceMotion,
              ),
              curve: AppMotion.emphasized,
              builder: (context, value, _) => Text(
                '$value',
                key: const ValueKey('gold-value'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
          ],
        ),
      ),
    );
  }
}



class _InMatchError extends StatelessWidget {
  const _InMatchError({required this.message, required this.onDismiss});

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) => Positioned(
        left: AppSpacing.md,
        right: AppSpacing.md,
        top: AppSpacing.md,
        child: Material(
          color: Theme.of(context).colorScheme.errorContainer,
          borderRadius: AppRadius.allMd,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: Row(
              children: [
                const Icon(Icons.error_outline),
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: Text(message)),
                IconButton(
                  onPressed: onDismiss,
                  tooltip: 'ปิดข้อความ',
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
        ),
      );
}

class _DisconnectedOverlay extends StatelessWidget {
  const _DisconnectedOverlay({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => Positioned.fill(
        child: ColoredBox(
          color: Theme.of(context).colorScheme.scrim.withValues(alpha: 0.8),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.wifi_off, size: 64),
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    'การเชื่อมต่อหลุด — แมตช์นี้ถือว่าแพ้',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  AppButton(
                    onPressed: onBack,
                    child: const Text('กลับหน้าหลัก'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

class _MatchSkeleton extends StatelessWidget {
  const _MatchSkeleton();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          children: [
            const SkeletonBox(height: 88),
            const SizedBox(height: AppSpacing.lg),
            Expanded(
              child: GridView.count(
                crossAxisCount: 3,
                mainAxisSpacing: AppSpacing.sm,
                crossAxisSpacing: AppSpacing.sm,
                children: List.generate(9, (_) => const SkeletonBox()),
              ),
            ),
            const Text('กำลังเข้าสู่แมตช์…'),
          ],
        ),
      );
}
