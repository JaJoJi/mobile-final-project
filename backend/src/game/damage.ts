import { REVIVE_HP_FRACTION } from './constants';
import { CombatEvent, UnitInstance } from './types';

/**
 * `applyDamage` — `docs/05-combat-spec.md §3`.
 *
 * Event order matches the spec pseudocode exactly:
 *   - lethal hit on a Tank 1★/2★ that has not revived this battle →
 *     emit `revive` only, and return (the Tank did NOT die).
 *   - otherwise subtract HP; if it reaches 0, mark dead and emit `death`
 *     BEFORE the `attack` event; always emit `attack` last.
 *
 * The revive handler runs in-tick; the cycle does not break.
 * Mutates `target` in place (HP / alive / revivedThisRound).
 */
export function applyDamage(
  target: UnitInstance,
  dmg: number,
  source: UnitInstance,
  cycle: number,
  tick: number,
  events: CombatEvent[],
): void {
  const lethal = dmg >= target.hp;

  if (
    lethal &&
    target.unitId === 'tank' &&
    target.star >= 1 &&
    !target.revivedThisRound
  ) {
    target.hp = Math.floor(target.maxHp * REVIVE_HP_FRACTION);
    target.revivedThisRound = true;
    events.push({
      type: 'revive',
      cycle,
      tick,
      unit: target.instanceId,
      hpAfter: target.hp,
      unitSide: target.side,
      unitSlot: target.slot,
      unitUnitId: target.unitId,
      unitStar: target.star,
    });
    return;
  }

  target.hp -= dmg;
  if (target.hp <= 0) {
    target.hp = 0;
    target.alive = false;
    events.push({
      type: 'death',
      cycle,
      tick,
      unit: target.instanceId,
      unitSide: target.side,
      unitSlot: target.slot,
      unitUnitId: target.unitId,
      unitStar: target.star,
    });
  }

  events.push({
    type: 'attack',
    cycle,
    tick,
    attacker: source.instanceId,
    target: target.instanceId,
    damage: dmg,
    targetHpAfter: target.hp,
    attackerSide: source.side,
    attackerSlot: source.slot,
    attackerUnitId: source.unitId,
    attackerStar: source.star,
    targetSide: target.side,
    targetSlot: target.slot,
    targetUnitId: target.unitId,
    targetStar: target.star,
  });
}
