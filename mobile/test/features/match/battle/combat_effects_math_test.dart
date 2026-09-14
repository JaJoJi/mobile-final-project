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
  });
}
