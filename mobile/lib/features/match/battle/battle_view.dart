/// `BattleView` — the in-match combat player mounted in place of the
/// old static `_BattleHost` (P0-FE-05).
///
/// Sub-step 2a: wire-up only. The widget
///   * listens to `combatEventsProvider` for the current battle batch,
///   * drives a playhead `AnimationController` whose value is pushed into
///     a [BattlePlaybackController] (a `StateNotifier`),
///   * logs the batch load so we can eyeball the wire format on a real
///     match,
///   * still renders the two static boards (no per-event animation yet).
///
/// 2b will derive per-unit HP / alpha state from `events` + playhead
/// value; 2c adds the melee lunge; 2d the ranged projectile; 2e the
/// floating damage numbers. The public surface of [BattleView] and the
/// [BattlePlaybackController] is stable across all of them.
library;

import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/game_theme.dart';
import '../../../core/widgets/game_asset_button.dart';
import '../../../core/widgets/unit_avatar.dart';
import '../../../core/ws/ws_providers.dart';
import '../../../shared/models/combat_event.dart';
import '../../../shared/models/match_state.dart';
import '../../../shared/models/unit.dart';
import '../board/stone_board_tile.dart';
import '../match_controller.dart' show unitMaxHp;
import 'battle_playback_controller.dart';
import 'battle_visual_state.dart';

/// Family by `matchId` so navigating between match screens (multi-match
/// history) does not reuse a stale batch.
final battlePlaybackProvider = StateNotifierProvider.autoDispose
    .family<BattlePlaybackController, BattleVisualState, String>(
  (ref, matchId) => BattlePlaybackController(),
);

/// `BattleView` — 2a skeleton.
class BattleView extends ConsumerStatefulWidget {
  const BattleView({
    super.key,
    required this.match,
    required this.matchId,
    required this.skipSubmitted,
    required this.onSkip,
  });

  final MatchState match;
  final String matchId;
  final bool skipSubmitted;
  final VoidCallback onSkip;

  @override
  ConsumerState<BattleView> createState() => _BattleViewState();
}

class _BattleViewState extends ConsumerState<BattleView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _playhead;
  late final BattlePlaybackController _controller;
  Timer? _staleTimer;
  bool _staleDetected = false;

  @override
  void initState() {
    super.initState();
    _playhead = AnimationController(
      vsync: this,
      duration: kCombatEventDuration,
    );
    _playhead.addStatusListener(_onPlayheadStatusChanged);
    _playhead.addListener(_pushPlayhead);
    _controller = ref.read(battlePlaybackProvider(widget.matchId).notifier);
    _startStaleTimer();
  }

  @override
  void dispose() {
    _staleTimer?.cancel();
    _playhead.removeStatusListener(_onPlayheadStatusChanged);
    _playhead.removeListener(_pushPlayhead);
    _playhead.dispose();
    super.dispose();
  }

  /// If no combat batch arrives within 10s, the WS likely missed the event.
  void _startStaleTimer() {
    _staleTimer = Timer(const Duration(seconds: 10), () {
      if (!mounted) return;
      final batch = ref.read(battlePlaybackProvider(widget.matchId)).batch;
      if (batch == null) {
        setState(() => _staleDetected = true);
      }
    });
  }

  void _onBatch(CombatEventBatch batch) {
    if (!mounted) return;
    _staleTimer?.cancel();
    _staleDetected = false;
    _acked = false;
    _controller.loadBatch(batch);
    final filtered = _controller.state.batch!.events;
    final totalMs = filtered.length * kCombatEventDuration.inMilliseconds;
    developer.log(
      'battle batch loaded: match=${batch.matchId} round=${batch.round} '
      'events=${filtered.length} (of ${batch.events.length}) '
      'cycleCount=${batch.cycleCount} playbackMs=$totalMs',
      name: 'BattleView',
    );
    _playhead
      ..duration = Duration(milliseconds: totalMs)
      ..forward(from: 0);
    setState(() {}); // refresh the playhead listener binding below
  }

  bool _acked = false;

  void _onPlayheadStatusChanged(AnimationStatus status) {
    if (_playhead.isCompleted && !_acked) {
      _acked = true;
      // Freeze 500ms (battle_end spec), then ack.
      Future<void>.delayed(const Duration(milliseconds: 500), () {
        if (mounted) widget.onSkip();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Listen for batches arriving from the server.
    ref.listen<AsyncValue<CombatEventBatch>>(
      combatEventsProvider,
      (prev, next) {
        final batch = next.valueOrNull;
        if (batch == null) return;
        if (batch.matchId != widget.matchId) return;
        if (batch.round != widget.match.round) return;
        _onBatch(batch);
      },
    );

    final view = ref.watch(battlePlaybackProvider(widget.matchId));
    final game = Theme.of(context).extension<GameTheme>()!;

    // Derive per-unit visual states from server snapshots in events.
    final unitStates = <UnitKey, UnitVisualState>{};
    if (view.batch != null) {
      unitStates.addAll(
        deriveUnitStates(
          events: view.batch!.events,
          playheadIndex: view.playheadIndex,
          playerBoard: widget.match.roster.board,
          opponentBoard: widget.match.opponent.boardSummary
              .asMap()
              .entries
              .map((entry) {
                final o = entry.value;
                if (o == null) return null;
                return Unit(
                  instanceId: 'opponent-${entry.key}-${o.unitId.name}',
                  unitId: o.unitId,
                  star: o.star,
                  hp: unitMaxHp(o.unitId),
                  maxHp: unitMaxHp(o.unitId),
                );
              })
              .toList(),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        children: [
          Expanded(
            child: _BattleStage(
              match: widget.match,
              game: game,
              unitStates: unitStates,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          _BatchSummary(view: view, staleDetected: _staleDetected),
          const SizedBox(height: AppSpacing.xs),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: GameAssetButton(
              key: const ValueKey('skip-combat-button'),
              onPressed: widget.skipSubmitted ? null : widget.onSkip,
              disabledReason:
                  widget.skipSubmitted ? 'ส่งผลการทดสอบแล้ว' : null,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    widget.skipSubmitted
                        ? Icons.hourglass_top
                        : Icons.fast_forward,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Flexible(
                    child: Text(
                      widget.skipSubmitted ? 'รอคู่แข่ง…' : 'ข้ามการต่อสู้',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _pushPlayhead() {
    _controller.seekTo(_playhead.value);
  }
}

/// Two static 3×3 boards (mine on top in portrait, opponent on top in
/// landscape — same as the pre-Step-2 `_BattleHost`). Sub-step 2b will
/// replace this with per-unit HP / alpha derived from the playhead.
class _BattleStage extends StatelessWidget {
  const _BattleStage({
    required this.match,
    required this.game,
    required this.unitStates,
  });

  final MatchState match;
  final GameTheme game;
  final Map<UnitKey, UnitVisualState> unitStates;

  @override
  Widget build(BuildContext context) {
    final orientation = MediaQuery.orientationOf(context);
    final enemySide = match.yourSide == MatchSide.p1 ? MatchSide.p2 : MatchSide.p1;
    final mine = _BoardPreview(
      boardKey: const ValueKey('battle-player-board'),
      label: 'คุณ',
      icon: Icons.shield_outlined,
      color: game.ally,
      units: match.roster.board,
      side: match.yourSide,
      unitStates: unitStates,
      showLabel: orientation == Orientation.landscape,
    );
    final opponent = _BoardPreview(
      boardKey: const ValueKey('battle-opponent-board'),
      label: 'คู่แข่ง',
      icon: Icons.sports_martial_arts_outlined,
      color: game.enemy,
      opponentUnits: match.opponent.boardSummary,
      side: enemySide,
      unitStates: unitStates,
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
        const SizedBox(
          key: ValueKey('combat-damage-lane'),
          height: AppSpacing.xxl,
        ),
        Expanded(child: opponent),
        _PortraitVersusDivider(
          opponentColor: game.enemy,
          playerColor: game.ally,
        ),
        Expanded(child: mine),
      ],
    );
  }
}

class _BoardPreview extends StatelessWidget {
  const _BoardPreview({
    required this.boardKey,
    required this.label,
    required this.icon,
    required this.color,
    required this.side,
    required this.unitStates,
    this.units,
    this.opponentUnits,
    this.reverseRows = false,
    this.showLabel = true,
  });

  final Key boardKey;
  final String label;
  final IconData icon;
  final Color color;
  final MatchSide side;
  final Map<UnitKey, UnitVisualState> unitStates;
  final List<Unit?>? units;
  final List<OpponentUnit?>? opponentUnits;
  final bool reverseRows;
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
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
              final boardSize = constraints.biggest.shortestSide;
              return Center(
                child: SizedBox.square(
                  key: boardKey,
                  dimension: boardSize,
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
                      final unitKey = UnitKey(side: side, slot: sourceIndex);
                      final uv = unitStates[unitKey];
                      return BattleTile(
                        slot: sourceIndex,
                        unitSide: uv != null
                            ? (side == MatchSide.p1
                                ? UnitSide.ally
                                : UnitSide.enemy)
                            : null,
                        unitState: uv,
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

/// Minimal tile — shows the unit avatar with HP, alive/dead state,
/// and melee lunge animation derived from the event stream (2b+2c).
class BattleTile extends StatefulWidget {
  const BattleTile({
    super.key,
    required this.slot,
    required this.unitSide,
    this.unitState,
  });

  final int slot;
  final UnitSide? unitSide;
  final UnitVisualState? unitState;

  @override
  State<BattleTile> createState() => _BattleTileState();
}

class _BattleTileState extends State<BattleTile>
    with TickerProviderStateMixin {
  late final AnimationController _lungeCtrl;
  late final Animation<double> _lungeAnim;
  late final AnimationController _projCtrl;
  late final Animation<double> _projAnim;
  late final AnimationController _floatCtrl;
  late final Animation<double> _floatAnim;
  bool _wasLunging = false;
  bool _wasShooting = false;
  bool _wasFloating = false;
  int? _lastFloatingDamage;

  @override
  void initState() {
    super.initState();
    _lungeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100), // short2
    );
    _lungeAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _lungeCtrl, curve: AppMotion.standard),
    );
    _projCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300), // medium2
    );
    _projAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _projCtrl, curve: AppMotion.standard),
    );
    _floatCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300), // medium2
    );
    _floatAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _floatCtrl, curve: AppMotion.standard),
    );
  }

  @override
  void didUpdateWidget(BattleTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    final isLunging = widget.unitState?.isLunging ?? false;
    if (isLunging && !_wasLunging) {
      _lungeCtrl.forward(from: 0).then((_) => _lungeCtrl.reverse());
    }
    _wasLunging = isLunging;

    final isShooting = widget.unitState?.isShooting ?? false;
    if (isShooting && !_wasShooting) {
      _projCtrl.forward(from: 0);
    }
    _wasShooting = isShooting;

    final floatingAmount = widget.unitState?.floatingDamage;
    final hasFloating = floatingAmount != null;
    if (hasFloating && floatingAmount != _lastFloatingDamage) {
      _floatCtrl.forward(from: 0);
    }
    _lastFloatingDamage = floatingAmount;
    _wasFloating = hasFloating;
  }

  @override
  void dispose() {
    _lungeCtrl.dispose();
    _projCtrl.dispose();
    _floatCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final uv = widget.unitState;
    final isAlive = uv?.alive ?? false;
    return AnimatedOpacity(
      opacity: isAlive || uv == null ? 1.0 : 0.3,
      duration: const Duration(milliseconds: 200),
      child: AnimatedBuilder(
        animation: Listenable.merge([_lungeAnim, _projAnim]),
        builder: (context, child) {
          // Lunge offset: toward the opponent side.
          final isAlly = widget.unitSide == UnitSide.ally;
          final dy = isAlly ? -12.0 : 12.0;
          final lungeOffset = _lungeAnim.value * dy;
          return Transform.translate(
            offset: Offset(0, lungeOffset),
            child: child,
          );
        },
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            StoneBoardTile(
              slot: widget.slot,
              unitSide: widget.unitSide,
              child: uv == null
                  ? null
                  : UnitAvatar(
                      unitId: uv.unitId.toJson(),
                      star: uv.star,
                      variant: UnitAvatarVariant.replay,
                      state: isAlive
                          ? UnitAvatarState.normal
                          : UnitAvatarState.dead,
                      side: widget.unitSide!,
                      hp: uv.hp,
                      maxHp: uv.maxHp,
                      expand: true,
                    ),
            ),
            // Projectile overlay.
            if (uv != null && uv.isShooting)
              Positioned.fill(
                child: AnimatedBuilder(
                  animation: _projAnim,
                  builder: (context, _) {
                    final isAlly = widget.unitSide == UnitSide.ally;
                    // Fly upward for allies, downward for enemies.
                    final travelDy = isAlly ? -60.0 : 60.0;
                    final progress = _projAnim.value;
                    return Opacity(
                      opacity: (1.0 - progress).clamp(0.0, 1.0),
                      child: Transform.translate(
                        offset: Offset(0, travelDy * progress),
                        child: Icon(
                          uv.projectileIcon,
                          size: 16,
                          color: isAlly
                              ? Theme.of(context)
                                  .extension<GameTheme>()!
                                  .ally
                              : Theme.of(context)
                                  .extension<GameTheme>()!
                                  .enemy,
                        ),
                      ),
                    );
                  },
                ),
              ),
            // Floating damage/heal number.
            if (uv != null && uv.floatingDamage != null)
              Positioned.fill(
                child: AnimatedBuilder(
                  animation: _floatAnim,
                  builder: (context, _) {
                    final progress = _floatAnim.value;
                    return Opacity(
                      opacity: (1.0 - progress).clamp(0.0, 1.0),
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: Transform.translate(
                          offset: Offset(0, -24 * progress),
                          child: Text(
                            uv.floatingIsHeal
                                ? '+${uv.floatingDamage}'
                                : '-${uv.floatingDamage}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: uv.floatingIsHeal
                                  ? Colors.green
                                  : Colors.red,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Tiny overlay that surfaces what the controller has loaded — for 2a's
/// "controller logs the batch" verification. Will be deleted once 2e
/// replaces it with the real playback HUD.
class _BatchSummary extends StatelessWidget {
  const _BatchSummary({required this.view, this.staleDetected = false});

  final BattleVisualState view;
  final bool staleDetected;

  @override
  Widget build(BuildContext context) {
    final batch = view.batch;
    if (batch == null) {
      if (staleDetected) {
        return const Text(
          'รอคิวการต่อสู้… (อาจต้องรอสักครู่ — กำลังเชื่อมต่อใหม่)',
          key: ValueKey('battle-batch-summary'),
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: Colors.orange),
        );
      }
      return const Text(
        'รอคิวการต่อสู้…',
        key: ValueKey('battle-batch-summary'),
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 12),
      );
    }
    return Text(
      'batch loaded · round ${batch.round} · ${batch.events.length} events · '
      'playhead ${(view.playheadProgress * 100).toStringAsFixed(0)}% '
      'index ${view.playheadIndex}',
      key: const ValueKey('battle-batch-summary'),
      textAlign: TextAlign.center,
      style: const TextStyle(fontSize: 12),
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
