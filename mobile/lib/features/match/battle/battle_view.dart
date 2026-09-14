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
import 'combat_effects_overlay.dart';

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
  Timer? _ackTimer;
  bool _staleDetected = false;

  /// Wall-clock anchor for playback. The playhead's *position* is derived
  /// from elapsed real time, not from accumulated animation frames:
  /// browsers suspend `requestAnimationFrame` entirely in a background
  /// tab, which would otherwise freeze one player's replay at 0% while
  /// the other runs to 100% (and desync the two clients permanently).
  /// Anchoring to wall time means a tab that was hidden simply jumps to
  /// the correct position on its next frame.
  DateTime? _playbackStart;
  Duration _playbackTotal = Duration.zero;
  final GlobalKey _myBoardKey = GlobalKey();
  final GlobalKey _opponentBoardKey = GlobalKey();

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

    // `combatEventsProvider` is not autoDispose and keeps consuming the WS
    // stream in the background even while no BattleView is mounted (e.g.
    // during the shop/planning phase) — so a batch that arrives right
    // before this widget mounts would otherwise be missed entirely.
    // `listenManual` (initState-safe, unlike `ref.listen` in build, which
    // explicitly does not support `fireImmediately`) replays whatever
    // value the provider already holds at mount time; the `batch.round`
    // guard below makes this safe against a stale previous round's batch.
    ref.listenManual<AsyncValue<CombatEventBatch>>(
      combatEventsProvider,
      (prev, next) {
        final batch = next.valueOrNull;
        if (batch == null) return;
        if (batch.matchId != widget.matchId) return;
        if (batch.round != widget.match.round) return;
        _onBatch(batch);
      },
      fireImmediately: true,
    );
  }

  @override
  void dispose() {
    _staleTimer?.cancel();
    _ackTimer?.cancel();
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
    _playbackTotal = Duration(milliseconds: totalMs);
    _playbackStart = DateTime.now();
    // The controller only drives repaints now — position comes from wall
    // time in [_pushPlayhead], so a throttled tab self-corrects.
    _playhead
      ..duration = _playbackTotal
      ..forward(from: 0);
    // Ack on a timer, not on animation completion: a background tab gets
    // no animation frames at all, so a frame-driven ack would never fire
    // and the round would hang until the server's 60s combat timeout.
    // Browsers throttle background timers but do still run them.
    _ackTimer?.cancel();
    _ackTimer = Timer(
      _playbackTotal + const Duration(milliseconds: 500),
      _ack,
    );
    setState(() {}); // refresh the playhead listener binding below
  }

  bool _acked = false;

  /// Idempotent — may be reached from either the ack timer or the
  /// animation completing, whichever happens first.
  void _ack() {
    if (_acked || !mounted) return;
    _acked = true;
    widget.onSkip();
  }

  void _onPlayheadStatusChanged(AnimationStatus status) {
    if (_playhead.isCompleted) {
      // Freeze 500ms (battle_end spec), then ack.
      Future<void>.delayed(const Duration(milliseconds: 500), _ack);
    }
  }

  @override
  Widget build(BuildContext context) {
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
          opponentBoard:
              widget.match.opponent.boardSummary.asMap().entries.map((entry) {
            final o = entry.value;
            if (o == null) return null;
            return Unit(
              instanceId: 'opponent-${entry.key}-${o.unitId.name}',
              unitId: o.unitId,
              star: o.star,
              hp: unitMaxHp(o.unitId),
              maxHp: unitMaxHp(o.unitId),
            );
          }).toList(),
          mySide: widget.match.yourSide,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                _BattleStage(
                  match: widget.match,
                  game: game,
                  unitStates: unitStates,
                  myBoardKey: _myBoardKey,
                  opponentBoardKey: _opponentBoardKey,
                ),
                CombatEffectsOverlay(
                  batch: view.batch,
                  playheadProgress: view.playheadProgress,
                  myBoardKey: _myBoardKey,
                  opponentBoardKey: _opponentBoardKey,
                  mySide: widget.match.yourSide,
                ),
              ],
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
              disabledReason: widget.skipSubmitted ? 'ส่งผลการทดสอบแล้ว' : null,
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
    final start = _playbackStart;
    final totalMs = _playbackTotal.inMilliseconds;
    if (start == null || totalMs <= 0) {
      _controller.seekTo(_playhead.value);
      return;
    }
    final elapsedMs = DateTime.now().difference(start).inMilliseconds;
    _controller.seekTo((elapsedMs / totalMs).clamp(0.0, 1.0));
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
    required this.myBoardKey,
    required this.opponentBoardKey,
  });

  final MatchState match;
  final GameTheme game;
  final Map<UnitKey, UnitVisualState> unitStates;
  final GlobalKey myBoardKey;
  final GlobalKey opponentBoardKey;

  @override
  Widget build(BuildContext context) {
    final orientation = MediaQuery.orientationOf(context);
    final enemySide =
        match.yourSide == MatchSide.p1 ? MatchSide.p2 : MatchSide.p1;
    final mine = _BoardPreview(
      boardKey: const ValueKey('battle-player-board'),
      positionKey: myBoardKey,
      label: 'คุณ',
      icon: Icons.shield_outlined,
      color: game.ally,
      units: match.roster.board,
      side: match.yourSide,
      mySide: match.yourSide,
      unitStates: unitStates,
      showLabel: orientation == Orientation.landscape,
    );
    final opponent = _BoardPreview(
      boardKey: const ValueKey('battle-opponent-board'),
      positionKey: opponentBoardKey,
      label: 'คู่แข่ง',
      icon: Icons.sports_martial_arts_outlined,
      color: game.enemy,
      opponentUnits: match.opponent.boardSummary,
      side: enemySide,
      mySide: match.yourSide,
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
    required this.positionKey,
    required this.label,
    required this.icon,
    required this.color,
    required this.side,
    required this.mySide,
    required this.unitStates,
    this.units,
    this.opponentUnits,
    this.reverseRows = false,
    this.showLabel = true,
  });

  final Key boardKey;
  final GlobalKey positionKey;
  final String label;
  final IconData icon;
  final Color color;
  final MatchSide side;
  final MatchSide mySide;
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
              final tileWidth = (boardSize - 2 * AppSpacing.xs) / 3;
              final tileHeight = (boardSize - 2 * AppSpacing.xs) / 3;
              return Center(
                child: SizedBox.square(
                  key: boardKey,
                  dimension: boardSize,
                  child: KeyedSubtree(
                    key: positionKey,
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
                              ? (side == mySide
                                  ? UnitSide.ally
                                  : UnitSide.enemy)
                              : null,
                          unitState: uv,
                          tileWidth: tileWidth,
                          tileHeight: tileHeight,
                        );
                      },
                    ),
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
/// hit-shake, heal-bubble, floating damage numbers, and debuff tint/badge
/// derived from the event stream. Melee lunge/ranged projectile animation
/// lives in [CombatEffectsOverlay], not here.
class BattleTile extends StatefulWidget {
  const BattleTile({
    super.key,
    required this.slot,
    required this.unitSide,
    this.unitState,
    this.tileWidth = 80,
    this.tileHeight = 80,
  });

  final int slot;
  final UnitSide? unitSide;
  final UnitVisualState? unitState;
  final double tileWidth;
  final double tileHeight;

  @override
  State<BattleTile> createState() => _BattleTileState();
}

class _BattleTileState extends State<BattleTile> with TickerProviderStateMixin {
  late final AnimationController _floatCtrl;
  late final Animation<double> _floatAnim;
  late final AnimationController _shakeCtrl;
  late final Animation<double> _shakeAnim;
  late final AnimationController _healBubbleCtrl;
  late final Animation<double> _healBubbleAnim;
  late final AnimationController _recoilCtrl;
  late final Animation<double> _recoilAnim;
  bool _wasFloating = false;
  int? _lastFloatingDamage;
  int? _lastDamageIndex;
  int? _lastHealIndex;
  int? _lastRecoilIndex;

  /// In-place nudge distance (px) — deliberately not a real cross-board
  /// travel distance (that's CombatEffectsOverlay's job), just enough to
  /// clearly read as "this unit just attacked" on a ~97px tile.
  static const double _recoilDistance = 18;

  @override
  void initState() {
    super.initState();
    _floatCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _floatAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _floatCtrl, curve: AppMotion.standard),
    );
    // Hit shake: constant intensity, ~200ms, horizontal only.
    _shakeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _shakeAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _shakeCtrl, curve: Curves.easeOut),
    );
    // Heal bubble: expanding green circle, ~600ms, emit-and-dispose.
    _healBubbleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _healBubbleAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _healBubbleCtrl, curve: AppMotion.standard),
    );
    // Recoil: small there-and-back nudge, ~250ms total.
    _recoilCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 125),
    );
    _recoilAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _recoilCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void didUpdateWidget(BattleTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    final floatingAmount = widget.unitState?.floatingDamage;
    final hasFloating = floatingAmount != null;
    if (hasFloating && floatingAmount != _lastFloatingDamage) {
      _floatCtrl.forward(from: 0);
    }
    _lastFloatingDamage = floatingAmount;
    _wasFloating = hasFloating;

    // Hit shake: trigger on new damage event index.
    final damageIdx = widget.unitState?.lastDamageEventIndex;
    if (damageIdx != null && damageIdx != _lastDamageIndex) {
      _shakeCtrl.forward(from: 0);
    }
    _lastDamageIndex = damageIdx;

    // Heal bubble: trigger on new heal event index.
    final healIdx = widget.unitState?.healEventIndex;
    if (healIdx != null && healIdx != _lastHealIndex) {
      _healBubbleCtrl.forward(from: 0);
    }
    _lastHealIndex = healIdx;

    // Recoil: trigger on new melee-attack event index for this unit.
    final recoilIdx = widget.unitState?.recoilEventIndex;
    if (recoilIdx != null && recoilIdx != _lastRecoilIndex) {
      _recoilCtrl.forward(from: 0).then((_) => _recoilCtrl.reverse());
    }
    _lastRecoilIndex = recoilIdx;
  }

  @override
  void dispose() {
    _floatCtrl.dispose();
    _shakeCtrl.dispose();
    _healBubbleCtrl.dispose();
    _recoilCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final uv = widget.unitState;
    final isAlive = uv?.alive ?? false;
    return AnimatedOpacity(
      opacity: uv == null ? 0.3 : (isAlive ? 1.0 : 0.3),
      duration: const Duration(milliseconds: 200),
      child: AnimatedBuilder(
        animation: Listenable.merge([_shakeAnim, _recoilAnim]),
        builder: (context, child) {
          // Hit shake: constant 6px horizontal offset, oscillating.
          final shakeProgress = _shakeAnim.value;
          final shakeOffset = shakeProgress > 0
              ? Offset(
                  6 * (1 - shakeProgress) * (shakeProgress < 0.5 ? 1.0 : -1.0),
                  0,
                )
              : Offset.zero;
          // Recoil: small in-place nudge toward the target, there-and-back.
          // `recoilDy` is "toward the enemy board" in the viewer's frame,
          // so which screen axis that maps to depends on how the two
          // boards are arranged: stacked in portrait, side-by-side
          // (mine left, opponent right) in landscape.
          final recoilTravel =
              (widget.unitState?.recoilDy ?? 0) * _recoilDistance;
          final recoilLean =
              (widget.unitState?.recoilDx ?? 0) * _recoilDistance * 0.5;
          final isPortrait =
              MediaQuery.orientationOf(context) == Orientation.portrait;
          final recoilOffset = (isPortrait
                  ? Offset(recoilLean, recoilTravel)
                  : Offset(-recoilTravel, recoilLean)) *
              _recoilAnim.value;
          return Transform.translate(
            offset: shakeOffset + recoilOffset,
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
            // Debuff tint overlay — persistent blue wash when debuff active.
            if (uv?.debuff != null)
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: uv!.debuff!.color.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            // Debuff badge — small icon in top-right corner.
            if (uv?.debuff != null)
              const Positioned(
                top: 2,
                right: 2,
                child: Icon(
                  Icons.speed,
                  size: 12,
                  color: Color(0xFF42A5F5),
                ),
              ),
            // Heal bubble — expanding green circle, emit-and-dispose.
            if (uv != null && uv.healEventIndex != null)
              Positioned.fill(
                child: AnimatedBuilder(
                  animation: _healBubbleAnim,
                  builder: (context, _) {
                    final progress = _healBubbleAnim.value;
                    final radius = widget.tileWidth * 0.6 * progress;
                    return Center(
                      child: Container(
                        width: radius * 2,
                        height: radius * 2,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.green.withOpacity(
                            (0.3 * (1.0 - progress)).clamp(0.0, 1.0),
                          ),
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
                    final isHeal = uv.floatingIsHeal;
                    return Opacity(
                      opacity: (1.0 - progress).clamp(0.0, 1.0),
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: Transform.translate(
                          offset: Offset(0, -32 * progress),
                          child: isHeal
                              ? Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: Colors.green.withOpacity(0.3),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Text(
                                    '+${uv.floatingDamage}',
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.green,
                                    ),
                                  ),
                                )
                              : Text(
                                  '-${uv.floatingDamage}',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.red,
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
