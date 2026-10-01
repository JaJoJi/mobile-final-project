import 'package:auto_chess_mobile/core/widgets/unit_avatar.dart';
import 'package:auto_chess_mobile/features/match/battle/battle_view.dart';
import 'package:auto_chess_mobile/features/match/battle/battle_visual_state.dart';
import 'package:auto_chess_mobile/features/match/board/stone_board_tile.dart';
import 'package:auto_chess_mobile/shared/models/unit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../widgets/_harness.dart';

void main() {
  for (final side in UnitSide.values) {
    testWidgets('death replaces $side unit and ring with opaque broken stone',
        (tester) async {
      for (final alive in [true, false, true]) {
        await pumpThemed(
          tester,
          SizedBox.square(
            dimension: 100,
            child: BattleTile(
              slot: 0,
              unitSide: side,
              unitState: UnitVisualState(
                unitId: UnitId.ranger,
                star: 2,
                hp: alive ? 100 : 0,
                maxHp: 100,
                alive: alive,
              ),
            ),
          ),
        );
        final tile = tester.widget<StoneBoardTile>(find.byType(StoneBoardTile));
        expect(tile.broken, !alive);
        expect(tile.unitSide, alive ? side : isNull);
        expect(find.byType(UnitAvatar), alive ? findsOneWidget : findsNothing);
        final assets = tester
            .widgetList<Image>(find.byType(Image))
            .map((image) => (image.image as AssetImage).assetName);
        expect(assets.contains(StoneBoardTile.brokenAssetPath), !alive);
        if (!alive) {
          expect(assets.contains(StoneBoardTile.allyBaseAssetPath), isFalse);
          expect(assets.contains(StoneBoardTile.enemyBaseAssetPath), isFalse);
        }
        expect(
          tester
              .widget<AnimatedOpacity>(find.byType(AnimatedOpacity).first)
              .opacity,
          1,
        );
      }
    });
  }
  testWidgets('empty slots remain intact and faded', (tester) async {
    await pumpThemed(
      tester,
      const SizedBox.square(
        dimension: 100,
        child: BattleTile(slot: 0, unitSide: null),
      ),
    );
    expect(
      tester.widget<StoneBoardTile>(find.byType(StoneBoardTile)).broken,
      isFalse,
    );
    expect(
      tester
          .widget<AnimatedOpacity>(find.byType(AnimatedOpacity).first)
          .opacity,
      0.3,
    );
  });

  testWidgets('unit stars sit below the health bar in a readable badge',
      (tester) async {
    await pumpThemed(
      tester,
      const SizedBox.square(
        dimension: 100,
        child: BattleTile(
          slot: 0,
          unitSide: UnitSide.ally,
          unitState: UnitVisualState(
            unitId: UnitId.tank,
            star: 2,
            hp: 75,
            maxHp: 100,
            alive: true,
          ),
        ),
      ),
    );

    final health = find.byKey(const ValueKey('unit-health-bar-frame'));
    final stars = find.byKey(const ValueKey('unit-star-indicator'));
    expect(health, findsOneWidget);
    expect(stars, findsOneWidget);
    expect(tester.getSize(health).width, inInclusiveRange(60, 68));
    expect(find.byKey(const ValueKey('unit-star-frame')), findsOneWidget);
    final unitOverlay =
        tester.widgetList<Stack>(find.byType(Stack)).singleWhere(
              (stack) => stack.children.any(
                (child) => child.key == const ValueKey('unit-star-layer'),
              ),
            );
    final starLayerIndex = unitOverlay.children.indexWhere(
      (child) => child.key == const ValueKey('unit-star-layer'),
    );
    final healthLayerIndex = unitOverlay.children.indexWhere(
      (child) => child.key == const ValueKey('unit-health-layer'),
    );
    expect(healthLayerIndex, greaterThan(starLayerIndex));
    expect(
      find.descendant(of: stars, matching: find.byIcon(Icons.star)),
      findsNWidgets(3),
    );
    expect(
      find.descendant(of: stars, matching: find.byIcon(Icons.star_border)),
      findsNWidgets(3),
    );
    expect(
      tester.getTopLeft(stars).dy,
      greaterThan(tester.getBottomLeft(health).dy),
    );
    expect(
      tester
          .widget<Positioned>(
            find
                .ancestor(
                  of: stars,
                  matching: find.byType(Positioned),
                )
                .first,
          )
          .bottom,
      isNotNull,
    );
  });

  testWidgets('unit HUD follows tile size instead of screen breakpoints',
      (tester) async {
    const tile = SizedBox.square(
      dimension: 100,
      child: BattleTile(
        slot: 0,
        unitSide: UnitSide.ally,
        unitState: UnitVisualState(
          unitId: UnitId.fighter,
          star: 1,
          hp: 80,
          maxHp: 100,
          alive: true,
        ),
      ),
    );

    await pumpThemed(tester, tile, surfaceSize: const Size(393, 852));
    final health = find.byKey(const ValueKey('unit-health-bar-frame'));
    final battleTile = find.byType(BattleTile);
    final phoneWidth = tester.getSize(health).width;
    final phoneTop =
        tester.getTopLeft(health).dy - tester.getTopLeft(battleTile).dy;

    await pumpThemed(tester, tile, surfaceSize: const Size(1024, 1366));
    final tabletWidth = tester.getSize(health).width;
    final tabletTop =
        tester.getTopLeft(health).dy - tester.getTopLeft(battleTile).dy;

    expect(phoneWidth, closeTo(tabletWidth, 0.1));
    expect(phoneTop, closeTo(tabletTop, 0.1));
  });
}
