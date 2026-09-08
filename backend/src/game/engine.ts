import {
  applyHealerSupport,
  applyLifesteal,
  applyPierce,
  applySlow,
  clearHealerSlows,
} from './abilities';
import { MAX_CYCLES, TICKS_PER_CYCLE, actsOnTick, atkFor, spdFor } from './constants';
import { applyDamage } from './damage';
import { pickTarget } from './targeting';
import {
  BattleSim,
  BattleState,
  CombatEvent,
  Side,
  UnitInstance,
} from './types';
import { makeRng } from './seeded-rng';

/**
 * `runBattle` — the Cycle Processor (`docs/05-combat-spec.md §1`).
 *
 * Pure + synchronous + deterministic: no I/O, no `Date`, no `Math.random`.
 * The only randomness is one seeded coin flip for the per-round tie-tick
 * "init side" (`§6`). Same `BattleState` (same unit data + same
 * `roundSeed`) ⇒ byte-identical `CombatEvent[]`.
 *
 * The caller's `UnitInstance` objects are NOT mutated — the engine clones
 * them on entry, so re-running with the very same input yields the same
 * output.
 *
 * Structure: ≤ 30 cycles × 100 ticks. Each tick, units whose cooldown
 * lands on that tick act, ordered per `§6`. A wipe is checked at the end
 * of each cycle (`§1.3`); cycle 30 always ends the battle.
 */
export function runBattle(state: BattleState): CombatEvent[] {
  const sim: BattleSim = {
    p1Units: state.p1Units.map(cloneUnit),
    p2Units: state.p2Units.map(cloneUnit),
  };

  const rng = state.rng ?? makeRng(state.roundSeed);
  const initSide: Side = rng() < 0.5 ? 'p1' : 'p2';

  const events: CombatEvent[] = [];

  for (let cycle = 1; cycle <= MAX_CYCLES; cycle++) {
    for (let tick = 1; tick <= TICKS_PER_CYCLE; tick++) {
      const acting = [...sim.p1Units, ...sim.p2Units].filter(
        (u) => u.alive && actsOnTick(currentSpd(u), tick),
      );
      orderForTick(acting, initSide);

      for (const unit of acting) {
        if (!unit.alive) continue; // killed earlier in this same tick
        unitAct(unit, sim, cycle, tick, events);
      }
    }

    events.push({ type: 'cycle_end', cycle });

    const p1Alive = sim.p1Units.some((u) => u.alive);
    const p2Alive = sim.p2Units.some((u) => u.alive);
    if (!p1Alive || !p2Alive) {
      const winner: Side | null =
        !p1Alive && !p2Alive ? null : !p1Alive ? 'p2' : 'p1';
      events.push({ type: 'battle_end', cycle, winner });
      return events;
    }
  }

  events.push({ type: 'battle_end', cycle: MAX_CYCLES, winner: null });
  return events;
}

function cloneUnit(u: UnitInstance): UnitInstance {
  return {
    ...u,
    alive: u.alive ?? u.hp > 0,
    effectiveSpd: u.effectiveSpd ?? spdFor(u.unitId),
    revivedThisRound: u.revivedThisRound ?? false,
  };
}

const currentSpd = (u: UnitInstance): number => u.effectiveSpd ?? spdFor(u.unitId);

/**
 * Tie-tick ordering (`§6`): all `initSide` units first (then the other
 * side), each group ordered by higher SPD → row → col → instanceId.
 */
function orderForTick(units: UnitInstance[], initSide: Side): void {
  units.sort((a, b) => {
    if (a.side !== b.side) {
      if (a.side === initSide) return -1;
      if (b.side === initSide) return 1;
    }
    const sa = currentSpd(a);
    const sb = currentSpd(b);
    if (sa !== sb) return sb - sa;
    const ra = Math.floor(a.slot / 3);
    const rb = Math.floor(b.slot / 3);
    if (ra !== rb) return ra - rb;
    const ca = a.slot % 3;
    const cb = b.slot % 3;
    if (ca !== cb) return ca - cb;
    return a.instanceId.localeCompare(b.instanceId);
  });
}

function unitAct(
  unit: UnitInstance,
  sim: BattleSim,
  cycle: number,
  tick: number,
  events: CombatEvent[],
): void {
  switch (unit.unitId) {
    case 'fighter': {
      const target = pickTarget(unit, sim);
      if (!target) return;
      const dmg = atkFor('fighter', unit.star);
      applyDamage(target, dmg, unit, cycle, tick, events);
      if (dmg > 0 && unit.star >= 1) {
        applyLifesteal(unit, dmg, cycle, tick, events);
      }
      return;
    }

    case 'tank': {
      const target = pickTarget(unit, sim);
      if (!target) return;
      applyDamage(target, atkFor('tank', unit.star), unit, cycle, tick, events);
      return;
    }

    case 'ranger': {
      const target = pickTarget(unit, sim);
      if (!target) return;
      const dmg = atkFor('ranger', unit.star);
      applyDamage(target, dmg, unit, cycle, tick, events);
      if (unit.star === 1) {
        applyPierce(unit, target, dmg, sim, cycle, tick, events);
      }
      return;
    }

    case 'healer': {
      const target = pickTarget(unit, sim);
      let lastAttacked: UnitInstance | null = null;
      if (target) {
        // "When the Healer attacks, she resets the Slow on her tracked
        // targets" — clear first, then land the hit, then re-apply.
        clearHealerSlows(unit, sim);
        applyDamage(target, atkFor('healer', unit.star), unit, cycle, tick, events);
        lastAttacked = target;
      }
      applyHealerSupport(unit, sim, cycle, tick, events);
      if (unit.star >= 1 && lastAttacked) {
        applySlow(unit, lastAttacked, cycle, tick, events);
      }
      return;
    }
  }
}
