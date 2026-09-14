/**
 * Test helpers for constructing 3×3-board battle states (P3-BE-01).
 *
 * `slot = row * 3 + col`, so:
 *   0 1 2   ← row 0 (front)
 *   3 4 5   ← row 1 (middle)
 *   6 7 8   ← row 2 (back)
 */
import { spdFor } from '../constants';
import type {
  BattleSim,
  BattleState,
  Side,
  Star,
  UnitId,
  UnitInstance,
} from '../types';

let seq = 0;

export interface MakeUnitInput {
  unitId: UnitId;
  star?: Star;
  slot: number;
  side?: Side;
  hp?: number;
  maxHp?: number;
  id?: string;
}

export function makeUnit(input: MakeUnitInput): UnitInstance {
  const maxHp = input.maxHp ?? input.hp ?? 100;
  const hp = input.hp ?? maxHp;
  const side = input.side ?? 'p1';
  const unitId = input.unitId;
  return {
    instanceId: input.id ?? `${side}-${unitId}-${(++seq).toString().padStart(3, '0')}`,
    unitId,
    star: input.star ?? 0,
    hp,
    maxHp,
    slot: input.slot,
    side,
    alive: hp > 0,
    revivedThisRound: false,
    effectiveSpd: spdFor(unitId),
  };
}

/** Reset the instanceId counter so a golden fixture stays reproducible. */
export function resetIds(): void {
  seq = 0;
}

export function makeBattleState(opts: {
  p1Units: UnitInstance[];
  p2Units: UnitInstance[];
  roundSeed?: number;
  matchSeed?: string;
  rng?: () => number;
}): BattleState {
  return {
    p1Units: opts.p1Units,
    p2Units: opts.p2Units,
    roundSeed: opts.roundSeed ?? 1,
    matchSeed: opts.matchSeed ?? 'test-match',
    rng: opts.rng,
  };
}

/** A plain sim view for exercising targeting / ability helpers directly. */
export function makeSim(
  p1Units: UnitInstance[],
  p2Units: UnitInstance[],
): BattleSim {
  return { p1Units, p2Units };
}

/** Every event of a given type, in order. */
export function eventsOfType<T extends { type: string }>(
  events: T[],
  type: T['type'],
): T[] {
  return events.filter((e) => e.type === type);
}
