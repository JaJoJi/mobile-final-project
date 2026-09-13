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

    // Walks up to the *nearest* `RenderStack`-or-subtype ancestor — not
    // "any" ancestor works, despite what this comment used to claim. This
    // is only correct because `CombatEffectsOverlay` is wired as a direct
    // sibling of the boards inside the same `Stack` (see `battle_view.dart`
    // for that wiring), so the nearest match is guaranteed to be the
    // intended shared coordinate space.
    //
    // Two ways this can silently break, with no error or crash — just
    // wrong on-screen positions:
    //  - `RenderIndexedStack` (from Flutter's `IndexedStack`) is itself a
    //    `RenderStack` subtype. An `IndexedStack` sitting anywhere between
    //    this widget and the intended layout `Stack` would be picked up
    //    instead, silently.
    //  - Nothing in the type system ties this lookup to *the* boards'
    //    `Stack` specifically. If this widget is ever nested one level
    //    deeper inside another `Stack` (or `IndexedStack`) later, it will
    //    silently resolve to that nearer, wrong ancestor instead.
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
