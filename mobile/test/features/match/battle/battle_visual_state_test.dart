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
  group('deriveUnitStates initial board fallback', () {
    const eventWithoutSnapshots = AttackEvent(
      cycle: 1,
      tick: 1,
      attacker: 'p1-fighter',
      target: 'p2-ranger',
      damage: 10,
      targetHpAfter: 90,
    );

    test('uses the authoritative initial board when snapshots are absent', () {
      const initialBoard = CombatBoardState(
        p1: [
          CombatUnit(
            instanceId: 'p1-fighter',
            unitId: UnitId.fighter,
            star: 2,
            hp: 140,
            maxHp: 140,
          ),
        ],
        p2: [
          null,
          CombatUnit(
            instanceId: 'p2-ranger',
            unitId: UnitId.ranger,
            star: 1,
            hp: 90,
            maxHp: 100,
          ),
        ],
      );

      final map = deriveUnitStates(
        events: const [eventWithoutSnapshots],
        playheadIndex: 0,
        playerBoard: const [],
        opponentBoard: const [],
        mySide: MatchSide.p1,
        initialBoard: initialBoard,
      );

      expect(
        map[const UnitKey(side: MatchSide.p1, slot: 0)]?.unitId,
        UnitId.fighter,
      );
      expect(
        map[const UnitKey(side: MatchSide.p1, slot: 0)]?.star,
        2,
      );
      expect(
        map[const UnitKey(side: MatchSide.p2, slot: 1)]?.unitId,
        UnitId.ranger,
      );
    });

    test('falls back to viewer-relative match boards for legacy batches', () {
      const fighter = Unit(
        instanceId: 'mine',
        unitId: UnitId.fighter,
        star: 0,
        hp: 100,
        maxHp: 100,
      );
      const healer = Unit(
        instanceId: 'enemy',
        unitId: UnitId.healer,
        star: 1,
        hp: 80,
        maxHp: 100,
      );

      final map = deriveUnitStates(
        events: const [eventWithoutSnapshots],
        playheadIndex: 0,
        playerBoard: const [null, fighter],
        opponentBoard: const [healer],
        mySide: MatchSide.p2,
      );

      expect(
        map[const UnitKey(side: MatchSide.p2, slot: 1)]?.unitId,
        UnitId.fighter,
      );
      expect(
        map[const UnitKey(side: MatchSide.p1, slot: 0)]?.unitId,
        UnitId.healer,
      );
    });
  });

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
        mySide: MatchSide.p1,
      );

      final attacker = map[const UnitKey(side: MatchSide.p1, slot: 0)];
      expect(attacker, isNotNull);
      expect(attacker!.recoilEventIndex, 0);
      // attacker col 0, target col 1 -> dCol +1. Viewer is p1, so this is
      // the viewer's own unit: it sits on the bottom board and nudges up.
      expect(attacker.recoilDx, 1.0);
      expect(attacker.recoilDy, -1.0);
    });

    test('recoil direction is relative to the viewer, not the absolute side',
        () {
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

      // Same event, but seen by the p2 player: the p1 attacker is now the
      // *opponent*, rendered on the top board, so it must nudge downward
      // (toward the viewer's own board) rather than up.
      final map = deriveUnitStates(
        events: const [event],
        playheadIndex: 0,
        playerBoard: const [],
        opponentBoard: const [],
        mySide: MatchSide.p2,
      );

      final attacker = map[const UnitKey(side: MatchSide.p1, slot: 0)];
      expect(attacker!.recoilDy, 1.0);
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
        mySide: MatchSide.p1,
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
        mySide: MatchSide.p1,
      );

      final attacker = map[const UnitKey(side: MatchSide.p1, slot: 0)];
      expect(attacker!.recoilEventIndex, 0);
    });
  });

  group('a hit lands when the shot arrives, not when it is fired (#215)', () {
    // Two ranger shots at the same target: the first has already landed,
    // the second is the one in flight.
    const first = AttackEvent(
      cycle: 1,
      tick: 1,
      attacker: 'r1',
      target: 't1',
      damage: 12,
      targetHpAfter: 88,
      attackerSide: MatchSide.p1,
      attackerSlot: 6,
      attackerUnitId: UnitId.ranger,
      targetSide: MatchSide.p2,
      targetSlot: 0,
      unitStates: [
        UnitSnapshot(
          instanceId: 't1',
          unitId: UnitId.fighter,
          star: 0,
          hp: 88,
          maxHp: 100,
          slot: 0,
          side: MatchSide.p2,
          alive: true,
        ),
      ],
    );
    const second = AttackEvent(
      cycle: 1,
      tick: 2,
      attacker: 'r1',
      target: 't1',
      damage: 12,
      targetHpAfter: 76,
      attackerSide: MatchSide.p1,
      attackerSlot: 6,
      attackerUnitId: UnitId.ranger,
      targetSide: MatchSide.p2,
      targetSlot: 0,
      unitStates: [
        UnitSnapshot(
          instanceId: 't1',
          unitId: UnitId.fighter,
          star: 0,
          hp: 76,
          maxHp: 100,
          slot: 0,
          side: MatchSide.p2,
          alive: true,
        ),
      ],
    );

    const targetKey = UnitKey(side: MatchSide.p2, slot: 0);

    Map<UnitKey, UnitVisualState> derive({required bool landed}) =>
        deriveUnitStates(
          events: const [first, second],
          playheadIndex: 1,
          playerBoard: const [],
          opponentBoard: const [],
          mySide: MatchSide.p1,
          currentEventLanded: landed,
        );

    test('mid-flight the target still shows the previous hit', () {
      final target = derive(landed: false)[targetKey];
      expect(
        target?.hp,
        88,
        reason: 'HP dropped to the post-impact value while the projectile '
            'was still travelling',
      );
      expect(
        target?.floatingDamage,
        isNull,
        reason: 'the damage number appeared before the projectile arrived',
      );
      expect(
        target?.lastDamageEventIndex,
        0,
        reason: 'the hit shake fired for an event still in flight',
      );
    });

    test('on impact the hit lands', () {
      final target = derive(landed: true)[targetKey];
      expect(target?.hp, 76);
      expect(target?.floatingDamage, 12);
      expect(target?.lastDamageEventIndex, 1);
    });

    test('the attacker keeps animating while its shot is in flight', () {
      // The attacker's own state is driven by the event being played, not
      // by whether its outcome has landed — otherwise the shot would be
      // fired by a unit that never moved.
      const meleeInFlight = AttackEvent(
        cycle: 1,
        tick: 1,
        attacker: 'f1',
        target: 't1',
        damage: 15,
        targetHpAfter: 85,
        attackerSide: MatchSide.p1,
        attackerSlot: 0,
        attackerUnitId: UnitId.fighter,
        targetSide: MatchSide.p2,
        targetSlot: 0,
        unitStates: [
          UnitSnapshot(
            instanceId: 'f1',
            unitId: UnitId.fighter,
            star: 0,
            hp: 100,
            maxHp: 100,
            slot: 0,
            side: MatchSide.p1,
            alive: true,
          ),
        ],
      );
      final map = deriveUnitStates(
        events: const [meleeInFlight],
        playheadIndex: 0,
        playerBoard: const [],
        opponentBoard: const [],
        mySide: MatchSide.p1,
        currentEventLanded: false,
      );
      final attacker = map[const UnitKey(side: MatchSide.p1, slot: 0)];
      expect(attacker?.isMeleeAttacking, isTrue);
      expect(attacker?.recoilEventIndex, 0);
    });
  });
}
