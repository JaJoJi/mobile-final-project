/// Shared overlay rendered above both boards in `BattleView`, driving the
/// melee lunge and ranged projectile from the real on-screen position of
/// the attacker and target tiles instead of a hardcoded direction/distance
/// (P4-FE-01). See `docs/09-combat-effects-overlay-design.md`.
///
/// Position resolution deliberately happens inside a [LayoutBuilder]'s
/// `builder` callback rather than in `build()`. `Stack` lays out its
/// *positioned* children in list order, so by the time this (later, also
/// positioned) sibling's `LayoutBuilder` callback runs — mid-layout — the
/// board siblings earlier in the list have already been measured and
/// positioned, even on the very first frame. Reading `RenderBox` geometry
/// from a plain `build()` cannot make that guarantee: build always
/// completes, for the *whole* tree, before layout of any of it begins, so
/// sibling boards would never yet have a `size` to read.
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderStack;

import '../../../core/theme/app_spacing.dart';
import '../../../shared/models/combat_event.dart';
import '../../../shared/models/match_state.dart';
import '../../../shared/models/unit.dart';
import 'combat_effects_math.dart';

/// Global-space center of board [slot], or `null` if [boardKey]'s
/// `RenderBox` isn't laid out yet (first frame, or the widget was never
/// mounted).
Offset? tileGlobalCenter({
  required GlobalKey boardKey,
  required int slot,
  required bool reverseRows,
}) {
  final board = boardKey.currentContext?.findRenderObject() as RenderBox?;
  if (board == null || !board.hasSize) return null;
  final local = tileLocalCenter(
    slot: slot,
    boardWidth: board.size.width,
    boardHeight: board.size.height,
    spacing: AppSpacing.xs,
    reverseRows: reverseRows,
  );
  return board.localToGlobal(local);
}

/// Center of board [slot], expressed in [ancestor]'s local coordinate
/// space instead of the screen's global space. Resolving relative to a
/// shared ancestor (a single `localToGlobal(point, ancestor: ...)` hop)
/// avoids needing this overlay's *own* box to already have a finalized
/// screen position — which, mid-layout on the first frame, it doesn't.
Offset? _tileCenterRelativeTo({
  required GlobalKey boardKey,
  required int slot,
  required bool reverseRows,
  required RenderObject ancestor,
}) {
  final board = boardKey.currentContext?.findRenderObject() as RenderBox?;
  if (board == null || !board.hasSize) return null;
  final local = tileLocalCenter(
    slot: slot,
    boardWidth: board.size.width,
    boardHeight: board.size.height,
    spacing: AppSpacing.xs,
    reverseRows: reverseRows,
  );
  return board.localToGlobal(local, ancestor: ancestor);
}

/// Renders at most one attack effect (melee lunge or ranged projectile) —
/// whichever `AttackEvent` is active at the current playhead position —
/// travelling between the attacker's and target's real tile positions on
/// their respective boards.
class CombatEffectsOverlay extends StatelessWidget {
  const CombatEffectsOverlay({
    super.key,
    required this.batch,
    required this.playheadProgress,
    required this.myBoardKey,
    required this.opponentBoardKey,
    required this.mySide,
  });

  final CombatEventBatch? batch;
  final double playheadProgress;
  final GlobalKey myBoardKey;
  final GlobalKey opponentBoardKey;
  final MatchSide mySide;

  @override
  Widget build(BuildContext context) {
    // `Positioned` must be the direct `RenderObjectWidget` child of the
    // enclosing `Stack` (it applies `StackParentData` to whatever sits
    // immediately below it), so `IgnorePointer` — which has its own
    // `RenderObject` — goes *inside* it, not outside. `Positioned.fill`
    // (rather than a bare, non-positioned child) is also what makes
    // `Stack` treat this as a *positioned* sibling for layout-ordering
    // purposes — see the class doc.
    return Positioned.fill(
      child: IgnorePointer(
        child: LayoutBuilder(
          builder: (innerContext, constraints) =>
              _resolveEffect(innerContext) ?? const SizedBox.shrink(),
        ),
      ),
    );
  }

  Widget? _resolveEffect(BuildContext context) {
    final b = batch;
    if (b == null) return null;
    final current = currentEventEffect(b.events, playheadProgress);
    if (current == null) return null;

    final event = current.event;
    if (event is! AttackEvent) return null;
    final attackerSlot = event.attackerSlot;
    final attackerSide = event.attackerSide;
    final attackerUnitId = event.attackerUnitId;
    final targetSlot = event.targetSlot;
    final targetSide = event.targetSide;
    if (attackerSlot == null ||
        attackerSide == null ||
        attackerUnitId == null ||
        targetSlot == null ||
        targetSide == null) {
      return null;
    }

    // Any already-mounted ancestor works as the shared coordinate space —
    // the enclosing `Stack` is the natural, always-present choice.
    final ancestor = context.findAncestorRenderObjectOfType<RenderStack>();
    if (ancestor == null) return null;

    final attackerLocal = _tileCenterRelativeTo(
      boardKey: attackerSide == mySide ? myBoardKey : opponentBoardKey,
      slot: attackerSlot,
      reverseRows: attackerSide != mySide,
      ancestor: ancestor,
    );
    final targetLocal = _tileCenterRelativeTo(
      boardKey: targetSide == mySide ? myBoardKey : opponentBoardKey,
      slot: targetSlot,
      reverseRows: targetSide != mySide,
      ancestor: ancestor,
    );
    if (attackerLocal == null || targetLocal == null) return null;

    final isMelee =
        attackerUnitId == UnitId.fighter || attackerUnitId == UnitId.tank;
    final progress =
        isMelee ? triangleWave(current.subProgress) : current.subProgress;
    final position = Offset.lerp(attackerLocal, targetLocal, progress)!;

    // A self-contained `Stack` + `Positioned` pair, scoped to this
    // widget's own subtree, so the `Positioned` below always has a valid
    // `Stack` ancestor to apply `StackParentData` to regardless of how
    // this widget is embedded by its caller.
    return Stack(
      children: [
        Positioned(
          left: position.dx - 12,
          top: position.dy - 12,
          child: Icon(
            key: ValueKey(isMelee ? 'lunge-streak' : 'projectile-mark'),
            isMelee ? Icons.flash_on : Icons.arrow_forward,
            size: 24,
            color:
                attackerSide == mySide ? Colors.blueAccent : Colors.redAccent,
          ),
        ),
      ],
    );
  }
}
