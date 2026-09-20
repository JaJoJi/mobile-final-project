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

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderStack;

import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/unit_avatar.dart';
import '../../../shared/models/combat_event.dart';
import '../../../shared/models/match_state.dart';
import '../../../shared/models/unit.dart';
import '../board/stone_board_tile.dart';
import 'combat_effect_assets.dart';
import 'combat_effects_math.dart';

/// Side length of one tile on the board behind [boardKey], or `null` if
/// it isn't laid out yet. Mirrors `tileLocalCenter`'s grid assumptions.
double? _tileSize(GlobalKey boardKey) {
  final board = boardKey.currentContext?.findRenderObject() as RenderBox?;
  if (board == null || !board.hasSize) return null;
  return (board.size.width - 2 * AppSpacing.xs) / 3;
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
  required bool landscape,
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
    landscape: landscape,
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

    final landscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    final attackerLocal = _tileCenterRelativeTo(
      boardKey: attackerSide == mySide ? myBoardKey : opponentBoardKey,
      slot: attackerSlot,
      reverseRows: attackerSide != mySide,
      landscape: landscape,
      ancestor: ancestor,
    );
    final targetLocal = _tileCenterRelativeTo(
      boardKey: targetSide == mySide ? myBoardKey : opponentBoardKey,
      slot: targetSlot,
      reverseRows: targetSide != mySide,
      landscape: landscape,
      ancestor: ancestor,
    );
    if (attackerLocal == null || targetLocal == null) return null;

    final isMelee =
        attackerUnitId == UnitId.fighter || attackerUnitId == UnitId.tank;
    // A projectile is gone the instant it connects. Melee has no such cut
    // — the attacker travels back to its own tile over the second half of
    // the wave, which is the whole point of the lunge.
    if (!isMelee && current.subProgress >= kProjectileImpactFraction) {
      return null;
    }
    // Travel communicates who attacked whom, just like the melee lunge.
    // Keep this functional motion on the preserved battle timeline even
    // when the platform requests reduced decorative animations. Freezing
    // progress at 0.85 made shots appear beside the victim for the whole
    // event instead of travelling from their source.
    final progress = isMelee
        ? meleeTravel(current.subProgress)
        : projectileTravel(current.subProgress);
    final position = Offset.lerp(attackerLocal, targetLocal, progress)!;

    // Melee reads as the unit itself charging the target and returning,
    // so draw the attacker's actual sprite travelling the path (its home
    // tile hides itself meanwhile — see `UnitVisualState.isMeleeAttacking`).
    // Ranged keeps a small projectile mark, which is what it should be.
    if (isMelee) {
      final size = _tileSize(
        attackerSide == mySide ? myBoardKey : opponentBoardKey,
      );
      if (size == null) return null;
      return Stack(
        children: [
          Positioned(
            left: position.dx - size / 2,
            top: position.dy - size / 2,
            width: size,
            height: size,
            child: IgnorePointer(
              key: const ValueKey('lunge-traveler'),
              child: BoardPiecePlacement(
                child: RepaintBoundary(
                  child: UnitAvatar(
                    unitId: attackerUnitId.toJson(),
                    star: event.attackerStar ?? 0,
                    variant: UnitAvatarVariant.replay,
                    side:
                        attackerSide == mySide ? UnitSide.ally : UnitSide.enemy,
                    hp: 1,
                    maxHp: 1,
                    expand: true,
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }

    // Sized against the measured tile rather than a fixed pixel count, so
    // the projectile keeps the same visual weight on a phone and a tablet.
    final projectileSize =
        (_tileSize(attackerSide == mySide ? myBoardKey : opponentBoardKey) ??
                60) *
            0.82;
    final effectKind = combatEffectForEvent(event);
    if (effectKind == null || effectKind == CombatEffectKind.healerHeal) {
      return null;
    }
    final direction = targetLocal - attackerLocal;
    final angle = math.atan2(direction.dy, direction.dx);

    // A self-contained `Stack` + `Positioned` pair, scoped to this
    // widget's own subtree, so the `Positioned` below always has a valid
    // `Stack` ancestor to apply `StackParentData` to regardless of how
    // this widget is embedded by its caller.
    return Stack(
      children: [
        Positioned(
          left: position.dx - projectileSize / 2,
          top: position.dy - projectileSize / 2,
          child: Transform.rotate(
            key: const ValueKey('projectile-mark'),
            angle: angle,
            child: Image.asset(
              effectKind.assetPath,
              key: ValueKey('projectile-${effectKind.name}'),
              width: projectileSize,
              height: projectileSize,
              fit: BoxFit.contain,
            ),
          ),
        ),
      ],
    );
  }
}
