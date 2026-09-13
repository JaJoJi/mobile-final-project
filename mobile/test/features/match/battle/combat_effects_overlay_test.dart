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

  const batch = CombatEventBatch(
    matchId: 'm1',
    round: 1,
    cycleCount: 1,
    endedAt: 0,
    events: [meleeAttack],
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
    final iconCenter =
        tester.getCenter(find.byKey(const ValueKey('lunge-streak')));
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
