/**
 * Combat engine types. Frozen against `docs/05-combat-spec.md` +
 * `docs/01-game-design.md §2–3`.
 *
 * Board geometry (3×3 per player, locked):
 *   slot 0..8, row-major   →   row = floor(slot / 3), col = slot % 3
 *   row 0 = front (closest to enemy), row 1 = middle, row 2 = back
 *   "lane" = col.
 */

export type Star = 0 | 1 | 2;
export type UnitId = 'fighter' | 'healer' | 'ranger' | 'tank';
export type Side = 'p1' | 'p2';

export interface Position {
  row: 0 | 1 | 2;
  col: 0 | 1 | 2;
}

export function slotToPosition(slot: number): Position {
  return { row: Math.floor(slot / 3) as 0 | 1 | 2, col: (slot % 3) as 0 | 1 | 2 };
}

export interface UnitInstance {
  instanceId: string;
  unitId: UnitId;
  star: Star;
  hp: number;
  maxHp: number;
  /** 0..8, row-major. */
  slot: number;
  side: Side;
  alive: boolean;
  /** Tank 1★/2★ Revive — one revive per battle (`docs/05 §3`). */
  revivedThisRound?: boolean;
  /** Healer Slow bookkeeping (`docs/05 §4.4`). */
  slowActive?: boolean;
  slowUntilHealerAct?: string;
  /** Current SPD after Slow; defaults to the unit's base SPD. */
  effectiveSpd?: number;
}

export interface BattleState {
  p1Units: UnitInstance[];
  p2Units: UnitInstance[];
  /** `matchSeed + round` — seeds the tie-tick init draw (`docs/05 §6`). */
  roundSeed: number;
  matchSeed: string;
  /** Optional pre-built RNG; engine falls back to `makeRng(roundSeed)`. */
  rng?: () => number;
}

/** Read-only view the targeting / ability helpers operate on. */
export interface BattleSim {
  p1Units: UnitInstance[];
  p2Units: UnitInstance[];
}

export type CombatEvent =
  | { type: 'attack'; cycle: number; tick: number; attacker: string; target: string; damage: number; targetHpAfter: number }
  | { type: 'death'; cycle: number; tick: number; unit: string }
  | { type: 'revive'; cycle: number; tick: number; unit: string; hpAfter: number }
  | { type: 'heal'; cycle: number; tick: number; target: string; by: string; amount: number; targetHpAfter: number }
  | { type: 'lifesteal'; cycle: number; tick: number; unit: string; amount: number; hpAfter: number }
  | { type: 'pierce'; cycle: number; tick: number; attacker: string; target: string; damage: number }
  | { type: 'slow'; cycle: number; tick: number; target: string; by: string }
  | { type: 'cycle_end'; cycle: number }
  | { type: 'battle_end'; cycle: number; winner: Side | null };

export const enemySideOf = (side: Side): Side => (side === 'p1' ? 'p2' : 'p1');

export const unitsOf = (sim: BattleSim, side: Side): UnitInstance[] =>
  side === 'p1' ? sim.p1Units : sim.p2Units;
