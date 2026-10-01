import 'package:auto_chess_mobile/features/match/battle/battle_playback_controller.dart';
import 'package:auto_chess_mobile/shared/models/combat_event.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('combatPlaybackDuration', () {
    test('uses exactly the same duration per event at every battle size', () {
      for (final eventCount in [1, 10, 77, 2000]) {
        expect(
          combatPlaybackDuration(eventCount).inMilliseconds ~/ eventCount,
          800,
        );
      }
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
