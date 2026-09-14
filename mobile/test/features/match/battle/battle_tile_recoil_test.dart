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

  testWidgets(
      'recoil still plays under reduced motion, not squashed to 5%',
      (tester) async {
    // Flutter runs every AnimationBehavior.normal controller at 5% of its
    // duration while the platform reports "disable animations" — a 125ms
    // recoil becomes 6ms, so the unit looked like it "just stands still"
    // on hit. `animationBehavior: AnimationBehavior.preserve` is what
    // opts a functional animation (this one, not decoration) out of that.
    tester.binding.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(
      tester.binding.platformDispatcher.clearAccessibilityFeaturesTestValue,
    );

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
    // The forward-then-reverse nudge never changes sign, only magnitude —
    // 0 rising to a peak, then falling back to 0 — so a single sample
    // can't tell "still animating" from "already finished and settled
    // back at rest" by sign alone; both read as non-negative. At 5% of
    // 125ms the whole there-and-back cycle completes in ~12ms, well
    // inside a single 50ms `pump`, and a controller with no more frames
    // to process just sits at its last value: 0. So the real signal is
    // magnitude at a point the *unscaled* animation is still mid-flight —
    // verified empirically (with the fix in place) to be a clearly
    // nonzero ~7px at a cumulative 50ms, vs. exactly 0 without it.
    //
    // Small steps, not one 50ms jump: `AnimationController.reverse()` is
    // chained via a `Future` completion callback, which only actually
    // runs between frames — a single big pump can leave the animation
    // pinned at its forward endpoint (value 1.0, still nonzero) without
    // ever driving the reverse leg, which would mask the bug just as
    // effectively as a real fix does.
    for (final step in [1, 1, 1, 2, 5, 10, 10, 10, 10]) {
      await tester.pump(Duration(milliseconds: step));
    }

    final transform = tester.widget<Transform>(
      find
          .descendant(
            of: find.byType(BattleTile),
            matching: find.byType(Transform),
          )
          .first,
    );
    final offset = transform.transform.getTranslation();
    expect(
      offset.x,
      greaterThan(1),
      reason: 'recoil had already finished and settled back to rest by '
          '50ms — reduced-motion scaling was not overridden '
          '(offset was $offset)',
    );
    expect(offset.y, lessThan(-1));
  });
}
