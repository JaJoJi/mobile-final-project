/// Maps server combat events to presentation-only VFX assets.
///
/// This layer never changes combat state. An effect exists only when the
/// server emitted the corresponding event.
library;

import '../../../shared/models/combat_event.dart';
import '../../../shared/models/unit.dart';

enum CombatEffectKind {
  rangerProjectile,
  healerAttackProjectile,
  healerHeal,
}

extension CombatEffectKindAsset on CombatEffectKind {
  String get assetPath => switch (this) {
        CombatEffectKind.rangerProjectile =>
          'assets/images/vfx/ranger_projectile.png',
        CombatEffectKind.healerAttackProjectile =>
          'assets/images/vfx/healer_attack_projectile.png',
        CombatEffectKind.healerHeal =>
          'assets/images/vfx/healer_heal_burst.png',
      };
}

const combatEffectAssetPaths = <String>[
  'assets/images/vfx/ranger_projectile.png',
  'assets/images/vfx/healer_attack_projectile.png',
  'assets/images/vfx/healer_heal_burst.png',
];

/// Returns the visual requested by [event], or `null` for events that do not
/// own one of these effects. In particular, no event means no VFX.
CombatEffectKind? combatEffectForEvent(CombatEvent? event) => switch (event) {
      AttackEvent(attackerUnitId: UnitId.ranger) =>
        CombatEffectKind.rangerProjectile,
      AttackEvent(attackerUnitId: UnitId.healer) =>
        CombatEffectKind.healerAttackProjectile,
      HealEvent() => CombatEffectKind.healerHeal,
      _ => null,
    };
