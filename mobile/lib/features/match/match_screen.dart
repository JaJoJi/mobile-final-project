import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_motion.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_typography.dart';
import '../../core/theme/game_theme.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_scaffold.dart';
import '../../core/widgets/health_bar.dart';
import '../../core/widgets/phase_timer_ring.dart';
import '../../core/widgets/state_views.dart';
import '../../core/widgets/unit_avatar.dart';
import '../../core/ws/ws_client.dart';
import '../../core/ws/ws_providers.dart';
import '../../shared/models/game_events.dart';
import '../lobby/matchmaking_state.dart';
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

  @override
  Widget build(BuildContext context) {
    final provider = matchControllerProvider(widget.matchId);
    final view = ref.watch(provider);
    final controller = ref.read(provider.notifier);
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

    return Theme(
      data: matchTheme,
      child: AppScaffold(
        padded: false,
        connectionStatus: connection,
        onReconnect: () => ref.read(wsClientProvider).connect(),
        body: DecoratedBox(
          decoration: BoxDecoration(
            image: const DecorationImage(
              image: AssetImage('assets/images/backgrounds/fantasy_arena.png'),
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
                    finalTeam:
                        view.match!.roster.board.whereType<Unit>().toList(),
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
  });

  final MatchViewState view;
  final DateTime deadline;
  final MatchController controller;

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
                        selection: view.selection,
                        onSelect: controller.select,
                        onDrop: controller.place,
                        onSell: controller.sell,
                        onFuse: controller.fuse,
                      );
                      final shop = ShopTab(
                        shop: view.shop,
                        roster: match.roster,
                        enabled: view.canAct,
                        refreshUsed: view.refreshUsed,
                        onBuy: controller.buy,
                        onRefresh: controller.refresh,
                      );
                      return _PlanningHost(
                        key: const ValueKey('shop-place-scroll'),
                        orientation: orientation,
                        board: board,
                        shop: shop,
                      );
                    },
                  )
                : _BattleHost(
                    match: match,
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
            onRefresh: controller.refresh,
            onReady: controller.toggleReady,
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
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHigh.withValues(alpha: 0.94),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Row(
            children: [
              Expanded(
                child: _PlayerHp(
                  label: 'คุณ',
                  hp: match.roster.hp,
                  icon: Icons.shield_outlined,
                  color: Theme.of(context).extension<GameTheme>()!.ally,
                  valueKey: const ValueKey('player-hp-value'),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('รอบ ${phase.round}'),
                    const SizedBox(height: AppSpacing.xs),
                    PhaseTimerRing(deadline: deadline, onExpire: () {}),
                  ],
                ),
              ),
              Expanded(
                child: _PlayerHp(
                  label: 'คู่แข่ง',
                  hp: match.opponent.hp,
                  icon: Icons.sports_martial_arts_outlined,
                  color: Theme.of(context).extension<GameTheme>()!.enemy,
                  labelAtEnd: true,
                  valueKey: const ValueKey('opponent-hp-value'),
                ),
              ),
            ],
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
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
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
              Text(
                '$hp',
                key: valueKey,
                style: AppTypography.tabular(
                  Theme.of(context).textTheme.labelLarge ?? const TextStyle(),
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
          HealthBar(current: hp, max: 100, showText: false),
        ],
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
    return SafeArea(
      top: false,
      child: Material(
        color: Theme.of(context)
            .colorScheme
            .surfaceContainerHigh
            .withValues(alpha: 0.96),
        elevation: AppElevation.level3,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Row(
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: AppRadius.allMd,
                  border: Border.all(color: game.gold),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: AppSpacing.xs,
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.monetization_on_outlined, color: game.gold),
                      const SizedBox(width: AppSpacing.xs),
                      Text(
                        '$gold',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              IconButton.outlined(
                onPressed: enabled && !refreshUsed ? onRefresh : null,
                tooltip:
                    refreshUsed ? 'ใช้รีเฟรชรอบนี้แล้ว' : 'รีเฟรชร้านค้าฟรี',
                icon: Icon(refreshUsed ? Icons.done : Icons.refresh),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: AppButton(
                  onPressed: enabled && readyCount < 2 ? onReady : null,
                  size: AppButtonSize.lg,
                  variant: ready
                      ? AppButtonVariant.secondary
                      : AppButtonVariant.primary,
                  disabledReason:
                      readyCount >= 2 ? 'กำลังเริ่มการต่อสู้' : null,
                  child: Text(
                    ready
                        ? 'ยกเลิกพร้อม ($readyCount/2)'
                        : 'พร้อม ($readyCount/2)',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BattleHost extends StatelessWidget {
  const _BattleHost({
    required this.match,
    required this.skipSubmitted,
    required this.onSkip,
  });

  final MatchState match;
  final bool skipSubmitted;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final game = Theme.of(context).extension<GameTheme>()!;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        children: [
          Expanded(
            child: Builder(
              builder: (context) {
                final orientation = MediaQuery.orientationOf(context);
                final mine = _BattlePreview(
                  boardKey: const ValueKey('battle-player-board'),
                  label: 'คุณ',
                  icon: Icons.shield_outlined,
                  color: game.ally,
                  units: match.roster.board,
                  showLabel: orientation == Orientation.landscape,
                );
                final opponent = _BattlePreview(
                  boardKey: const ValueKey('battle-opponent-board'),
                  label: 'คู่แข่ง',
                  icon: Icons.sports_martial_arts_outlined,
                  color: game.enemy,
                  opponentUnits: match.opponent.boardSummary,
                  reverseRows: true,
                  showLabel: orientation == Orientation.landscape,
                );
                if (orientation == Orientation.landscape) {
                  return Row(
                    children: [
                      Expanded(child: mine),
                      const _VersusDivider(horizontal: false),
                      Expanded(child: opponent),
                    ],
                  );
                }
                return Column(
                  children: [
                    Expanded(child: opponent),
                    _PortraitVersusDivider(
                      opponentColor: game.enemy,
                      playerColor: game.ally,
                    ),
                    Expanded(child: mine),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'ระบบล็อกการจัดทีมแล้ว · ภาพเล่นซ้ำจะต่อเติมใน P0-FE-05',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: AppSpacing.xs),
          OutlinedButton.icon(
            key: const ValueKey('skip-combat-button'),
            onPressed: skipSubmitted ? null : onSkip,
            icon: Icon(
              skipSubmitted ? Icons.hourglass_top : Icons.fast_forward,
            ),
            label: Text(
              skipSubmitted ? 'รอคู่แข่ง…' : 'ข้ามการต่อสู้',
            ),
          ),
        ],
      ),
    );
  }
}

class _BattlePreview extends StatelessWidget {
  const _BattlePreview({
    required this.boardKey,
    required this.label,
    required this.icon,
    required this.color,
    this.units,
    this.opponentUnits,
    this.reverseRows = false,
    this.showLabel = true,
  });

  final Key boardKey;
  final String label;
  final IconData icon;
  final Color color;
  final List<Unit?>? units;
  final List<OpponentUnit?>? opponentUnits;
  final bool reverseRows;
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    final game = Theme.of(context).extension<GameTheme>()!;
    return Column(
      children: [
        if (showLabel) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color),
              const SizedBox(width: AppSpacing.xs),
              Text(label, style: Theme.of(context).textTheme.titleMedium),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final side = constraints.biggest.shortestSide;
              return Center(
                child: SizedBox.square(
                  key: boardKey,
                  dimension: side,
                  child: GridView.builder(
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      mainAxisSpacing: AppSpacing.xs,
                      crossAxisSpacing: AppSpacing.xs,
                    ),
                    itemCount: 9,
                    itemBuilder: (context, index) {
                      final row = index ~/ 3;
                      final column = index % 3;
                      final sourceIndex =
                          reverseRows ? (2 - row) * 3 + column : index;
                      final mine = units?[sourceIndex];
                      final enemy = opponentUnits?[sourceIndex];
                      if (mine == null && enemy == null) {
                        return DecoratedBox(
                          decoration: BoxDecoration(
                            color: game.boardCellEmpty,
                            borderRadius: AppRadius.allSm,
                            border: Border.all(
                              color:
                                  Theme.of(context).colorScheme.outlineVariant,
                            ),
                          ),
                        );
                      }
                      return FittedBox(
                        child: UnitAvatar(
                          unitId:
                              mine?.unitId.toJson() ?? enemy!.unitId.toJson(),
                          star: mine?.star ?? enemy!.star,
                          size: UnitAvatarSize.sm,
                          variant: UnitAvatarVariant.replay,
                          side: mine != null ? UnitSide.ally : UnitSide.enemy,
                        ),
                      );
                    },
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _PortraitVersusDivider extends StatelessWidget {
  const _PortraitVersusDivider({
    required this.opponentColor,
    required this.playerColor,
  });

  final Color opponentColor;
  final Color playerColor;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Row(
          children: [
            Expanded(
              child: _InlineSideLabel(
                label: 'คู่แข่ง',
                icon: Icons.sports_martial_arts_outlined,
                color: opponentColor,
              ),
            ),
            const _VersusDivider(horizontal: true),
            Expanded(
              child: _InlineSideLabel(
                label: 'คุณ',
                icon: Icons.shield_outlined,
                color: playerColor,
              ),
            ),
          ],
        ),
      );
}

class _InlineSideLabel extends StatelessWidget {
  const _InlineSideLabel({
    required this.label,
    required this.icon,
    required this.color,
  });

  final String label;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: AppSpacing.xs),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
        ],
      );
}

class _VersusDivider extends StatelessWidget {
  const _VersusDivider({required this.horizontal});

  final bool horizontal;

  @override
  Widget build(BuildContext context) {
    final game = Theme.of(context).extension<GameTheme>()!;
    final label = DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: AppRadius.allFull,
        border: Border.all(color: game.gold),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        child: Text(
          'VS',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: game.gold,
              ),
        ),
      ),
    );
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: horizontal ? 0 : AppSpacing.md,
        vertical: horizontal ? AppSpacing.sm : 0,
      ),
      child: label,
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
