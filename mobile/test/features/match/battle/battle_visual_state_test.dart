import 'package:auto_chess_mobile/features/match/battle/battle_visual_state.dart';
import 'package:auto_chess_mobile/shared/models/combat_event.dart';
import 'package:auto_chess_mobile/shared/models/match_state.dart';
import 'package:auto_chess_mobile/shared/models/unit.dart';
import 'package:flutter_test/flutter_test.dart';

const _attackerSnapshot = UnitSnapshot(
  instanceId: 'a1',
  unitId: UnitId.fighter,
  star: 1,
  hp: 100,
  maxHp: 100,
  slot: 0,
  side: MatchSide.p1,
  alive: true,
);

const _targetSnapshot = UnitSnapshot(
  instanceId: 'b1',
  unitId: UnitId.ranger,
  star: 1,
  hp: 90,
  maxHp: 100,
  slot: 4,
  side: MatchSide.p2,
  alive: true,
);

void main() {
  group('deriveUnitStates recoil', () {
    test('sets a recoil trigger + direction on a melee attacker', () {
      const event = AttackEvent(
        cycle: 1,
        tick: 1,
        attacker: 'a1',
        target: 'b1',
        damage: 10,
        targetHpAfter: 90,
        attackerSide: MatchSide.p1,
        attackerSlot: 0,
        attackerUnitId: UnitId.fighter,
        targetSide: MatchSide.p2,
        targetSlot: 4,
        unitStates: [_attackerSnapshot, _targetSnapshot],
      );

      final map = deriveUnitStates(
        events: const [event],
        playheadIndex: 0,
        playerBoard: const [],
        opponentBoard: const [],
      );

      final attacker = map[const UnitKey(side: MatchSide.p1, slot: 0)];
      expect(attacker, isNotNull);
      expect(attacker!.recoilEventIndex, 0);
      // attacker col 0, target col 1 -> dCol +1; p1 attacking "up" -> dRow -1.
      expect(attacker.recoilDx, 1.0);
      expect(attacker.recoilDy, -1.0);
    });

    test('does not set a recoil trigger on a ranged attacker', () {
      const event = AttackEvent(
        cycle: 1,
        tick: 1,
        attacker: 'r1',
        target: 'b1',
        damage: 10,
        targetHpAfter: 90,
        attackerSide: MatchSide.p1,
        attackerSlot: 0,
        attackerUnitId: UnitId.ranger,
        targetSide: MatchSide.p2,
        targetSlot: 4,
        unitStates: [
          UnitSnapshot(
            instanceId: 'r1',
            unitId: UnitId.ranger,
            star: 1,
            hp: 100,
            maxHp: 100,
            slot: 0,
            side: MatchSide.p1,
            alive: true,
          ),
          _targetSnapshot,
        ],
      );

      final map = deriveUnitStates(
        events: const [event],
        playheadIndex: 0,
        playerBoard: const [],
        opponentBoard: const [],
      );

      final attacker = map[const UnitKey(side: MatchSide.p1, slot: 0)];
      expect(attacker, isNotNull);
      expect(attacker!.recoilEventIndex, isNull);
      expect(attacker.recoilDx, 0.0);
      expect(attacker.recoilDy, 0.0);
    });

    test(
        'recoil trigger persists across later events until this unit '
        'attacks again', () {
      const firstAttack = AttackEvent(
        cycle: 1,
        tick: 1,
        attacker: 'a1',
        target: 'b1',
        damage: 10,
        targetHpAfter: 90,
        attackerSide: MatchSide.p1,
        attackerSlot: 0,
        attackerUnitId: UnitId.fighter,
        targetSide: MatchSide.p2,
        targetSlot: 4,
        unitStates: [_attackerSnapshot, _targetSnapshot],
      );
      const unrelatedEvent = AttackEvent(
        cycle: 1,
        tick: 2,
        attacker: 'b1',
        target: 'a1',
        damage: 5,
        targetHpAfter: 95,
        attackerSide: MatchSide.p2,
        attackerSlot: 4,
        attackerUnitId: UnitId.ranger,
        targetSide: MatchSide.p1,
        targetSlot: 0,
        unitStates: [_attackerSnapshot, _targetSnapshot],
      );

      final map = deriveUnitStates(
        events: const [firstAttack, unrelatedEvent],
        playheadIndex: 1,
        playerBoard: const [],
        opponentBoard: const [],
      );

      final attacker = map[const UnitKey(side: MatchSide.p1, slot: 0)];
      expect(attacker!.recoilEventIndex, 0);
    });
  });
}
