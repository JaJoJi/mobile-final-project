import 'package:auto_chess_mobile/shared/models/game_events.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BoardPosition', () {
    test('slot ↔ row/col round-trips row-major', () {
      for (var slot = 0; slot < 9; slot++) {
        final pos = BoardPosition.fromSlot(slot);
        expect(pos.slot, slot);
        expect(pos.row, slot ~/ 3);
        expect(pos.col, slot % 3);
      }
      expect(const BoardPosition(row: 2, col: 1).slot, 7);
    });
  });

  group('Unit', () {
    test('parses a roster entry', () {
      final u = Unit.fromJson({
        'instanceId': 'u-1',
        'unitId': 'ranger',
        'star': 2,
        'hp': 40,
        'maxHp': 80,
      });
      expect(u.unitId, UnitId.ranger);
      expect(u.star, 2);
      expect(u.hpFraction, 0.5);
      expect(u.isAlive, isTrue);
    });

    test('unknown unitId falls back to fighter', () {
      expect(Unit.fromJson({'unitId': 'wizard'}).unitId, UnitId.fighter);
    });

    test('slotsFromJson pads/truncates to a fixed length with nulls', () {
      final slots = Unit.slotsFromJson(
        [
          {
            'instanceId': 'a',
            'unitId': 'tank',
            'star': 0,
            'hp': 100,
            'maxHp': 100,
          },
          null,
        ],
        9,
      );
      expect(slots, hasLength(9));
      expect(slots[0]!.unitId, UnitId.tank);
      expect(slots[1], isNull);
      expect(slots[8], isNull);
    });
  });

  group('MatchState', () {
    test('decodes roster, opponent summary and side', () {
      final s = MatchState.fromJson({
        'matchId': 'm1',
        'round': 4,
        'yourSide': 'p2',
        'roster': {
          'board': [
            {
              'instanceId': 'b0',
              'unitId': 'fighter',
              'star': 1,
              'hp': 60,
              'maxHp': 60,
            },
            ...List.filled(8, null),
          ],
          'bench': List.filled(8, null),
          'gold': 7,
          'hp': 85,
        },
        'opponent': {
          'gold': 3,
          'hp': 70,
          'boardSummary': [
            {'unitId': 'healer', 'star': 0},
            ...List.filled(8, null),
          ],
        },
        'readyCount': 1,
      });

      expect(s.yourSide, MatchSide.p2);
      expect(s.roster.board.first!.unitId, UnitId.fighter);
      expect(s.roster.bench, hasLength(8));
      expect(s.roster.gold, 7);
      expect(s.opponent.boardSummary.first!.unitId, UnitId.healer);
      expect(s.opponent.boardSummary, hasLength(9));
      expect(s.readyCount, 1);
    });

    test('tolerates missing roster / opponent maps', () {
      final s = MatchState.fromJson({'matchId': 'm1', 'round': 1});
      expect(s.roster.board, hasLength(9));
      expect(s.roster.board.every((e) => e == null), isTrue);
      expect(s.opponent.boardSummary, hasLength(9));
      expect(s.yourSide, MatchSide.p1);
    });
  });

  group('MatchPhaseEvent', () {
    test('maps every known phase string', () {
      String raw(GamePhase p) => switch (p) {
            GamePhase.shopPlace => 'shop_place',
            GamePhase.battle => 'battle',
            GamePhase.resolved => 'resolved',
            GamePhase.finished => 'finished',
            GamePhase.unknown => '???',
          };
      for (final p in GamePhase.values) {
        expect(GamePhase.fromJson(raw(p)), p);
      }
    });

    test('unknown phase → GamePhase.unknown', () {
      final e = MatchPhaseEvent.fromJson({'phase': 'intermission', 'round': 1});
      expect(e.phase, GamePhase.unknown);
    });
  });

  group('CombatEvent', () {
    test('decodes each subtype from its type discriminator', () {
      expect(
        CombatEvent.fromJson({
          'type': 'attack',
          'cycle': 1,
          'tick': 5,
          'attacker': 'a',
          'target': 'b',
          'damage': 12,
          'targetHpAfter': 30,
        }),
        isA<AttackEvent>()
            .having((e) => e.damage, 'damage', 12)
            .having((e) => e.tick, 'tick', 5),
      );
      expect(
        CombatEvent.fromJson(
          {'type': 'death', 'cycle': 2, 'tick': 1, 'unit': 'x'},
        ),
        isA<DeathEvent>().having((e) => e.unit, 'unit', 'x'),
      );
      expect(
        CombatEvent.fromJson({
          'type': 'heal',
          'cycle': 1,
          'tick': 2,
          'target': 't',
          'by': 'h',
          'amount': 8,
          'targetHpAfter': 50,
        }),
        isA<HealEvent>().having((e) => e.by, 'by', 'h'),
      );
      expect(
        CombatEvent.fromJson({'type': 'cycle_end', 'cycle': 3}),
        isA<CycleEndEvent>().having((e) => e.tick, 'tick', 0),
      );
    });

    test('battle_end carries a nullable winner side', () {
      expect(
        (CombatEvent.fromJson(
          {'type': 'battle_end', 'cycle': 9, 'winner': 'p1'},
        ) as BattleEndEvent)
            .winner,
        MatchSide.p1,
      );
      expect(
        (CombatEvent.fromJson(
          {'type': 'battle_end', 'cycle': 9, 'winner': null},
        ) as BattleEndEvent)
            .winner,
        isNull,
      );
    });

    test('unknown type → UnknownCombatEvent, never throws', () {
      final e = CombatEvent.fromJson({'type': 'meteor', 'cycle': 1, 'tick': 1});
      expect(e, isA<UnknownCombatEvent>());
      expect((e as UnknownCombatEvent).type, 'meteor');
    });

    test('a switch over CombatEvent is exhaustive', () {
      String label(CombatEvent e) => switch (e) {
            AttackEvent() => 'attack',
            DeathEvent() => 'death',
            ReviveEvent() => 'revive',
            HealEvent() => 'heal',
            LifestealEvent() => 'lifesteal',
            PierceEvent() => 'pierce',
            SlowEvent() => 'slow',
            CycleEndEvent() => 'cycle_end',
            BattleEndEvent() => 'battle_end',
            UnknownCombatEvent() => 'unknown',
          };
      expect(label(const DeathEvent(cycle: 1, tick: 1, unit: 'u')), 'death');
    });

    test('CombatEventBatch decodes the ordered list + metadata', () {
      final batch = CombatEventBatch.fromJson({
        'matchId': 'm1',
        'round': 5,
        'cycleCount': 12,
        'endedAt': 1700000000000,
        'events': [
          {
            'type': 'attack',
            'cycle': 1,
            'tick': 1,
            'attacker': 'a',
            'target': 'b',
            'damage': 5,
            'targetHpAfter': 20,
          },
          {'type': 'battle_end', 'cycle': 1, 'winner': 'p2'},
        ],
      });
      expect(batch.events, hasLength(2));
      expect(batch.events.first, isA<AttackEvent>());
      expect(batch.events.last, isA<BattleEndEvent>());
      expect(batch.cycleCount, 12);
      expect(batch.endedAtTime.isUtc, isTrue);
    });
  });

  group('ShopOffersEvent', () {
    test('keeps null holes for purchased slots', () {
      final e = ShopOffersEvent.fromJson({
        'matchId': 'm1',
        'round': 2,
        'offers': [
          {'offerId': 'o1', 'unitId': 'tank', 'star': 0},
          null,
          {'offerId': 'o3', 'unitId': 'healer', 'star': 0},
        ],
      });
      expect(e.offers, hasLength(3));
      expect(e.offers[0]!.unitId, UnitId.tank);
      expect(e.offers[1], isNull);
      expect(e.offers[2]!.offerId, 'o3');
    });
  });

  group('MatchDamageEvent', () {
    test('decodes both sides and the round winner', () {
      final e = MatchDamageEvent.fromJson({
        'matchId': 'm1',
        'round': 3,
        'damage': {
          'p1': {
            'wiped': true,
            'tie': false,
            'hpBefore': 40,
            'hpAfter': 25,
            'damageApplied': 15,
          },
          'p2': {
            'wiped': false,
            'tie': false,
            'hpBefore': 60,
            'hpAfter': 60,
            'damageApplied': 0,
          },
        },
        'winner': 'p2',
      });
      expect(e.p1.wiped, isTrue);
      expect(e.p1.damageApplied, 15);
      expect(e.p2.hpAfter, 60);
      expect(e.winner, RoundOutcome.p2);
    });

    test('null winner when the round is undecided', () {
      final e = MatchDamageEvent.fromJson(
        {'matchId': 'm', 'round': 1, 'winner': null},
      );
      expect(e.winner, isNull);
    });
  });

  group('MatchEndEvent', () {
    test('decodes winner + reason + final states', () {
      final e = MatchEndEvent.fromJson({
        'matchId': 'm1',
        'winnerId': 'user-2',
        'reason': 'hp_zero',
        'final': {
          'p1': {'hp': 0, 'gold': 3},
          'p2': {'hp': 12, 'gold': 8},
        },
      });
      expect(e.reason, MatchEndReason.hpZero);
      expect(e.didWin('user-2'), isTrue);
      expect(e.didWin('user-1'), isFalse);
      expect(e.isDraw, isFalse);
      expect(e.finalP2.gold, 8);
    });

    test('null winnerId is a draw', () {
      final e = MatchEndEvent.fromJson(
        {'matchId': 'm', 'winnerId': null, 'reason': 'hp_zero'},
      );
      expect(e.isDraw, isTrue);
      expect(e.didWin('anyone'), isFalse);
    });

    test('unknown reason string → MatchEndReason.unknown', () {
      final e = MatchEndEvent.fromJson({'matchId': 'm', 'reason': 'meltdown'});
      expect(e.reason, MatchEndReason.unknown);
    });
  });

  group('GameError', () {
    test('flags auth codes', () {
      expect(const GameError(code: 'auth.invalid').isAuth, isTrue);
      expect(const GameError(code: 'auth.expired').isAuth, isTrue);
      expect(const GameError(code: 'rate.limited').isAuth, isFalse);
      expect(const GameError(code: 'rate.limited').isRateLimit, isTrue);
    });

    test('fromJson defaults a missing code to "unknown"', () {
      expect(GameError.fromJson(const {}).code, 'unknown');
    });
  });

  group('GameEvents / GameActions names', () {
    test('server event names match the API contract', () {
      expect(GameEvents.matchPhase, 'game:match:phase');
      expect(GameEvents.combatEvents, 'game:combat:events');
      expect(GameEvents.all, contains('game:match:end'));
      expect(GameEvents.all, hasLength(7));
    });

    test('client action names match the API contract', () {
      expect(GameActions.shopBuy, 'game:shop:buy');
      expect(GameActions.matchCombatDone, 'game:match:combat_done');
    });
  });
}
