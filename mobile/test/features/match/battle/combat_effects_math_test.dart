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
  test('melee travel eases both legs without moving the impact time', () {
    expect(meleeTravel(0), 0);
    expect(meleeTravel(0.5), 1);
    expect(meleeTravel(1), 0);
    expect(meleeTravel(0.001), lessThan(0.00002));
    expect(1 - meleeTravel(0.499), lessThan(0.00002));
    for (var i = 1; i <= 50; i++) {
      final t = i / 100;
      expect(meleeTravel(t), greaterThan(meleeTravel(t - 0.01)));
      expect(meleeTravel(t), closeTo(meleeTravel(1 - t), 0.000001));
    }
  });

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

    test('clamps playheadProgress of 1.0 to the last event, not out of range',
        () {
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

    test('landscape puts depth on the column axis, not the row axis', () {
      // Slot 0 = front row, lane 0. Side-by-side boards (landscape) put
      // "mine" on the left with the VS divider on its right, so front
      // (depth 0) has to land in the *rightmost* column, not the top row.
      final mine = tileLocalCenter(
        slot: 0,
        boardWidth: 300,
        boardHeight: 300,
        spacing: 4,
        landscape: true,
      );
      expect(mine.dx, closeTo(251.333, 0.01)); // column 2 (rightmost)
      expect(mine.dy, closeTo(48.667, 0.01)); // row 0 (lane unchanged)

      // Opponent's divider is on its *left*, so its front lands in the
      // leftmost column instead — the same `reverseRows` flag that used
      // to flip the row axis now flips the column axis.
      final opponent = tileLocalCenter(
        slot: 0,
        boardWidth: 300,
        boardHeight: 300,
        spacing: 4,
        reverseRows: true,
        landscape: true,
      );
      expect(opponent.dx, closeTo(48.667, 0.01)); // column 0 (leftmost)
      expect(opponent.dy, closeTo(48.667, 0.01)); // row 0 (lane unchanged)
    });
  });

  group('impactFraction', () {
    const melee = AttackEvent(
      cycle: 1,
      tick: 1,
      attacker: 'a',
      target: 'b',
      damage: 10,
      targetHpAfter: 90,
      attackerUnitId: UnitId.fighter,
    );
    const ranged = AttackEvent(
      cycle: 1,
      tick: 1,
      attacker: 'a',
      target: 'b',
      damage: 10,
      targetHpAfter: 90,
      attackerUnitId: UnitId.ranger,
    );
    const heal = HealEvent(
      cycle: 1,
      tick: 1,
      by: 'h',
      target: 'b',
      amount: 10,
      targetHpAfter: 100,
    );
    const positionedHeal = HealEvent(
      cycle: 1,
      tick: 1,
      by: 'h',
      target: 'b',
      amount: 10,
      targetHpAfter: 100,
      bySide: MatchSide.p1,
      bySlot: 0,
      targetSide: MatchSide.p1,
      targetSlot: 4,
    );

    test('a melee attack lands at the peak of its lunge', () {
      // triangleWave peaks at 0.5, which is exactly where the attacker
      // sprite is standing on the target's tile.
      expect(impactFraction(melee), 0.5);
    });

    test('a projectile lands near the end of its flight, still on screen', () {
      // The whole point of #215: the hit has to read as happening when
      // the projectile arrives, and the projectile has to still be
      // visible at that moment rather than already gone.
      final f = impactFraction(ranged);
      expect(f, greaterThan(0.5));
      expect(f, lessThan(1.0));
    });

    test('a healer projectile flies as long as a ranger one', () {
      const healerAttack = AttackEvent(
        cycle: 1,
        tick: 1,
        attacker: 'a',
        target: 'b',
        damage: 6,
        targetHpAfter: 94,
        attackerUnitId: UnitId.healer,
      );
      expect(impactFraction(healerAttack), impactFraction(ranged));
    });

    test('an event with no travel lands immediately', () {
      expect(impactFraction(heal), 0.0);
    });

    test('a positioned heal lands when its source energy arrives', () {
      expect(impactFraction(positionedHeal), kHealImpactFraction);
      expect(healTravel(kHealImpactFraction / 2), closeTo(0.5, 0.001));
    });
  });

  group('hasImpacted', () {
    const ranged = AttackEvent(
      cycle: 1,
      tick: 1,
      attacker: 'a',
      target: 'b',
      damage: 10,
      targetHpAfter: 90,
      attackerUnitId: UnitId.ranger,
    );

    test('is false while the projectile is still in flight', () {
      expect(hasImpacted(ranged, 0.0), isFalse);
      expect(hasImpacted(ranged, 0.5), isFalse);
    });

    test('is true from the impact point onward', () {
      expect(hasImpacted(ranged, impactFraction(ranged)), isTrue);
      expect(hasImpacted(ranged, 1.0), isTrue);
    });

    test('a null event has nothing left in flight', () {
      expect(hasImpacted(null, 0.0), isTrue);
    });
  });
}
