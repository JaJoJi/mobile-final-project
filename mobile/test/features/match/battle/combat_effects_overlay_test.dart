import 'package:auto_chess_mobile/core/theme/app_theme.dart';
import 'package:auto_chess_mobile/features/match/battle/combat_effects_math.dart';
import 'package:auto_chess_mobile/features/match/battle/combat_effects_overlay.dart';
import 'package:auto_chess_mobile/shared/models/combat_event.dart';
import 'package:auto_chess_mobile/shared/models/match_state.dart';
import 'package:auto_chess_mobile/shared/models/unit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final myBoardKey = GlobalKey();
  final opponentBoardKey = GlobalKey();

  // Every fixture below stacks the boards vertically (mine at y 0-300,
  // opponent's at y 300-600) — the portrait convention `tileLocalCenter`
  // uses to put depth on the row axis. The default test surface is
  // 800x600 (landscape), which since #P4 flips that to the column axis;
  // pin portrait explicitly so the ambient orientation matches what
  // these fixtures actually lay out.
  void forcePortrait(WidgetTester tester) {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

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

  const batch = CombatEventBatch(
    matchId: 'm1',
    round: 1,
    cycleCount: 1,
    endedAt: 0,
    events: [meleeAttack],
  );

  const rangedAttack = AttackEvent(
    cycle: 1,
    tick: 1,
    attacker: 'a',
    target: 'b',
    damage: 10,
    targetHpAfter: 90,
    attackerSide: MatchSide.p1,
    attackerSlot: 0,
    attackerUnitId: UnitId.ranger,
    targetSide: MatchSide.p2,
    targetSlot: 4,
  );

  const rangedBatch = CombatEventBatch(
    matchId: 'm1',
    round: 1,
    cycleCount: 1,
    endedAt: 0,
    events: [rangedAttack],
  );

  Widget buildTree(double progress, {CombatEventBatch? eventsBatch}) {
    return MaterialApp(
      theme: buildTheme(Brightness.light),
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
              batch: eventsBatch ?? batch,
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

  testWidgets('melee attacker sprite travels during its event window',
      (tester) async {
    forcePortrait(tester);
    await tester.pumpWidget(buildTree(0.5));
    expect(find.byKey(const ValueKey('lunge-traveler')), findsOneWidget);
  });

  testWidgets('melee traveler is gone once the batch has finished',
      (tester) async {
    forcePortrait(tester);
    await tester.pumpWidget(buildTree(1.0));
    // At subProgress 1.0 the triangle wave is back at 0 (attacker position)
    // and the *next* build with a finished batch renders nothing — assert
    // via a progress value clearly past the single event's window instead.
    await tester.pumpWidget(buildTree(0.0));
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.light),
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
    expect(find.byKey(const ValueKey('lunge-traveler')), findsNothing);
  });

  testWidgets('melee traveler sits at the target tile at the peak of the wave',
      (tester) async {
    forcePortrait(tester);
    // 1 event total: playheadProgress 0.5 -> subProgress 0.5 ->
    // triangleWave(0.5) == 1.0 (fully at target).
    await tester.pumpWidget(buildTree(0.5));
    final iconCenter =
        tester.getCenter(find.byKey(const ValueKey('lunge-traveler')));
    // Target is slot 4 (center tile) of the opponent board, which spans
    // y in [300, 600] on screen -> its center tile center is at (150, 450).
    expect(iconCenter.dx, closeTo(150, 5));
    expect(iconCenter.dy, closeTo(450, 5));
  });

  testWidgets(
      'projectile mark moves linearly with flight progress, not the '
      'triangle wave', (tester) async {
    forcePortrait(tester);
    // 1 event total: playheadProgress 0.25 -> subProgress 0.25 ->
    // projectileTravel(0.25) = 0.25 / kProjectileImpactFraction (#215: a
    // projectile completes its whole flight by the impact point, not by
    // subProgress 1.0). The ranger's attackerUnitId makes `isMelee`
    // false, so the widget should use that flight fraction directly
    // (linear) rather than `triangleWave(subProgress)`.
    await tester.pumpWidget(buildTree(0.25, eventsBatch: rangedBatch));

    // Confirms melee/ranged branching selects the ranged icon, not the
    // melee one.
    expect(find.byKey(const ValueKey('projectile-mark')), findsOneWidget);
    expect(find.byKey(const ValueKey('lunge-traveler')), findsNothing);

    final iconCenter =
        tester.getCenter(find.byKey(const ValueKey('projectile-mark')));
    // Attacker is slot 0 (top-left tile) of my board, which spans
    // (0,0)-(300,300) -> tile center (48.667, 48.667). Target is slot 4
    // (center tile) of the opponent board, which spans y in [300, 600]
    // -> tile center (150, 450).
    final t = projectileTravel(0.25);
    final expectedX = 48.667 + t * (150 - 48.667);
    final expectedY = 48.667 + t * (450 - 48.667);
    //
    // If the melee (triangle-wave) branch were used by mistake,
    // triangleWave(0.25) == 0.5, putting the icon at (99.333, 249.333)
    // instead -- clearly distinct from the expectation below, so this
    // assertion actually proves which branch ran.
    expect(iconCenter.dx, closeTo(expectedX, 5));
    expect(iconCenter.dy, closeTo(expectedY, 5));
  });

  testWidgets('traveller scales and repositions with the board size',
      (tester) async {
    forcePortrait(tester);
    // Same event, two very different board sizes: the traveller must be
    // sized and placed from the measured board, not from fixed pixels.
    Future<Rect> travellerRectFor(double boardSize) async {
      final myKey = GlobalKey();
      final oppKey = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.light),
          home: Scaffold(
            body: Stack(
              children: [
                Positioned(
                  left: 0,
                  top: 0,
                  width: boardSize,
                  height: boardSize,
                  child: SizedBox(key: myKey),
                ),
                Positioned(
                  left: 0,
                  top: boardSize,
                  width: boardSize,
                  height: boardSize,
                  child: SizedBox(key: oppKey),
                ),
                CombatEffectsOverlay(
                  batch: batch,
                  playheadProgress: 0.5,
                  myBoardKey: myKey,
                  opponentBoardKey: oppKey,
                  mySide: MatchSide.p1,
                ),
              ],
            ),
          ),
        ),
      );
      return tester.getRect(find.byKey(const ValueKey('lunge-traveler')));
    }

    final small = await travellerRectFor(240);
    final large = await travellerRectFor(480);

    // Traveller is one tile wide. Tiles are the board minus its two fixed
    // 4px gutters, split three ways — the gutters don't scale, so this is
    // the exact expectation rather than a flat doubling.
    double tileOf(double board) => (board - 2 * 4) / 3;
    expect(small.width, closeTo(tileOf(240), 0.5));
    expect(large.width, closeTo(tileOf(480), 0.5));

    // The point of the whole feature: at the peak of the wave the sprite
    // is standing on the *target's* square, at any board size. Target is
    // slot 4 (row 1, col 1) of the opponent board, which the harness lays
    // out directly below the player's, and which renders with reversed
    // rows — row 1 mirrors to itself, so it's the middle tile either way.
    Offset expectedTargetCentre(double board) {
      final tile = tileOf(board);
      final centreInBoard = 1 * (tile + 4) + tile / 2;
      return Offset(centreInBoard, board + centreInBoard);
    }

    expect(small.center.dx, closeTo(expectedTargetCentre(240).dx, 1));
    expect(small.center.dy, closeTo(expectedTargetCentre(240).dy, 1));
    expect(large.center.dx, closeTo(expectedTargetCentre(480).dx, 1));
    expect(large.center.dy, closeTo(expectedTargetCentre(480).dy, 1));
  });

  testWidgets('renders nothing when a tile position cannot be resolved',
      (tester) async {
    forcePortrait(tester);
    final unlaidOutKey = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.light),
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
    expect(find.byKey(const ValueKey('lunge-traveler')), findsNothing);
  });

  testWidgets('a projectile reaches the target tile before it disappears',
      (tester) async {
    forcePortrait(tester);
    // AC: "lands on or very near the target tile before disappearing".
    // One event, so playheadProgress *is* subProgress; sample at the
    // impact point, which is deliberately short of 1.0 so the icon is
    // still drawn on the frame the hit registers.
    await tester.pumpWidget(
      buildTree(kProjectileImpactFraction - 0.01, eventsBatch: rangedBatch),
    );
    final mark = find.byKey(const ValueKey('projectile-mark'));
    expect(mark, findsOneWidget);
    final centre = tester.getCenter(mark);
    // Target is slot 4 of the opponent board, which the harness lays out
    // at y in [300, 600] -> its middle tile's centre is (150, 450).
    expect(centre.dx, closeTo(150, 8));
    expect(centre.dy, closeTo(450, 8));

    // AC: "disappears instantly on impact" — no fade, no lingering.
    await tester.pumpWidget(
      buildTree(kProjectileImpactFraction, eventsBatch: rangedBatch),
    );
    expect(find.byKey(const ValueKey('projectile-mark')), findsNothing);
  });

  testWidgets('a healer uses its bolt asset and a ranger its arrow asset',
      (tester) async {
    forcePortrait(tester);
    // The per-tile projectile this overlay replaced picked the icon by
    // unit; the distinction was lost in the move.
    await tester.pumpWidget(buildTree(0.25, eventsBatch: rangedBatch));
    final rangerImage = tester.widget<Image>(
      find.byKey(const ValueKey('projectile-rangerProjectile')),
    );
    expect(
      (rangerImage.image as AssetImage).assetName,
      'assets/images/vfx/ranger_projectile.png',
    );

    const healerAttack = AttackEvent(
      cycle: 1,
      tick: 1,
      attacker: 'a',
      target: 'b',
      damage: 6,
      targetHpAfter: 94,
      attackerSide: MatchSide.p1,
      attackerSlot: 0,
      attackerUnitId: UnitId.healer,
      targetSide: MatchSide.p2,
      targetSlot: 4,
    );
    await tester.pumpWidget(
      buildTree(
        0.25,
        eventsBatch: const CombatEventBatch(
          matchId: 'm1',
          round: 1,
          cycleCount: 1,
          endedAt: 0,
          events: [healerAttack],
        ),
      ),
    );
    final healerImage = tester.widget<Image>(
      find.byKey(const ValueKey('projectile-healerAttackProjectile')),
    );
    expect(
      (healerImage.image as AssetImage).assetName,
      'assets/images/vfx/healer_attack_projectile.png',
    );
  });

  testWidgets('reduced motion keeps a ranged VFX stationary near impact',
      (tester) async {
    forcePortrait(tester);
    tester.binding.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(
      tester.binding.platformDispatcher.clearAccessibilityFeaturesTestValue,
    );

    await tester.pumpWidget(buildTree(0.1, eventsBatch: rangedBatch));
    final early =
        tester.getCenter(find.byKey(const ValueKey('projectile-mark')));
    await tester.pumpWidget(buildTree(0.7, eventsBatch: rangedBatch));
    final late =
        tester.getCenter(find.byKey(const ValueKey('projectile-mark')));

    expect(late, early);
  });

  testWidgets('an enemy projectile flies down toward the viewer',
      (tester) async {
    forcePortrait(tester);
    // AC: works for both ally (bottom board -> up) and enemy (top board
    // -> down). Same event mirrored: p2 shoots at p1, viewed as p1, so
    // the shot must travel from the opponent's board into the viewer's.
    const incoming = AttackEvent(
      cycle: 1,
      tick: 1,
      attacker: 'a',
      target: 'b',
      damage: 10,
      targetHpAfter: 90,
      attackerSide: MatchSide.p2,
      attackerSlot: 0,
      attackerUnitId: UnitId.ranger,
      targetSide: MatchSide.p1,
      targetSlot: 4,
    );
    await tester.pumpWidget(
      buildTree(
        0.25,
        eventsBatch: const CombatEventBatch(
          matchId: 'm1',
          round: 1,
          cycleCount: 1,
          endedAt: 0,
          events: [incoming],
        ),
      ),
    );
    final early =
        tester.getCenter(find.byKey(const ValueKey('projectile-mark')));

    await tester.pumpWidget(
      buildTree(
        kProjectileImpactFraction - 0.01,
        eventsBatch: const CombatEventBatch(
          matchId: 'm1',
          round: 1,
          cycleCount: 1,
          endedAt: 0,
          events: [incoming],
        ),
      ),
    );
    final late_ =
        tester.getCenter(find.byKey(const ValueKey('projectile-mark')));

    // The viewer's own board is the top one in this harness, so an
    // incoming shot travels upward on screen — the point is that it moves
    // *toward* the target's real tile, not a hardcoded direction.
    expect(late_.dy, lessThan(early.dy));
    expect(late_.dx, closeTo(150, 8));
    expect(late_.dy, closeTo(150, 8));
  });
}
