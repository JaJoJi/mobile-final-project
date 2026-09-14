import type { Star, UnitId } from './types';

/**
 * MVP unit stats — `docs/01-game-design.md §3`.
 *
 *   | Unit    | HP  | ATK | SPD |
 *   | fighter | 100 | 15  | 20  |
 *   | healer  | 70  | 6   | 50  |
 *   | ranger  | 60  | 12  | 67  |
 *   | tank    | 150 | 8   | 0   |
 *
 * HP is not read from here at runtime — the orchestrator (P0-BE-13) puts
 * the resolved `hp` / `maxHp` on each `UnitInstance`. ATK + SPD are looked
 * up here by `unitId`.
 */
export interface UnitBaseStats {
  hp: number;
  atk: number;
  spd: number;
}

export const UNIT_BASE_STATS: Record<UnitId, UnitBaseStats> = {
  fighter: { hp: 100, atk: 15, spd: 20 },
  healer: { hp: 70, atk: 6, spd: 50 },
  ranger: { hp: 60, atk: 12, spd: 67 },
  tank: { hp: 150, atk: 8, spd: 0 },
};

export const MAX_CYCLES = 30;
export const TICKS_PER_CYCLE = 100;

/** Slow: `effectiveSpd = round(baseSpd * 0.7)`, clamped ≥ 0 (`docs/05 §4.4`). */
export const SLOW_MULTIPLIER = 0.7;

/** Fighter Lifesteal fraction of damage dealt, by star (`docs/05 §4.1`). */
export const LIFESTEAL_RATE: Record<Star, number> = { 0: 0, 1: 0.05, 2: 0.1 };

/** Ranger 1★ Pierce fraction of primary damage (`docs/05 §4.2`). */
export const PIERCE_RATE = 0.1;

/** Healer flat heal per target (`docs/05 §4.4`). */
export const HEAL_AMOUNT = 10;

/** Tank Revive restores this fraction of maxHp (`docs/05 §3`). */
export const REVIVE_HP_FRACTION = 0.5;

/**
 * Star ATK scaling — **MVP assumption**. `docs/01 §3.3` says star level
 * "affects stats" but gives no numbers ("tune via playtest"). We scale
 * ATK ×1 / ×1.5 / ×2 for 0★ / 1★ / 2★. SPD is deliberately NOT scaled:
 * ranger's base SPD is 90 and `docs/05 §1.1` forbids SPD > 95.
 */
export function atkFor(unitId: UnitId, star: Star): number {
  const mult = star === 2 ? 2 : star === 1 ? 1.5 : 1;
  return Math.floor(UNIT_BASE_STATS[unitId].atk * mult);
}

/**
 * SPD is an *actions per cycle* dial, not a linear stat: a unit acts every
 * `100 - spd` ticks, so the top of the range is extremely steep. At the
 * MVP's original SPD 90 a ranger acted ten times a cycle for 12 damage —
 * 120 damage per cycle against a fighter's 15 — and two of them wiped a
 * whole starting board before the first `cycle_end`. Real matches ended at
 * `battle_end` cycle 1 with the winner's units barely scratched, which is
 * nothing for the client to replay, and a match was over in about six
 * near-instant rounds.
 *
 * SPD 67 puts the ranger at 3 actions per cycle (36 damage), still the
 * highest output on the board and still a 60 HP glass cannon, but battles
 * now run the several cycles the replay is built to show. Per
 * `docs/05 §1.1` these are playtest-tuned placeholders; keep the
 * actions/cycle column in that table in step with any change here.
 */
export function spdFor(unitId: UnitId): number {
  return UNIT_BASE_STATS[unitId].spd;
}

/**
 * Ticks in a cycle at which a unit with the given SPD acts.
 * `cooldown = 100 - spd`; the unit acts every `cooldown` ticks, i.e. at
 * ticks where `tick % cooldown === 0` → `floor(100 / cooldown)` actions
 * per cycle, matching the table in `docs/05 §1.1`.
 */
export function actsOnTick(spd: number, tick: number): boolean {
  const cooldown = TICKS_PER_CYCLE - spd;
  if (cooldown <= 0) return tick === TICKS_PER_CYCLE; // SPD ≥ 100 is forbidden; guard anyway
  return tick % cooldown === 0;
}
