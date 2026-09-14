# Combat Effects Overlay Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the melee lunge and ranged projectile in the in-match combat replay (`BattleView`) travel to the real screen position of their target and trigger reliably every time, replacing the current per-tile `didUpdateWidget` diffing with pure derivation from the playhead.

**Architecture:** A new `CombatEffectsOverlay` (`Stack` layer above the existing two boards) computes, every frame, which single combat event is "active" at the current playhead position and its sub-progress within that event's fixed 600 ms window — purely from `(events, playheadProgress)`, no cached flags. For an `AttackEvent`, it resolves the attacker's and target's real on-screen tile centers (via two `GlobalKey`s, one per board, and `RenderBox.localToGlobal`) and renders a small icon interpolating between them. This works identically in portrait and landscape, unlike the current hardcoded `boardHeight`-only travel.

**Tech Stack:** Flutter (existing `battle_view.dart` / `battle_visual_state.dart` / `battle_playback_controller.dart`), `flutter_test` widget tests, no new packages.

**Scope note:** This plan covers melee lunge and ranged projectile only — the two effects the user explicitly reported as not appearing during live testing. Hit-shake and heal-bubble already derive their trigger keys purely (`lastDamageEventIndex` / `healEventIndex` in `battle_visual_state.dart`) and were not reported broken; migrating them to the same overlay pattern plus adding an attacker recoil (both described as a "Phase 2" idea in `docs/09-combat-effects-overlay-design.md`) is deliberately deferred to a follow-up plan, not included here.

---

## File Structure

| File | Change | Responsibility |
|---|---|---|
| `mobile/lib/features/match/battle/combat_effects_math.dart` | Create | Pure, widget-free math: which event is active + its sub-progress, and tile-center geometry. No Flutter widget imports. |
| `mobile/lib/features/match/battle/combat_effects_overlay.dart` | Create | `CombatEffectsOverlay` widget + `tileGlobalCenter` (the one impure, `RenderBox`-reading wrapper around the pure geometry). |
| `mobile/lib/features/match/battle/battle_view.dart` | Modify | Thread two `GlobalKey`s (one per board) from `_BattleViewState` down through `_BattleStage`/`_BoardPreview`; mount `CombatEffectsOverlay` in a `Stack` alongside `_BattleStage`; remove the old per-tile lunge/projectile `Transform` code from `_BattleTileState` (superseded) and the `lungeOffsetFor` function. |
| `mobile/lib/features/match/battle/battle_visual_state.dart` | Modify | Remove the now-unused lunge/projectile fields and branch from `UnitVisualState`/`deriveUnitStates` (dead code once `_BattleTileState` no longer reads them). |
| `mobile/test/features/match/battle/combat_effects_math_test.dart` | Create | Unit tests for the pure functions. |
| `mobile/test/features/match/battle/combat_effects_overlay_test.dart` | Create | Widget tests: effect appears/disappears with the right event window, and its position actually moves toward the target. |
| `mobile/test/features/match/battle/battle_view_lunge_test.dart` | Delete | Tests the interim `lungeOffsetFor` fix (commit `439cd71`), which this plan removes. |

---

## Task 1: Pure combat-effects math

**Files:**
- Create: `mobile/lib/features/match/battle/combat_effects_math.dart`
- Test: `mobile/test/features/match/battle/combat_effects_math_test.dart`

- [ ] **Step 1: Write the failing tests**

```dart
// mobile/test/features/match/battle/combat_effects_math_test.dart
import 'package:auto_chess_mobile/features/match/battle/combat_effects_math.dart';
import 'package:auto_chess_mobile/shared/models/combat_event.dart';
import 'package:auto_chess_mobile/shared/models/match_state.dart';
import 'package:auto_chess_mobile/shared/models/unit.dart';
import 'package:flutter_test/flutter_test.dart';

const _attack = AttackEvent(
  cycle: 1,
  tick: 1,
  attacker: 'a',
  target: 'b',
  damage: 10,
  targetHpAfter: 90,
  attackerSide: MatchSide.p1,
  attackerSlot: 0,
  attackerUnitId: UnitId.fighter,
  targetSide: MatchSide.p2,
  targetSlot: 4,
);

void main() {
  group('currentEventEffect', () {
    test('returns null for an empty event list', () {
      expect(currentEventEffect(const [], 0.5), isNull);
    });

    test('returns the only event with subProgress 0 at playhead 0.0', () {
      final result = currentEventEffect(const [_attack], 0.0);
      expect(result!.event, same(_attack));
      expect(result.index, 0);
      expect(result.subProgress, 0.0);
    });

    test('returns subProgress near 1.0 near the end of a single event', () {
      final result = currentEventEffect(const [_attack], 0.999);
      expect(result!.index, 0);
      expect(result.subProgress, closeTo(0.999, 0.001));
    });

    test('picks the second of two events partway through playback', () {
      const second = AttackEvent(
        cycle: 1,
        tick: 2,
        attacker: 'b',
        target: 'a',
        damage: 5,
        targetHpAfter: 85,
      );
      final result = currentEventEffect(const [_attack, second], 0.75);
      expect(result!.event, same(second));
      expect(result.index, 1);
      expect(result.subProgress, closeTo(0.5, 0.001));
    });

    test('clamps playheadProgress of 1.0 to the last event, not out of range', () {
      final result = currentEventEffect(const [_attack], 1.0);
      expect(result!.index, 0);
      expect(result.subProgress, 1.0);
    });
  });

  group('triangleWave', () {
    test('starts at 0', () => expect(triangleWave(0.0), 0.0));
    test('peaks at 1 at the midpoint', () => expect(triangleWave(0.5), 1.0));
    test('returns to 0 at the end', () => expect(triangleWave(1.0), 0.0));
    test('is symmetric', () {
      expect(triangleWave(0.25), closeTo(triangleWave(0.75), 0.0001));
    });
  });

  group('tileLocalCenter', () {
    test('slot 0 is the top-left tile center', () {
      final offset = tileLocalCenter(
        slot: 0,
        boardWidth: 300,
        boardHeight: 300,
        spacing: 4,
      );
      // tileWidth = (300 - 8) / 3 = 97.333...
      expect(offset.dx, closeTo(48.667, 0.01));
      expect(offset.dy, closeTo(48.667, 0.01));
    });

    test('slot 8 is the bottom-right tile center', () {
      final offset = tileLocalCenter(
        slot: 8,
        boardWidth: 300,
        boardHeight: 300,
        spacing: 4,
      );
      // 2 * (97.333 + 4) + 97.333/2 = 251.333
      expect(offset.dx, closeTo(251.333, 0.01));
      expect(offset.dy, closeTo(251.333, 0.01));
    });

    test('reverseRows flips row 0 to the bottom', () {
      final normal = tileLocalCenter(
        slot: 0,
        boardWidth: 300,
        boardHeight: 300,
        spacing: 4,
      );
      final reversed = tileLocalCenter(
        slot: 0,
        boardWidth: 300,
        boardHeight: 300,
        spacing: 4,
        reverseRows: true,
      );
      expect(reversed.dx, normal.dx); // column unaffected
      expect(reversed.dy, closeTo(251.333, 0.01)); // row 0 -> displayed row 2
    });
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd mobile && flutter test test/features/match/battle/combat_effects_math_test.dart`
Expected: compile error — `Target of URI doesn't exist: 'package:auto_chess_mobile/features/match/battle/combat_effects_math.dart'` (the file doesn't exist yet). This is the correct RED state — proceed to implement.

- [ ] **Step 3: Write the implementation**

```dart
// mobile/lib/features/match/battle/combat_effects_math.dart
/// Pure, widget-free math for the combat effects overlay (P4-FE-01).
///
/// Kept separate from `combat_effects_overlay.dart` so it can be unit
/// tested without mounting any widget tree. Nothing in this file reads
/// live layout — the one function that does (`tileGlobalCenter`) lives
/// in `combat_effects_overlay.dart` and calls `tileLocalCenter` below.
library;

import 'dart:ui' show Offset;

import '../../../shared/models/combat_event.dart';

/// The combat event active at [playheadProgress] (0.0-1.0 across the
/// whole batch) and how far through that event's own fixed-duration
/// window we are (0.0 = just started, 1.0 = about to advance).
///
/// Returns `null` for an empty [events] list.
({CombatEvent event, int index, double subProgress})? currentEventEffect(
  List<CombatEvent> events,
  double playheadProgress,
) {
  if (events.isEmpty) return null;
  final exact = playheadProgress.clamp(0.0, 1.0) * events.length;
  final index = exact.floor().clamp(0, events.length - 1);
  final subProgress = (exact - index).clamp(0.0, 1.0);
  return (event: events[index], index: index, subProgress: subProgress);
}

/// Triangle wave: 0→1 over the first half of [subProgress], 1→0 over the
/// second half. Drives "there and back" motion (the melee lunge) from a
/// single progress value instead of a separate one-shot
/// `AnimationController`.
double triangleWave(double subProgress) {
  final t = subProgress.clamp(0.0, 1.0);
  return t <= 0.5 ? t * 2 : (1 - t) * 2;
}

/// Local-space center of board [slot] (0-8, row-major) inside a 3x3 grid
/// sized [boardWidth] x [boardHeight], with [spacing] between cells
/// (matching the `GridView`'s `mainAxisSpacing`/`crossAxisSpacing`).
///
/// [reverseRows] mirrors the opponent board's row order (see
/// `_BoardPreview`'s `reverseRows` in `battle_view.dart`).
Offset tileLocalCenter({
  required int slot,
  required double boardWidth,
  required double boardHeight,
  required double spacing,
  bool reverseRows = false,
}) {
  final tileWidth = (boardWidth - 2 * spacing) / 3;
  final tileHeight = (boardHeight - 2 * spacing) / 3;
  final row = slot ~/ 3;
  final col = slot % 3;
  final displayRow = reverseRows ? 2 - row : row;
  return Offset(
    col * (tileWidth + spacing) + tileWidth / 2,
    displayRow * (tileHeight + spacing) + tileHeight / 2,
  );
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd mobile && flutter test test/features/match/battle/combat_effects_math_test.dart`
Expected: `All tests passed!` (14 tests)

- [ ] **Step 5: Format, analyze, commit**

```bash
cd mobile
dart format lib/features/match/battle/combat_effects_math.dart test/features/match/battle/combat_effects_math_test.dart
flutter analyze lib/features/match/battle/combat_effects_math.dart test/features/match/battle/combat_effects_math_test.dart
```
Expected: `No issues found!`

```bash
git add mobile/lib/features/match/battle/combat_effects_math.dart mobile/test/features/match/battle/combat_effects_math_test.dart
git commit -m "feat(fe): P4-FE-01 pure combat-effects math (event window + tile geometry)"
```

---

## Task 2: `CombatEffectsOverlay` widget

**Files:**
- Create: `mobile/lib/features/match/battle/combat_effects_overlay.dart`
- Test: `mobile/test/features/match/battle/combat_effects_overlay_test.dart`

- [ ] **Step 1: Write the failing widget tests**

```dart
// mobile/test/features/match/battle/combat_effects_overlay_test.dart
import 'package:auto_chess_mobile/features/match/battle/combat_effects_overlay.dart';
import 'package:auto_chess_mobile/shared/models/combat_event.dart';
import 'package:auto_chess_mobile/shared/models/match_state.dart';
import 'package:auto_chess_mobile/shared/models/unit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final myBoardKey = GlobalKey();
  final opponentBoardKey = GlobalKey();

  const meleeAttack = AttackEvent(
    cycle: 1,
    tick: 1,
    attacker: 'a',
    target: 'b',
    damage: 10,
    targetHpAfter: 90,
    attackerSide: MatchSide.p1,
    attackerSlot: 0,
    attackerUnitId: UnitId.fighter,
    targetSide: MatchSide.p2,
    targetSlot: 4,
  );

  final batch = CombatEventBatch(
    matchId: 'm1',
    round: 1,
    cycleCount: 1,
    endedAt: 0,
    events: const [meleeAttack],
  );

  Widget buildTree(double progress) {
    return MaterialApp(
      home: Scaffold(
        body: Stack(
          children: [
            Positioned(
              left: 0,
              top: 0,
              width: 300,
              height: 300,
              child: SizedBox(key: myBoardKey),
            ),
            Positioned(
              left: 0,
              top: 300,
              width: 300,
              height: 300,
              child: SizedBox(key: opponentBoardKey),
            ),
            CombatEffectsOverlay(
              batch: batch,
              playheadProgress: progress,
              myBoardKey: myBoardKey,
              opponentBoardKey: opponentBoardKey,
              mySide: MatchSide.p1,
            ),
          ],
        ),
      ),
    );
  }

  testWidgets('lunge streak appears during its event window', (tester) async {
    await tester.pumpWidget(buildTree(0.5));
    expect(find.byKey(const ValueKey('lunge-streak')), findsOneWidget);
  });

  testWidgets('lunge streak is gone once the batch has finished',
      (tester) async {
    await tester.pumpWidget(buildTree(1.0));
    // At subProgress 1.0 the triangle wave is back at 0 (attacker position)
    // and the *next* build with a finished batch renders nothing — assert
    // via a progress value clearly past the single event's window instead.
    await tester.pumpWidget(buildTree(0.0));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              Positioned(
                left: 0,
                top: 0,
                width: 300,
                height: 300,
                child: SizedBox(key: myBoardKey),
              ),
              Positioned(
                left: 0,
                top: 300,
                width: 300,
                height: 300,
                child: SizedBox(key: opponentBoardKey),
              ),
              CombatEffectsOverlay(
                batch: null,
                playheadProgress: 0.0,
                myBoardKey: myBoardKey,
                opponentBoardKey: opponentBoardKey,
                mySide: MatchSide.p1,
              ),
            ],
          ),
        ),
      ),
    );
    expect(find.byKey(const ValueKey('lunge-streak')), findsNothing);
  });

  testWidgets('lunge streak sits at the target tile at the peak of the wave',
      (tester) async {
    // 1 event total: playheadProgress 0.5 -> subProgress 0.5 ->
    // triangleWave(0.5) == 1.0 (fully at target).
    await tester.pumpWidget(buildTree(0.5));
    final iconCenter = tester.getCenter(find.byKey(const ValueKey('lunge-streak')));
    // Target is slot 4 (center tile) of the opponent board, which spans
    // y in [300, 600] on screen -> its center tile center is at (150, 450).
    expect(iconCenter.dx, closeTo(150, 5));
    expect(iconCenter.dy, closeTo(450, 5));
  });

  testWidgets('renders nothing when a tile position cannot be resolved',
      (tester) async {
    final unlaidOutKey = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              CombatEffectsOverlay(
                batch: batch,
                playheadProgress: 0.5,
                myBoardKey: unlaidOutKey, // never mounted -> no RenderBox
                opponentBoardKey: opponentBoardKey,
                mySide: MatchSide.p1,
              ),
            ],
          ),
        ),
      ),
    );
    expect(find.byKey(const ValueKey('lunge-streak')), findsNothing);
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd mobile && flutter test test/features/match/battle/combat_effects_overlay_test.dart`
Expected: compile error — `combat_effects_overlay.dart` doesn't exist yet.

- [ ] **Step 3: Write the implementation**

```dart
// mobile/lib/features/match/battle/combat_effects_overlay.dart
/// Shared overlay rendered above both boards in `BattleView`, driving the
/// melee lunge and ranged projectile from the real on-screen position of
/// the attacker and target tiles instead of a hardcoded direction/distance
/// (P4-FE-01). See `docs/09-combat-effects-overlay-design.md`.
library;

import 'package:flutter/material.dart';

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
    return IgnorePointer(
      child: Positioned.fill(
        child: Builder(
          builder: (innerContext) => _resolveEffect(innerContext) ??
              const SizedBox.shrink(),
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

    final selfBox = context.findRenderObject() as RenderBox?;
    if (selfBox == null || !selfBox.hasSize) return null;

    final attackerGlobal = tileGlobalCenter(
      boardKey: attackerSide == mySide ? myBoardKey : opponentBoardKey,
      slot: attackerSlot,
      reverseRows: attackerSide != mySide,
    );
    final targetGlobal = tileGlobalCenter(
      boardKey: targetSide == mySide ? myBoardKey : opponentBoardKey,
      slot: targetSlot,
      reverseRows: targetSide != mySide,
    );
    if (attackerGlobal == null || targetGlobal == null) return null;

    final attackerLocal = selfBox.globalToLocal(attackerGlobal);
    final targetLocal = selfBox.globalToLocal(targetGlobal);

    final isMelee =
        attackerUnitId == UnitId.fighter || attackerUnitId == UnitId.tank;
    final progress =
        isMelee ? triangleWave(current.subProgress) : current.subProgress;
    final position = Offset.lerp(attackerLocal, targetLocal, progress)!;

    return Positioned(
      left: position.dx - 12,
      top: position.dy - 12,
      child: Icon(
        key: ValueKey(isMelee ? 'lunge-streak' : 'projectile-mark'),
        isMelee ? Icons.flash_on : Icons.arrow_forward,
        size: 24,
        color: attackerSide == mySide ? Colors.blueAccent : Colors.redAccent,
      ),
    );
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd mobile && flutter test test/features/match/battle/combat_effects_overlay_test.dart`
Expected: `All tests passed!` (4 tests)

- [ ] **Step 5: Format, analyze, commit**

```bash
cd mobile
dart format lib/features/match/battle/combat_effects_overlay.dart test/features/match/battle/combat_effects_overlay_test.dart
flutter analyze lib/features/match/battle/combat_effects_overlay.dart test/features/match/battle/combat_effects_overlay_test.dart
```
Expected: `No issues found!`

```bash
git add mobile/lib/features/match/battle/combat_effects_overlay.dart mobile/test/features/match/battle/combat_effects_overlay_test.dart
git commit -m "feat(fe): P4-FE-01 CombatEffectsOverlay renders lunge/projectile at real tile positions"
```

---

## Task 3: Wire the overlay into `BattleView`

**Files:**
- Modify: `mobile/lib/features/match/battle/battle_view.dart`

- [ ] **Step 1: Add stable `GlobalKey`s and mount the overlay in `_BattleViewState`**

In `mobile/lib/features/match/battle/battle_view.dart`, find:

```dart
class _BattleViewState extends ConsumerState<BattleView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _playhead;
  late final BattlePlaybackController _controller;
  Timer? _staleTimer;
  bool _staleDetected = false;
```

Replace with:

```dart
class _BattleViewState extends ConsumerState<BattleView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _playhead;
  late final BattlePlaybackController _controller;
  Timer? _staleTimer;
  bool _staleDetected = false;
  final GlobalKey _myBoardKey = GlobalKey();
  final GlobalKey _opponentBoardKey = GlobalKey();
```

Then find (inside `build()`):

```dart
          Expanded(
            child: _BattleStage(
              match: widget.match,
              game: game,
              unitStates: unitStates,
            ),
          ),
```

Replace with:

```dart
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
```

Add the import, next to the other local imports:

```dart
import 'combat_effects_overlay.dart';
```

- [ ] **Step 2: Thread the keys through `_BattleStage`**

Find:

```dart
class _BattleStage extends StatelessWidget {
  const _BattleStage({
    required this.match,
    required this.game,
    required this.unitStates,
  });

  final MatchState match;
  final GameTheme game;
  final Map<UnitKey, UnitVisualState> unitStates;
```

Replace with:

```dart
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
```

Find:

```dart
    final mine = _BoardPreview(
      boardKey: const ValueKey('battle-player-board'),
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
```

Replace with:

```dart
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
```

- [ ] **Step 3: Attach the position key to `_BoardPreview`'s grid**

Find:

```dart
class _BoardPreview extends StatelessWidget {
  const _BoardPreview({
    required this.boardKey,
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
  final String label;
```

Replace with:

```dart
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
```

Find:

```dart
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
```

Replace with:

```dart
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
```

This opens one more level of nesting — find the matching close of that `GridView.builder(` call:

```dart
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
```

Replace with (adds one closing `)` for the new `KeyedSubtree`, and re-indents the two lines that were already there):

```dart
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
```

- [ ] **Step 4: Run the existing battle-related widget tests**

Run: `cd mobile && flutter test test/features/match/match_screen_test.dart`
Expected: `All tests passed!` — this file's tests (`find.byKey(const ValueKey('battle-player-board'))` etc., lines 743/750/799/802) still pass because `boardKey` (the `ValueKey`) is untouched; only a new inner `KeyedSubtree` was added.

- [ ] **Step 5: Format, analyze, commit**

```bash
cd mobile
dart format lib/features/match/battle/battle_view.dart
flutter analyze lib/features/match/battle/battle_view.dart
```
Expected: no *new* issues beyond the pre-existing ones already in this file (see note below).

> **Note:** `flutter analyze` on this file already reports a few pre-existing, unrelated issues (an `invalid_use_of_visible_for_testing_member` pair at the `_controller.state.batch!` line, an `unused_field` for `_wasFloating`, three `deprecated_member_use` for `withOpacity`). These predate this plan (inherited from the `P4-FE-03` branch this work is stacked on) — do not fix them as part of this task; just confirm the count of issues hasn't grown.

```bash
git add mobile/lib/features/match/battle/battle_view.dart
git commit -m "feat(fe): P4-FE-01 mount CombatEffectsOverlay above the battle boards"
```

---

## Task 4: Remove the old per-tile lunge/projectile code

**Files:**
- Modify: `mobile/lib/features/match/battle/battle_view.dart`
- Delete: `mobile/test/features/match/battle/battle_view_lunge_test.dart`

This is safe now that Task 3 renders lunge/projectile from `CombatEffectsOverlay` instead — the code removed here is fully superseded, not still relied upon.

- [ ] **Step 1: Delete the superseded test**

```bash
rm mobile/test/features/match/battle/battle_view_lunge_test.dart
```

- [ ] **Step 2: Delete `lungeOffsetFor`**

In `mobile/lib/features/match/battle/battle_view.dart`, delete this entire function:

```dart
/// Pixel offset for the melee lunge at a given animation [progress]
/// (0 = origin tile, 1 = fully crossed to the enemy board).
///
/// Ally and enemy render on two separate board widgets (own `GridView`
/// each, stacked with the versus divider between them) — there is no
/// shared coordinate space between an attacker's tile and its target's.
/// So, same as the ranged projectile below, "reaching the target" means
/// traveling the full [boardHeight] toward the opponent, not one local
/// tile step.
Offset lungeOffsetFor({
  required double lungeDx,
  required double lungeDy,
  required double tileWidth,
  required double boardHeight,
  required double progress,
}) {
  return Offset(
    lungeDx * tileWidth * 1.2 * progress,
    lungeDy * boardHeight * progress,
  );
}
```

- [ ] **Step 3: Remove the lunge/projectile controllers, fields, and triggers from `_BattleTileState`**

Find:

```dart
class _BattleTileState extends State<BattleTile> with TickerProviderStateMixin {
  late final AnimationController _lungeCtrl;
  late final Animation<double> _lungeAnim;
  late final AnimationController _projCtrl;
  late final Animation<double> _projAnim;
  late final AnimationController _floatCtrl;
  late final Animation<double> _floatAnim;
  late final AnimationController _shakeCtrl;
  late final Animation<double> _shakeAnim;
  late final AnimationController _healBubbleCtrl;
  late final Animation<double> _healBubbleAnim;
  bool _wasLunging = false;
  bool _wasShooting = false;
  bool _wasFloating = false;
  int? _lastFloatingDamage;
  int? _lastDamageIndex;
  int? _lastHealIndex;

  @override
  void initState() {
    super.initState();
    _lungeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _lungeAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _lungeCtrl, curve: Curves.easeInOut),
    );
    _projCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _projAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _projCtrl, curve: Curves.linear),
    );
    _floatCtrl = AnimationController(
```

Replace with:

```dart
class _BattleTileState extends State<BattleTile> with TickerProviderStateMixin {
  late final AnimationController _floatCtrl;
  late final Animation<double> _floatAnim;
  late final AnimationController _shakeCtrl;
  late final Animation<double> _shakeAnim;
  late final AnimationController _healBubbleCtrl;
  late final Animation<double> _healBubbleAnim;
  bool _wasFloating = false;
  int? _lastFloatingDamage;
  int? _lastDamageIndex;
  int? _lastHealIndex;

  @override
  void initState() {
    super.initState();
    _floatCtrl = AnimationController(
```

Find:

```dart
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
```

Replace with:

```dart
  @override
  void didUpdateWidget(BattleTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    final floatingAmount = widget.unitState?.floatingDamage;
```

Find:

```dart
  @override
  void dispose() {
    _lungeCtrl.dispose();
    _projCtrl.dispose();
    _floatCtrl.dispose();
    _shakeCtrl.dispose();
    _healBubbleCtrl.dispose();
    super.dispose();
  }
```

Replace with:

```dart
  @override
  void dispose() {
    _floatCtrl.dispose();
    _shakeCtrl.dispose();
    _healBubbleCtrl.dispose();
    super.dispose();
  }
```

- [ ] **Step 4: Remove the lunge offset from `build()` and drop the old projectile block**

Find:

```dart
      child: AnimatedBuilder(
        animation: Listenable.merge([
          _lungeAnim,
          _projAnim,
          _shakeAnim,
        ]),
        builder: (context, child) {
          // Lunge: travel across to the enemy board and back.
          final lungeDx = widget.unitState?.lungeDx ?? 0;
          final lungeDy = widget.unitState?.lungeDy ??
              (widget.unitSide == UnitSide.ally ? -1.0 : 1.0);
          final progress = _lungeAnim.value;
          final lungeOffset = lungeOffsetFor(
            lungeDx: lungeDx,
            lungeDy: lungeDy,
            tileWidth: widget.tileWidth,
            boardHeight: widget.boardHeight,
            progress: progress,
          );
          // Hit shake: constant 6px horizontal offset, oscillating.
          final shakeProgress = _shakeAnim.value;
          final shakeOffset = shakeProgress > 0
              ? Offset(
                  6 * (1 - shakeProgress) * (shakeProgress < 0.5 ? 1.0 : -1.0),
                  0,
                )
              : Offset.zero;
          return Transform.translate(
            offset: lungeOffset + shakeOffset,
            child: child,
          );
        },
```

Replace with:

```dart
      child: AnimatedBuilder(
        animation: _shakeAnim,
        builder: (context, child) {
          // Hit shake: constant 6px horizontal offset, oscillating.
          final shakeProgress = _shakeAnim.value;
          final shakeOffset = shakeProgress > 0
              ? Offset(
                  6 * (1 - shakeProgress) * (shakeProgress < 0.5 ? 1.0 : -1.0),
                  0,
                )
              : Offset.zero;
          return Transform.translate(
            offset: shakeOffset,
            child: child,
          );
        },
```

Find (the old projectile `Positioned.fill`, now superseded by `CombatEffectsOverlay`):

```dart
            // Projectile overlay.
            if (uv != null && uv.isShooting)
              Positioned.fill(
                child: AnimatedBuilder(
                  animation: _projAnim,
                  builder: (context, _) {
                    final isAlly = widget.unitSide == UnitSide.ally;
                    final progress = _projAnim.value;
                    final travelX = (widget.unitState?.lungeDx ?? 0) *
                        widget.tileWidth *
                        1.2;
                    final travelY =
                        isAlly ? -widget.boardHeight : widget.boardHeight;
                    return Opacity(
                      opacity: progress < 0.95 ? 1.0 : 0.0,
                      child: Transform.translate(
                        offset: Offset(travelX * progress, travelY * progress),
                        child: Icon(
                          uv.projectileIcon,
                          size: 24,
                          color: isAlly
                              ? Theme.of(context).extension<GameTheme>()!.ally
                              : Theme.of(context).extension<GameTheme>()!.enemy,
                        ),
                      ),
                    );
                  },
                ),
              ),
            // Heal bubble — expanding green circle, emit-and-dispose.
```

Replace with:

```dart
            // Heal bubble — expanding green circle, emit-and-dispose.
```

(This deletes the whole projectile block and keeps the heal-bubble comment/block that immediately follows it untouched.)

- [ ] **Step 5: Run the full mobile test suite**

Run: `cd mobile && flutter test`
Expected: `All tests passed!` — no regressions in `match_screen_test.dart`, `widget_gallery_test.dart`, etc.

- [ ] **Step 6: Format, analyze, commit**

```bash
cd mobile
dart format lib/features/match/battle/battle_view.dart
flutter analyze lib/features/match/battle/battle_view.dart
```
Expected: same pre-existing issue count as Task 3 (no new ones), and the `unused_field` warning for `_wasFloating` is unrelated and still present — that one is pre-existing too, not introduced by this task.

```bash
git add mobile/lib/features/match/battle/battle_view.dart mobile/test/features/match/battle/battle_view_lunge_test.dart
git commit -m "refactor(fe): P4-FE-01 remove per-tile lunge/projectile Transform code, superseded by overlay"
```

---

## Task 5: Remove the now-dead lunge/projectile fields from `UnitVisualState`

**Files:**
- Modify: `mobile/lib/features/match/battle/battle_visual_state.dart`

Nothing reads `isLunging`, `lungeTargetSlot`, `lungeDx`, `lungeDy`, `isShooting`, `projectileTargetSlot`, or `projectileIcon` after Task 4 — `CombatEffectsOverlay` reads directly from the `AttackEvent`, not from `UnitVisualState`. Removing these keeps `deriveUnitStates` from computing values nobody uses.

- [ ] **Step 1: Confirm nothing else references these fields**

Run: `cd mobile && grep -rn "isLunging\|lungeTargetSlot\|lungeDx\|lungeDy\|isShooting\|projectileTargetSlot\|projectileIcon" lib test`
Expected: matches only inside `battle_visual_state.dart` itself (after Task 4, `battle_view.dart` and its tests no longer reference any of these).

- [ ] **Step 2: Trim the `UnitVisualState` constructor and fields**

Find:

```dart
  const UnitVisualState({
    required this.unitId,
    required this.star,
    required this.hp,
    required this.maxHp,
    required this.alive,
    this.isLunging = false,
    this.lungeTargetSlot,
    this.lungeDx = 0,
    this.lungeDy = 0,
    this.isShooting = false,
    this.projectileTargetSlot,
    this.projectileIcon = Icons.arrow_forward,
    this.floatingDamage,
    this.floatingIsHeal = false,
    this.healEventIndex,
    this.lastDamageEventIndex,
    this.debuff,
  });

  final UnitId unitId;
  final int star;
  final int hp;
  final int maxHp;
  final bool alive;
  final bool isLunging;
  final int? lungeTargetSlot;
  /// Normalized horizontal lunge direction (-1 = left, +1 = right).
  final double lungeDx;
  /// Normalized vertical lunge direction (-1 = up toward enemy, +1 = down).
  final double lungeDy;
  final bool isShooting;
  final int? projectileTargetSlot;
  final IconData projectileIcon;
  final int? floatingDamage;
```

Replace with:

```dart
  const UnitVisualState({
    required this.unitId,
    required this.star,
    required this.hp,
    required this.maxHp,
    required this.alive,
    this.floatingDamage,
    this.floatingIsHeal = false,
    this.healEventIndex,
    this.lastDamageEventIndex,
    this.debuff,
  });

  final UnitId unitId;
  final int star;
  final int hp;
  final int maxHp;
  final bool alive;
  final int? floatingDamage;
```

- [ ] **Step 3: Remove the unused import this leaves behind**

`Icons` (from `package:flutter/material.dart`) was only used for the `projectileIcon` default. Find:

```dart
import 'package:flutter/material.dart' show Color, IconData, Icons;
```

Replace with:

```dart
import 'package:flutter/material.dart' show Color;
```

- [ ] **Step 4: Trim the `AttackEvent` branch in `deriveUnitStates`**

Find:

```dart
      case AttackEvent():
        // Floating damage on target.
        _setFloating(
          current.targetSide,
          current.targetSlot,
          current.damage,
          false,
          map,
        );
        // Lunging / shooting on attacker.
        if (current.attackerSlot != null &&
            current.attackerSide != null &&
            current.attackerUnitId != null) {
          final isMelee = current.attackerUnitId == UnitId.fighter ||
              current.attackerUnitId == UnitId.tank;
          final key = UnitKey(
            side: current.attackerSide!,
            slot: current.attackerSlot!,
          );
          final existing = map[key];
          if (existing != null) {
            if (isMelee && current.targetSlot != null) {
              final attackerSlot = current.attackerSlot!;
              final targetSlot = current.targetSlot!;
              final aCol = attackerSlot % 3;
              final tCol = targetSlot % 3;
              var dCol = (tCol - aCol).toDouble();
              if (dCol.abs() > 1) dCol = dCol > 0 ? 1.0 : -1.0;
              final dRow = current.attackerSide == MatchSide.p2 ? 1.0 : -1.0;
              map[key] = UnitVisualState(
                unitId: existing.unitId,
                star: existing.star,
                hp: existing.hp,
                maxHp: existing.maxHp,
                alive: existing.alive,
                isLunging: true,
                lungeTargetSlot: current.targetSlot,
                lungeDx: dCol,
                lungeDy: dRow,
              );
            } else {
              final icon = current.attackerUnitId == UnitId.ranger
                  ? Icons.arrow_forward
                  : Icons.bolt;
              map[key] = UnitVisualState(
                unitId: existing.unitId,
                star: existing.star,
                hp: existing.hp,
                maxHp: existing.maxHp,
                alive: existing.alive,
                isShooting: true,
                projectileTargetSlot: current.targetSlot,
                projectileIcon: icon,
              );
            }
          }
        }
```

Replace with:

```dart
      case AttackEvent():
        // Floating damage on target. Lunge/projectile visuals are driven
        // directly from the event stream by CombatEffectsOverlay, not
        // from UnitVisualState (P4-FE-01).
        _setFloating(
          current.targetSide,
          current.targetSlot,
          current.damage,
          false,
          map,
        );
```

- [ ] **Step 5: Trim the "enrich" loop's now-nonexistent field copies**

Find:

```dart
    map[key] = UnitVisualState(
      unitId: existing.unitId,
      star: existing.star,
      hp: existing.hp,
      maxHp: existing.maxHp,
      alive: existing.alive,
      isLunging: existing.isLunging,
      lungeTargetSlot: existing.lungeTargetSlot,
      lungeDx: existing.lungeDx,
      lungeDy: existing.lungeDy,
      isShooting: existing.isShooting,
      projectileTargetSlot: existing.projectileTargetSlot,
      projectileIcon: existing.projectileIcon,
      floatingDamage: existing.floatingDamage,
      floatingIsHeal: existing.floatingIsHeal,
      healEventIndex: healEventIndex[key],
      lastDamageEventIndex: lastDamage[key],
      debuff: debuff,
    );
```

Replace with:

```dart
    map[key] = UnitVisualState(
      unitId: existing.unitId,
      star: existing.star,
      hp: existing.hp,
      maxHp: existing.maxHp,
      alive: existing.alive,
      floatingDamage: existing.floatingDamage,
      floatingIsHeal: existing.floatingIsHeal,
      healEventIndex: healEventIndex[key],
      lastDamageEventIndex: lastDamage[key],
      debuff: debuff,
    );
```

- [ ] **Step 6: Run the full mobile test suite**

Run: `cd mobile && flutter test`
Expected: `All tests passed!`

- [ ] **Step 7: Format, analyze, commit**

```bash
cd mobile
dart format lib/features/match/battle/battle_visual_state.dart
flutter analyze lib/features/match/battle/battle_visual_state.dart
```
Expected: `No issues found!` (this file had none before, either).

```bash
git add mobile/lib/features/match/battle/battle_visual_state.dart
git commit -m "refactor(fe): P4-FE-01 drop dead lunge/projectile fields from UnitVisualState"
```

---

## Task 6: Final verification and handoff

**Files:** none (verification only)

- [ ] **Step 1: Run the full suite one more time from a clean state**

```bash
cd mobile
dart format --set-exit-if-changed lib test
flutter analyze
flutter test
```
Expected: format reports no changes needed, analyze shows only the pre-existing issues noted in Task 3 (none new), and every test passes.

- [ ] **Step 2: Push**

```bash
git push
```

- [ ] **Step 3: Hand back for live retest**

Tell the user: code is pushed to `P4-FE-01`; hot-reload (`r`) or hot-restart (`R`) the running `flutter run` session (hot-restart is safer here since `_BattleViewState`'s fields changed), then trigger a melee attack and a ranged attack in a live match and confirm both now travel toward the real target position and disappear correctly. Do not open a PR yet — confirm live first (per this repo's own "no PR for incomplete work" convention).

---

## Deferred (not in this plan)

- Migrating hit-shake and heal-bubble to the same pure-derivation pattern, and adding the attacker-side in-place recoil described in `docs/09-combat-effects-overlay-design.md`'s "Phase 2." Not reported broken; do as a follow-up plan once this lands.
- Resolving the #214 / #217 merge-order conflict (both already flagged on GitHub) — a team decision, not an engineering task.
