# Combat Effects Overlay — Design

**Status:** Approved, not yet implemented
**Date:** 2026-09-13
**Owner:** fiat222
**Related issues:** #214 (P4-FE-01, melee lunge), #216 / PR #217 (P4-FE-03, heal bubble + hit shake + debuff)

## Problem

Live-testing the melee lunge fix on #214 surfaced a bigger issue than lunge distance: **combat animations (lunge, projectile, hit shake, heal bubble) don't reliably trigger at all** in a real match. The battle screen renders (both boards, VS divider, HP bars), units are visible and take damage correctly, but the transient animations never play.

Root cause (not yet 100% confirmed, but strongly suspected): `_BattleTileState` (in `battle_view.dart`) detects "should I animate now" by diffing `widget.unitState` against `oldWidget.unitState` inside `didUpdateWidget` (e.g. `isLunging && !_wasLunging`). This is fragile — if Flutter ever recreates the tile's `State` instead of reusing it (key mismatch, list restructuring, etc.), the `_wasLunging`/`_wasShooting`/`_lastDamageIndex` tracking fields reset silently and the transition is never detected. There's no visible error; the animation just never fires.

A second, independent problem: ally and enemy render on **two separate board widgets** (own `GridView` each — `_BoardPreview`), stacked in a `Column` (portrait) or side-by-side in a `Row` (landscape) inside `_BattleStage`. There's no shared coordinate space between an attacker's tile and its target's tile. The current lunge/projectile code approximates "toward the enemy" with a hardcoded scalar (`boardHeight`, vertical-only) — which is also wrong in landscape orientation, where the boards are arranged horizontally, not vertically.

## Goals

- Combat animations trigger reliably, every time, for every affected unit.
- Melee lunge and ranged projectile travel toward the **real screen position** of their target, correct in both portrait and landscape.
- Keep the two-board layout as-is (an intentional design choice, not something this work should change). No single shared "arena" grid.

## Non-goals

- Merging the two boards into one shared game grid / single arena.
- Camera work, zoom, or any change to how the boards themselves are laid out.
- Changing combat balance, event timing (`kCombatEventDuration` stays 600 ms/event), or the wire format of `CombatEvent`.

## Architecture

### 1. Trigger mechanism: pure derivation, not state-diffing

Every event already occupies a fixed 600 ms slot on the playhead (`kCombatEventDuration`), and the playhead's overall progress (`playheadProgress`, 0.0–1.0) is already known every frame via `battlePlaybackProvider`. Instead of an imperative "did this flag just flip" check, compute directly, on every build:

```dart
({CombatEvent event, double subProgress})? currentEventEffect(
  CombatEventBatch batch,
  double playheadProgress,
) {
  if (batch.events.isEmpty) return null;
  final exact = playheadProgress.clamp(0.0, 1.0) * batch.events.length;
  final index = exact.floor().clamp(0, batch.events.length - 1);
  final subProgress = (exact - index).clamp(0.0, 1.0);
  return (event: batch.events[index], subProgress: subProgress);
}
```

`subProgress` (0→1 within the current event's own 600 ms window) drives every visual: e.g. lunge = triangle wave (0→1 over the first half of the window, 1→0 over the second half), so "there and back" falls naturally out of the fixed window instead of needing its own `AnimationController` with its own imperative `forward().then(reverse)` call.

This has no hidden trigger to miss: at any given frame, "what's animating" is a pure function of `(batch, playheadProgress)`. If a widget rebuilds from scratch, the answer is identical — there's no history to lose.

This same pure-derivation approach replaces the shake and heal-bubble triggers too, but those stay rendered locally inside `BattleTile` (no cross-board travel needed — a unit reacting to being hit only ever needs its own tile's position).

### 2. Cross-board coordinate resolution

Two `GlobalKey`s (not one per tile — one per board's `GridView` container, so 2 total), attached in `_BoardPreview`. Given a `(MatchSide, slot)` and which board it's on, resolve its center in global screen coordinates:

```dart
Offset? tileGlobalCenter({
  required GlobalKey boardKey,
  required int slot,
  required double tileWidth,
  required double tileHeight,
  required double spacing,
  required bool reverseRows,
}) {
  final board = boardKey.currentContext?.findRenderObject() as RenderBox?;
  if (board == null || !board.hasSize) return null;
  final row = slot ~/ 3;
  final col = slot % 3;
  final displayRow = reverseRows ? 2 - row : row;
  final local = Offset(
    col * (tileWidth + spacing) + tileWidth / 2,
    displayRow * (tileHeight + spacing) + tileHeight / 2,
  );
  return board.localToGlobal(local);
}
```

The overlay (below) converts this global point into its own local coordinate space with `overlayBox.globalToLocal(...)`. This works identically in portrait and landscape — it's real geometry, not a guessed direction — and needs no per-tile keys or registries to keep in sync.

### 3. `CombatEffectsOverlay` widget

A `Stack` wraps the existing `_BattleStage` output (no change to `_BattleStage`'s own layout):

```
Stack
 ├─ _BattleStage (existing: both boards + divider, unchanged)
 └─ CombatEffectsOverlay (new, positioned.fill, IgnorePointer)
```

`CombatEffectsOverlay`:
- Watches `battlePlaybackProvider` directly (same provider `BattleView` already reads).
- Calls `currentEventEffect(...)` each build.
- If the current event is an `AttackEvent`, resolves attacker/target global centers via the two board `GlobalKey`s and renders exactly one effect widget:
  - Melee attacker (`fighter`/`tank`) → `_LungeStreak` (a short mark/icon travelling attacker→target and partway back, per the triangle-wave `subProgress`).
  - Ranged attacker (`ranger`/`healer`) → `_ProjectileMark` (icon travelling attacker→target, one-way, fading near arrival — same visual intent as today's projectile, now with a real destination).
- If either tile's position can't be resolved (not laid out yet, unit already removed from the tree), renders nothing for that frame (`SizedBox.shrink()`) — never throws.
- At most one effect renders at a time, matching the game's sequential (non-overlapping) event playback.

`BattleTile` keeps its own shake + heal-bubble rendering, switched to the same `currentEventEffect`-style pure derivation (keyed off whether *this tile's* `UnitKey` is the event's target), instead of the current `didUpdateWidget` flag-diffing. It also keeps a **small in-place recoil** on the attacker's own tile (a short, local nudge toward the target's general direction — reusing today's `lungeDx`/`lungeDy` direction fields, tiny fixed distance, no cross-board travel), rendered the same pure-derivation way, keyed off whether *this tile's* `UnitKey` is the event's attacker. This is deliberate layering, not redundant with the overlay: the recoil reads as "I am attacking," the overlay streak reads as "this is who I'm hitting" — together they're clearer than either alone (same idea as Marvel Snap-style reaction pairing discussed in #214).

### Data flow

```
BattlePlaybackController (existing)
   batch: CombatEventBatch, playheadProgress: double
        │
        ├─▶ BattleTile (existing, per-unit sprite/HP/shake/heal — now pure-derived)
        │
        └─▶ CombatEffectsOverlay (new)
                → currentEventEffect(batch, playheadProgress)
                → if AttackEvent: resolve attacker/target global centers
                → render _LungeStreak or _ProjectileMark, or nothing
```

No new state is introduced anywhere — `CombatEffectsOverlay` is a `ConsumerWidget` (stateless), not a `StatefulWidget`. There is nothing to get out of sync.

## Error handling

| Case | Behavior |
|---|---|
| Board `GlobalKey`'s `RenderBox` not yet laid out (first frame) | `tileGlobalCenter` returns `null`; overlay renders nothing that frame |
| Target unit already dead / removed before its own event resolves | Same — `null` position, skip that frame's effect silently |
| `batch.events` empty (shouldn't happen, defensive) | `currentEventEffect` returns `null`, overlay renders nothing |
| Orientation changes mid-battle (rotate device) | Geometry is re-resolved every build from live `RenderBox` positions — self-correcting, no stale state to invalidate |

## Testing

1. **Pure function tests** (no widget mounting) for `currentEventEffect`: given a batch and a `playheadProgress`, asserts the correct event index and `subProgress`, including boundary values (0.0, 1.0, exact event boundaries).
2. **Pure function tests** for `tileGlobalCenter`'s geometry math, isolated from `RenderBox` lookup (test the row/col → local-offset formula directly, including `reverseRows`).
3. **Widget tests** for `CombatEffectsOverlay`: mount a fake `BattleView` with a known `CombatEventBatch`, drive the playhead programmatically (no real animation timing), and assert:
   - A `_LungeStreak`/`_ProjectileMark` appears during its event's window and disappears outside it.
   - Its rendered position (`tester.getCenter(...)`) is closer to the target's tile than the attacker's tile at `subProgress` near 1.0 (regression guard for "does it actually travel", not just "does it exist").
   - No exception when a target tile is off-screen/unresolvable (simulate by an event referencing a slot with no rendered tile).
4. Existing `battle_view_lunge_test.dart` (`lungeOffsetFor`, the interim boardHeight-based fix from commit `439cd71`) gets **deleted** as part of this work — the function it tests is superseded, not reused, by `_LungeStreak`'s new positioning.

## Migration / merge-order note

PR #217 (#216, heal bubble + hit shake + debuff) touches the same `_BattleTileState` animation-trigger code this design replaces. Whichever of #214 or #217 lands second will need a real rebase, not a clean merge — flagged on both issues already. This design doesn't dictate merge order; that's a call for whoever's coordinating the two branches.
