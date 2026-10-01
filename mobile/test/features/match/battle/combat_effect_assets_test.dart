import 'package:auto_chess_mobile/features/match/battle/combat_effect_assets.dart';
import 'package:auto_chess_mobile/shared/models/combat_event.dart';
import 'package:auto_chess_mobile/shared/models/unit.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  AttackEvent attack(UnitId unitId) => AttackEvent(
        cycle: 1,
        tick: 1,
        attacker: 'attacker',
        target: 'target',
        damage: 10,
        targetHpAfter: 90,
        attackerUnitId: unitId,
      );

  test('maps only server events owned by Ranger and Healer VFX', () {
    expect(
      combatEffectForEvent(attack(UnitId.ranger)),
      CombatEffectKind.rangerProjectile,
    );
    expect(
      combatEffectForEvent(attack(UnitId.healer)),
      CombatEffectKind.healerAttackProjectile,
    );
    expect(combatEffectForEvent(attack(UnitId.fighter)), isNull);
    expect(combatEffectForEvent(null), isNull);
  });

  test('maps every emitted heal event to the healer heal treatment', () {
    const event = HealEvent(
      cycle: 1,
      tick: 1,
      target: 'ally',
      by: 'healer',
      amount: 10,
      targetHpAfter: 70,
    );

    expect(combatEffectForEvent(event), CombatEffectKind.healerHeal);
  });
}
