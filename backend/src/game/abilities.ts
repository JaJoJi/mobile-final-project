import {
  HEAL_AMOUNT,
  LIFESTEAL_RATE,
  PIERCE_RATE,
  SLOW_MULTIPLIER,
  spdFor,
} from './constants';
import {
  BattleSim,
  CombatEvent,
  UnitInstance,
  enemySideOf,
  unitsOf,
} from './types';

/**
 * Ability effects — `docs/05-combat-spec.md §4`.
 * Each helper is called by the engine AFTER the primary `applyDamage`.
 */

/** Fighter 1★/2★ Lifesteal (`§4.1`). Emitted on every attack with `dmg > 0`. */
export function applyLifesteal(
  fighter: UnitInstance,
  dmg: number,
  cycle: number,
  tick: number,
  events: CombatEvent[],
): void {
  const raw = Math.floor(dmg * LIFESTEAL_RATE[fighter.star]);
  const heal = Math.max(0, Math.min(raw, fighter.maxHp - fighter.hp));
  fighter.hp += heal;
  events.push({
    type: 'lifesteal',
    cycle,
    tick,
    unit: fighter.instanceId,
    amount: heal,
    hpAfter: fighter.hp,
  });
}

/**
 * Ranger 1★ Pierce (`§4.2`). 10% of the primary damage spills to the alive
 * enemy DIRECTLY behind the primary target — same column, `row + 1` only.
 * Never skips rows; if that exact slot is empty or dead, no event.
 */
export function applyPierce(
  ranger: UnitInstance,
  primaryTarget: UnitInstance,
  primaryDamage: number,
  sim: BattleSim,
  cycle: number,
  tick: number,
  events: CombatEvent[],
): void {
  const behindRow = Math.floor(primaryTarget.slot / 3) + 1;
  if (behindRow > 2) return;
  const col = primaryTarget.slot % 3;

  const behind = unitsOf(sim, enemySideOf(ranger.side)).find(
    (u) => u.alive && u.slot % 3 === col && Math.floor(u.slot / 3) === behindRow,
  );
  if (!behind) return;

  const dmg = Math.floor(primaryDamage * PIERCE_RATE);
  behind.hp = Math.max(0, behind.hp - dmg);
  events.push({
    type: 'pierce',
    cycle,
    tick,
    attacker: ranger.instanceId,
    target: behind.instanceId,
    damage: dmg,
  });

  if (behind.hp === 0 && behind.alive) {
    behind.alive = false;
    events.push({ type: 'death', cycle, tick, unit: behind.instanceId });
  }
}

/**
 * Healer support (`§4.4`). Runs every time the Healer acts, even if she had
 * no attack target (`E1`). Heals the lowest-HP alive ally (any lane, may be
 * self); a 2★ Healer also heals the next-lowest. No event when the heal
 * would be 0 (`E13`).
 */
export function applyHealerSupport(
  healer: UnitInstance,
  sim: BattleSim,
  cycle: number,
  tick: number,
  events: CombatEvent[],
): void {
  const allies = unitsOf(sim, healer.side);
  const first = lowestHpAlly(allies, null);
  if (first) healOne(first, healer, cycle, tick, events);
  if (healer.star === 2) {
    const second = lowestHpAlly(allies, first);
    if (second) healOne(second, healer, cycle, tick, events);
  }
}

/**
 * Healer 1★+ Slow (`§4.4`). Sets the last-attacked enemy's `effectiveSpd`
 * to `round(baseSpd * 0.7)` (clamped ≥ 0) until this Healer acts again.
 */
export function applySlow(
  healer: UnitInstance,
  target: UnitInstance,
  cycle: number,
  tick: number,
  events: CombatEvent[],
): void {
  target.effectiveSpd = Math.max(
    0,
    Math.round(spdFor(target.unitId) * SLOW_MULTIPLIER),
  );
  target.slowActive = true;
  target.slowUntilHealerAct = healer.instanceId;
  events.push({ type: 'slow', cycle, tick, target: target.instanceId, by: healer.instanceId });
}

/**
 * Clear every Slow this Healer applied — restore `effectiveSpd` to base.
 * Called when the Healer acts again (`§4.4` implementation note).
 */
export function clearHealerSlows(healer: UnitInstance, sim: BattleSim): void {
  for (const u of [...sim.p1Units, ...sim.p2Units]) {
    if (u.slowUntilHealerAct === healer.instanceId) {
      u.effectiveSpd = spdFor(u.unitId);
      u.slowActive = false;
      u.slowUntilHealerAct = undefined;
    }
  }
}

function healOne(
  target: UnitInstance,
  healer: UnitInstance,
  cycle: number,
  tick: number,
  events: CombatEvent[],
): void {
  const amount = Math.min(HEAL_AMOUNT, target.maxHp - target.hp);
  if (amount <= 0) return;
  target.hp += amount;
  events.push({
    type: 'heal',
    cycle,
    tick,
    target: target.instanceId,
    by: healer.instanceId,
    amount,
    targetHpAfter: target.hp,
  });
}

/** Lowest-HP alive ally; ties broken by instanceId. `exclude` is skipped. */
function lowestHpAlly(
  allies: UnitInstance[],
  exclude: UnitInstance | null,
): UnitInstance | null {
  const pool = allies.filter((u) => u.alive && u !== exclude);
  if (pool.length === 0) return null;
  return pool.reduce((a, b) => {
    if (b.hp !== a.hp) return b.hp < a.hp ? b : a;
    return b.instanceId.localeCompare(a.instanceId) < 0 ? b : a;
  });
}
