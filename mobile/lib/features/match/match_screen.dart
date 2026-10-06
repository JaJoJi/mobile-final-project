import 'dart:async';
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
import '../../core/widgets/health_bar.dart';
import '../../core/widgets/phase_timer_ring.dart';
import '../../core/widgets/state_views.dart';
import '../../core/widgets/unit_avatar.dart';
import '../../core/ws/ws_client.dart';
import '../../core/ws/ws_providers.dart';
import '../../shared/models/game_events.dart';
import '../lobby/matchmaking_state.dart';
import '../player_hub/player_hub_refresh_controller.dart';
import 'battle/battle_view.dart';
import 'board/board_slot.dart';
import 'board/board_tab.dart';
import 'match_controller.dart';
import 'match_loading_view.dart';
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
  bool _didPrecacheMatchArt = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didPrecacheMatchArt) return;
    _didPrecacheMatchArt = true;
    for (final path in [
      ...GameUiAssets.hud,
      ...GameBackgroundAssets.all,
      ...allUnitArtPaths,
    ]) {
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
                  const MatchLoadingView()
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
                if (view.damage != null &&
                    view.match != null &&
                    view.end == null &&
                    view.combatDoneSubmitted)
                  RoundResultOverlay(
                    damage: view.damage!,
                    mySide: view.match!.yourSide.name,
                    phase: view.phase,
                    readySubmitted: view.roundReadySubmitted,
                    onNextRound: controller.readyForNextRound,
                    onSurrender: controller.surrender,
                  ),
                if (view.end != null && view.match != null)
                  MatchEndOverlay(
                    event: view.end!,
                    didWin: _didWin(view),
                    mySide: view.match!.yourSide,
                    playerName: view.match!.roster.username ?? 'ผู้เล่นของคุณ',
                    opponentName: view.match!.opponent.username ?? 'คู่แข่ง',
                    finalTeam: view.match!.roster.board,
                    rounds: view.match!.round,
                    duration: DateTime.now().difference(_openedAt),
                    onPlayAgain: _playAgain,
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
    ref.read(playerHubRefreshControllerProvider).invalidateAfterMatch();
    ref.read(matchmakingStateProvider.notifier).resetAfterMatch();
    context.go('/lobby');
  }

  void _playAgain() {
    ScaffoldMessenger.maybeOf(context)?.clearSnackBars();
    ref.read(playerHubRefreshControllerProvider).invalidateAfterMatch();
    final matchmaking = ref.read(matchmakingStateProvider.notifier);
    matchmaking.resetAfterMatch();
    context.go('/lobby');
    unawaited(matchmaking.beginSearch());
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
    final shopPlace = phase.phase == GamePhase.shopPlace && view.end == null;
    return Column(
      children: [
        if (view.end == null)
          _MatchHud(
            phase: phase,
            match: match,
            deadline: deadline,
            summary: view.combatDoneSubmitted ||
                view.end != null ||
                phase.phase == GamePhase.resolved,
          ),
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
                      );
                      final shop = ShopTab(
                        shop: view.shop,
                        roster: match.roster,
                        enabled: view.canAct,
                        refreshUsed: view.refreshUsed,
                        vertical: orientation == Orientation.landscape,
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
                : phase.phase == GamePhase.battle ||
                        phase.phase == GamePhase.resolved ||
                        view.end != null
                    ? BattleView(
                        key: ValueKey('battle-${phase.round}'),
                        match: match,
                        matchId: match.matchId,
                        skipSubmitted:
                            view.combatDoneSubmitted || view.end != null,
                        onSkip: controller.skipCombat,
                      )
                    : const SizedBox.expand(
                        key: ValueKey('round-resolved'),
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
            onSell: controller.sell,
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
                // The shop column is exactly as tall as the board beside
                // it regardless of how few cards it holds, and the cards
                // stack vertically at a capped width (`ShopTab.vertical`
                // / `ShopTab.maxCardWidth`) — so the panel itself is sized
                // to that same cap (plus its own padding) instead of a
                // flex share, which used to leave the cap's own savings
                // sitting empty beside the card rather than actually
                // freeing width for the board, the thing players look at
                // during combat.
                Expanded(child: board),
                const SizedBox(width: AppSpacing.sm),
                SizedBox(
                  width: ShopTab.maxCardWidth + AppSpacing.sm * 2,
                  child: ColoredBox(color: panelColor, child: shop),
                ),
              ],
            )
          : LayoutBuilder(
              builder: (context, constraints) {
                // Five portrait cards derive their height from the available
                // width. Sizing this panel from viewport height left a large
                // empty band below the cards on tall phones.
                final shopHeight =
                    (constraints.maxWidth * 0.34).clamp(128.0, 144.0);
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
    required this.summary,
  });

  final MatchPhaseEvent phase;
  final MatchState match;
  final DateTime deadline;
  final bool summary;

  String _playerName(MatchSide side, String? stateName) {
    final current = stateName?.trim();
    if (current != null && current.isNotEmpty) return current;

    final index = side == MatchSide.p1 ? 0 : 1;
    if (index < phase.players.length) {
      final phaseName = phase.players[index].username?.trim();
      if (phaseName != null && phaseName.isNotEmpty) return phaseName;
    }
    return side == MatchSide.p1 ? 'ผู้เล่น 1' : 'ผู้เล่น 2';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final game = theme.extension<GameTheme>()!;
    final opponentSide =
        match.yourSide == MatchSide.p1 ? MatchSide.p2 : MatchSide.p1;
    final playerName = _playerName(match.yourSide, match.roster.username);
    final opponentName = _playerName(opponentSide, match.opponent.username);
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
                          label: playerName,
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
                          label: opponentName,
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
                      child: summary
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(AppSpacing.sm),
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    'รอบ ${phase.round}',
                                    key: const ValueKey('hud-summary-round'),
                                    style: theme.textTheme.titleLarge?.copyWith(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ),
                            )
                          : Column(
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
    required this.onSell,
    required this.onReady,
  });

  final int gold;
  final int readyCount;
  final bool ready;
  final bool enabled;
  final bool refreshUsed;
  final VoidCallback onRefresh;
  final void Function(RosterArea, int) onSell;
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
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.sm,
          ),
          child: SizedBox(
            height: AppSpacing.huge - AppSpacing.xs,
            child: Row(
              children: [
                SizedBox(
                  key: const ValueKey('gold-badge'),
                  height: double.infinity,
                  child: _AnimatedGoldBadge(gold: gold),
                ),
                const SizedBox(width: AppSpacing.sm),
                Tooltip(
                  message: refreshUsed
                      ? 'ใช้รีเฟรชรอบนี้แล้ว'
                      : !enabled
                          ? 'จัดทีมได้เฉพาะช่วงวางแผน'
                          : 'รีเฟรชร้านค้า',
                  child: SizedBox.square(
                    dimension: AppSpacing.huge - AppSpacing.xs,
                    child: _ActionFrame(
                      frameKey: const ValueKey('refresh-action-frame'),
                      accent: game.ally,
                      child: OutlinedButton(
                        key: const ValueKey('refresh-button'),
                        onPressed: enabled && !refreshUsed ? onRefresh : null,
                        style: OutlinedButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          foregroundColor: scheme.onSurface,
                          backgroundColor:
                              scheme.surface.withValues(alpha: 0.88),
                          side: BorderSide.none,
                          shape: const RoundedRectangleBorder(
                            borderRadius: AppRadius.allSm,
                          ),
                        ),
                        child: Icon(
                          refreshUsed
                              ? Icons.done_rounded
                              : Icons.refresh_rounded,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                SizedBox.square(
                  dimension: AppSpacing.huge - AppSpacing.xs,
                  child: _SellDropTarget(
                    enabled: enabled,
                    onSell: onSell,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: SizedBox(
                    height: double.infinity,
                    child: _ActionFrame(
                      frameKey: const ValueKey('ready-action-frame'),
                      accent: ready ? game.success : game.gold,
                      child: FilledButton(
                        key: const ValueKey('ready-button'),
                        onPressed: enabled && readyCount < 2 ? onReady : null,
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.md,
                          ),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          backgroundColor: ready ? game.success : game.gold,
                          foregroundColor: const Color(0xFF171A20),
                          disabledBackgroundColor:
                              ready ? game.success : game.gold,
                          disabledForegroundColor:
                              const Color(0xFF171A20).withValues(alpha: 0.72),
                          overlayColor: scheme.shadow.withValues(alpha: 0.12),
                          shape: const RoundedRectangleBorder(
                            borderRadius: AppRadius.allSm,
                          ),
                        ),
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
                                ?.copyWith(
                                  color: const Color(0xFF171A20),
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                        ),
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

class _SellDropTarget extends StatelessWidget {
  const _SellDropTarget({
    required this.enabled,
    required this.onSell,
  });

  final bool enabled;
  final void Function(RosterArea, int) onSell;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DragTarget<UnitDragData>(
      key: const ValueKey('sell-drop-target'),
      onWillAcceptWithDetails: (_) => enabled,
      onAcceptWithDetails: (details) {
        final source = details.data.selection;
        onSell(source.area, source.slot);
      },
      builder: (context, candidates, rejected) {
        final hovering = candidates.isNotEmpty;
        final accent =
            hovering ? scheme.error : scheme.error.withValues(alpha: 0.72);
        return Tooltip(
          message: enabled ? 'ลากฮีโร่มาวางเพื่อขาย' : 'ขายได้เฉพาะช่วงวางแผน',
          child: _ActionFrame(
            frameKey: const ValueKey('sell-action-frame'),
            accent: accent,
            child: AnimatedContainer(
              key: const ValueKey('sell-drop-surface'),
              duration: AppMotion.short2,
              decoration: BoxDecoration(
                color: hovering
                    ? scheme.errorContainer.withValues(alpha: 0.92)
                    : Color.lerp(scheme.error, Colors.black, 0.68)!,
                boxShadow: hovering
                    ? [
                        BoxShadow(
                          color: scheme.error.withValues(alpha: 0.52),
                          blurRadius: AppSpacing.md,
                          spreadRadius: AppSpacing.xxs,
                        ),
                      ]
                    : null,
              ),
              child: Semantics(
                label: hovering ? 'ปล่อยเพื่อขายฮีโร่' : 'ลากฮีโร่มาเพื่อขาย',
                child: Center(
                  child: AnimatedSwitcher(
                    duration: AppMotion.short2,
                    child: Icon(
                      hovering
                          ? Icons.delete_sweep_rounded
                          : Icons.delete_outline_rounded,
                      key: ValueKey(hovering ? 'sell-bin-open' : 'sell-bin'),
                      size: AppSpacing.xl - AppSpacing.xs,
                      color: hovering ? scheme.onErrorContainer : scheme.error,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ActionFrame extends StatelessWidget {
  const _ActionFrame({
    required this.accent,
    required this.child,
    this.frameKey,
  });

  final Color accent;
  final Widget child;
  final Key? frameKey;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      key: frameKey,
      decoration: BoxDecoration(
        borderRadius: AppRadius.allMd,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accent.withValues(alpha: 0.72),
            Colors.white.withValues(alpha: 0.9),
            accent.withValues(alpha: 0.24),
            accent.withValues(alpha: 0.82),
          ],
          stops: const [0, 0.28, 0.58, 1],
        ),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.22),
            blurRadius: AppSpacing.sm,
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxs),
        child: ClipRRect(
          borderRadius: AppRadius.allSm,
          child: child,
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
    final scheme = Theme.of(context).colorScheme;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return AnimatedBuilder(
      animation: _flash,
      builder: (context, child) {
        final pulse = math.sin(_flash.value * math.pi);
        return Transform.scale(
          scale: 1 + (pulse * 0.07),
          child: _ActionFrame(
            frameKey: const ValueKey('gold-action-frame'),
            accent: game.gold,
            child: DecoratedBox(
              key: const ValueKey('gold-surface'),
              decoration: BoxDecoration(
                color: scheme.surface.withValues(alpha: 0.88),
                boxShadow: _flash.isAnimating
                    ? [
                        BoxShadow(
                          color: game.gold.withValues(alpha: pulse * 0.75),
                          blurRadius: 14,
                          spreadRadius: AppSpacing.xxs,
                        ),
                      ]
                    : null,
              ),
              child: child,
            ),
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
            Icon(Icons.monetization_on, color: game.gold),
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
