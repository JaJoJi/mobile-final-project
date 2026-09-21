import 'package:auto_chess_mobile/features/match/battle/battle_playback_controller.dart';
import 'package:auto_chess_mobile/shared/models/combat_event.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('combatPlaybackDuration', () {
    test('keeps sparse and dense battle animation speeds comparable', () {
      const sparseEvents = 10;
      const denseEvents = 77;
      final sparseMs =
          combatPlaybackDuration(sparseEvents).inMilliseconds / sparseEvents;
      final denseMs =
          combatPlaybackDuration(denseEvents).inMilliseconds / denseEvents;

      expect(sparseMs, 900);
      expect(denseMs, greaterThanOrEqualTo(700));
      expect(sparseMs / denseMs, lessThan(1.3));
    });

    test('still finishes before the server combat timeout', () {
      expect(combatPlaybackDuration(2000), kMaxCombatPlayback);
      expect(
        kMaxCombatPlayback + const Duration(milliseconds: 500),
        lessThan(const Duration(seconds: 60)),
      );
    });
  });

  group('BattlePlaybackController.loadBatch', () {
    test('drops death events — the paired attack already carries the kill', () {
      // `applyDamage` (backend/src/game/damage.ts) emits a `death` event
      // immediately followed by its own `attack` event for the SAME
      // lethal hit — the `attack` event alone already carries
      // `targetHpAfter: 0` and a snapshot with the target dead, so
      // `death` adds no visual information CombatEffectsOverlay or
      // deriveUnitStates ever reads (`DeathEvent` has zero consumers in
      // the whole visual pipeline).
      //
      // Left in the playhead timeline, `death` became its own 1.6s slot
      // that reveals the target as dead *before* the attacker's own
      // travel/impact animation for that exact kill has even started —
      // so on every single kill, a still-alive attacker visibly strikes
      // a target the board is already showing as dead. Filtering it out,
      // the same way cycle_end/battle_end already are, collapses the
      // kill back into the one event that actually depicts it.
      const attack1 = AttackEvent(
        cycle: 1,
        tick: 10,
        attacker: 'a',
        target: 'b',
        damage: 10,
        targetHpAfter: 5,
      );
      const death = DeathEvent(cycle: 1, tick: 20, unit: 'b');
      const attack2 = AttackEvent(
        cycle: 1,
        tick: 20,
        attacker: 'a',
        target: 'b',
        damage: 10,
        targetHpAfter: 0,
      );
      final controller = BattlePlaybackController();
      controller.loadBatch(
        const CombatEventBatch(
          matchId: 'm1',
          round: 1,
          cycleCount: 1,
          endedAt: 0,
          events: [attack1, death, attack2],
        ),
      );

      expect(controller.events, [attack1, attack2]);
    });
  });
}
