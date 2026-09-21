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

const _healerHealed = UnitVisualState(
  unitId: UnitId.healer,
  star: 2,
  hp: 70,
  maxHp: 70,
  alive: true,
  healEventIndex: 4,
  isHealerHeal: true,
);

const _idleHealer = UnitVisualState(
  unitId: UnitId.healer,
  star: 2,
  hp: 70,
  maxHp: 70,
  alive: true,
);

const _lifestealing = UnitVisualState(
  unitId: UnitId.fighter,
  star: 2,
  hp: 100,
  maxHp: 100,
  alive: true,
  healEventIndex: 5,
);

const _damaged = UnitVisualState(
  unitId: UnitId.fighter,
  star: 1,
  hp: 100,
  maxHp: 100,
  alive: true,
  floatingDamage: 12,
  lastDamageEventIndex: 6,
  hitEffectKind: HitEffectKind.slash,
);

const _projectileDamaged = UnitVisualState(
  unitId: UnitId.fighter,
  star: 1,
  hp: 88,
  maxHp: 100,
  alive: true,
  floatingDamage: 12,
  lastDamageEventIndex: 7,
  hitEffectKind: HitEffectKind.projectile,
);

const _healed = UnitVisualState(
  unitId: UnitId.healer,
  star: 2,
  hp: 70,
  maxHp: 70,
  alive: true,
  floatingDamage: 18,
  floatingIsHeal: true,
  healEventIndex: 7,
  isHealerHeal: true,
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

  testWidgets('recoil still plays under reduced motion, not squashed to 5%',
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

  testWidgets('Healer heal uses the generated sigil on the event target',
      (tester) async {
    await pumpThemed(
      tester,
      const BattleTile(
        slot: 0,
        unitSide: UnitSide.ally,
        unitState: _idleHealer,
      ),
    );
    await pumpThemed(
      tester,
      const BattleTile(
        slot: 0,
        unitSide: UnitSide.ally,
        unitState: _healerHealed,
      ),
    );

    final image = tester.widget<Image>(
      find.byKey(const ValueKey('healer-heal-vfx')),
    );
    expect(
      (image.image as AssetImage).assetName,
      'assets/images/vfx/healer_heal_burst.png',
    );
    expect(
      find.byKey(const ValueKey('healer-heal-particles')),
      findsOneWidget,
    );
  });

  testWidgets('melee damage paints a short slash impact', (tester) async {
    await pumpThemed(
      tester,
      const BattleTile(slot: 0, unitSide: UnitSide.ally, unitState: _idle),
    );
    await pumpThemed(
      tester,
      const BattleTile(slot: 0, unitSide: UnitSide.ally, unitState: _damaged),
    );
    await tester.pump(const Duration(milliseconds: 80));

    expect(find.byKey(const ValueKey('slash-hit-vfx')), findsOneWidget);
    expect(find.byKey(const ValueKey('projectile-hit-vfx')), findsNothing);

    await tester.pump(const Duration(milliseconds: 420));
    expect(find.byKey(const ValueKey('slash-hit-vfx')), findsNothing);
  });

  testWidgets('ranged damage paints a compact projectile impact',
      (tester) async {
    await pumpThemed(
      tester,
      const BattleTile(slot: 0, unitSide: UnitSide.ally, unitState: _idle),
    );
    await pumpThemed(
      tester,
      const BattleTile(
        slot: 0,
        unitSide: UnitSide.ally,
        unitState: _projectileDamaged,
      ),
    );
    await tester.pump(const Duration(milliseconds: 80));

    expect(find.byKey(const ValueKey('projectile-hit-vfx')), findsOneWidget);
    expect(find.byKey(const ValueKey('slash-hit-vfx')), findsNothing);

    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byKey(const ValueKey('projectile-hit-vfx')), findsNothing);
  });

  testWidgets('Fighter lifesteal does not borrow the Healer sigil',
      (tester) async {
    await pumpThemed(
      tester,
      const BattleTile(slot: 0, unitSide: UnitSide.ally, unitState: _idle),
    );
    await pumpThemed(
      tester,
      const BattleTile(
        slot: 0,
        unitSide: UnitSide.ally,
        unitState: _lifestealing,
      ),
    );

    expect(find.byKey(const ValueKey('healer-heal-vfx')), findsNothing);
    expect(find.byKey(const ValueKey('lifesteal-pulse')), findsOneWidget);
  });

  testWidgets('damage number uses large outlined combat text', (tester) async {
    await pumpThemed(
      tester,
      const BattleTile(slot: 0, unitSide: UnitSide.ally, unitState: _idle),
    );
    await pumpThemed(
      tester,
      const BattleTile(
        slot: 0,
        unitSide: UnitSide.ally,
        unitState: _damaged,
      ),
    );
    await tester.pump(const Duration(milliseconds: 80));

    expect(
      find.byKey(const ValueKey('floating-damage-number')),
      findsOneWidget,
    );
    final labels = tester.widgetList<Text>(find.text('-12')).toList();
    expect(labels, hasLength(2));
    expect(labels.any((text) => text.style?.foreground != null), isTrue);
    expect(labels.every((text) => (text.style?.fontSize ?? 0) >= 20), isTrue);
    expect(
      labels.every((text) => text.style?.fontWeight == FontWeight.w900),
      isTrue,
    );
  });

  testWidgets('heal number uses the same prominent treatment', (tester) async {
    await pumpThemed(
      tester,
      const BattleTile(
        slot: 0,
        unitSide: UnitSide.ally,
        unitState: _idleHealer,
      ),
    );
    await pumpThemed(
      tester,
      const BattleTile(
        slot: 0,
        unitSide: UnitSide.ally,
        unitState: _healed,
      ),
    );
    await tester.pump(const Duration(milliseconds: 80));

    expect(
      find.byKey(const ValueKey('floating-heal-number')),
      findsOneWidget,
    );
    final labels = tester.widgetList<Text>(find.text('+18')).toList();
    expect(labels, hasLength(2));
    expect(labels.any((text) => text.style?.foreground != null), isTrue);
    expect(labels.every((text) => (text.style?.fontSize ?? 0) >= 20), isTrue);
  });

  testWidgets('ranged impact number survives the event boundary',
      (tester) async {
    await pumpThemed(
      tester,
      const BattleTile(slot: 0, unitSide: UnitSide.ally, unitState: _idle),
    );
    await pumpThemed(
      tester,
      const BattleTile(
        slot: 0,
        unitSide: UnitSide.ally,
        unitState: _damaged,
      ),
    );
    await tester.pump(const Duration(milliseconds: 80));

    // A ranged hit lands near the end of its event. The next event clears
    // floatingDamage from UnitVisualState almost immediately, but the number
    // must finish its own animation instead of disappearing with that event.
    await pumpThemed(
      tester,
      const BattleTile(slot: 0, unitSide: UnitSide.ally, unitState: _idle),
    );
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      find.byKey(const ValueKey('floating-damage-number')),
      findsOneWidget,
    );

    await tester.pump(const Duration(milliseconds: 600));
    expect(
      find.byKey(const ValueKey('floating-damage-number')),
      findsNothing,
    );
  });
}
