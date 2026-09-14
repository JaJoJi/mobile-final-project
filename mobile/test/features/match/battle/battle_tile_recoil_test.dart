import 'package:auto_chess_mobile/core/widgets/unit_avatar.dart' show UnitSide;
import 'package:auto_chess_mobile/features/match/battle/battle_view.dart';
import 'package:auto_chess_mobile/features/match/battle/battle_visual_state.dart';
import 'package:auto_chess_mobile/shared/models/unit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../widgets/_harness.dart';

const _idle = UnitVisualState(
  unitId: UnitId.fighter,
  star: 1,
  hp: 100,
  maxHp: 100,
  alive: true,
);

const _recoiling = UnitVisualState(
  unitId: UnitId.fighter,
  star: 1,
  hp: 100,
  maxHp: 100,
  alive: true,
  recoilEventIndex: 0,
  recoilDx: 1,
  recoilDy: -1,
);

void main() {
  testWidgets(
      'BattleTile nudges the attacker toward its target on a new '
      'recoil index', (tester) async {
    await pumpThemed(
      tester,
      const BattleTile(slot: 0, unitSide: UnitSide.ally, unitState: _idle),
    );

    await pumpThemed(
      tester,
      const BattleTile(
        slot: 0,
        unitSide: UnitSide.ally,
        unitState: _recoiling,
      ),
    );
    // Mid-recoil: the forward half of the there-and-back animation.
    await tester.pump(const Duration(milliseconds: 50));

    final transform = tester.widget<Transform>(
      find
          .descendant(
            of: find.byType(BattleTile),
            matching: find.byType(Transform),
          )
          .first,
    );
    final offset = transform.transform.getTranslation();
    expect(offset.x, greaterThan(0));
    expect(offset.y, lessThan(0));
  });

  testWidgets('BattleTile does not nudge when there is no recoil index',
      (tester) async {
    await pumpThemed(
      tester,
      const BattleTile(slot: 0, unitSide: UnitSide.ally, unitState: _idle),
    );
    await tester.pump(const Duration(milliseconds: 50));

    final transform = tester.widget<Transform>(
      find
          .descendant(
            of: find.byType(BattleTile),
            matching: find.byType(Transform),
          )
          .first,
    );
    final offset = transform.transform.getTranslation();
    expect(offset.x, 0);
    expect(offset.y, 0);
  });
}
