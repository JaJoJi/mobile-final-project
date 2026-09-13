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

/**
 * Lightweight snapshot of a unit's state at a specific point in the battle.
 * Sent with every combat event so the FE can render directly from the
 * snapshot without tracking state locally.
 */
export interface UnitSnapshot {
  instanceId: string;
  unitId: UnitId;
  star: Star;
  hp: number;
  maxHp: number;
  slot: number;
  side: Side;
  alive: boolean;
}

export function snapshotUnit(u: UnitInstance): UnitSnapshot {
  return {
    instanceId: u.instanceId,
    unitId: u.unitId,
    star: u.star,
    hp: u.hp,
    maxHp: u.maxHp,
    slot: u.slot,
    side: u.side,
    alive: u.alive,
  };
}

export function snapshotAllUnits(sim: BattleSim): UnitSnapshot[] {
  return [...sim.p1Units, ...sim.p2Units].map(snapshotUnit);
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

/**
 * Positional + identity fields attached to every event the FE animation
 * player needs. Optional on the type so older clients keep parsing older
 * payloads; the engine always populates them, so the FE can rely on them.
 *
 * `unitStates` carries the full board snapshot after this event, so the FE
 * can render directly from it without tracking state locally. This
 * eliminates phantom-unit bugs caused by client/server state divergence.
 */
export interface CombatEventActorFields {
  /** Owning side of the unit (`'p1' | 'p2'`). Lets the renderer anchor on
   *  the correct half of the board without an external lookup. */
  side?: Side;
  /** Row-major board slot 0..8. `row = slot ~/ 3`, `col = slot % 3`. */
  slot?: number;
  /** Archetype — required for picking the right sprite / animation. */
  unitId?: UnitId;
  /** Fusion tier 0|1|2 — picks the star overlay and any per-star VFX. */
  star?: Star;
  /** Full board snapshot after this event. FE renders from this. */
  unitStates?: UnitSnapshot[];
}

export type CombatEvent =
  | (CombatEventActorFields & {
      type: 'attack';
      cycle: number;
      tick: number;
      attacker: string;
      target: string;
      damage: number;
      targetHpAfter: number;
      attackerSide?: Side;
      attackerSlot?: number;
      attackerUnitId?: UnitId;
      attackerStar?: Star;
      targetSide?: Side;
      targetSlot?: number;
      targetUnitId?: UnitId;
      targetStar?: Star;
    })
  | (CombatEventActorFields & {
      type: 'death';
      cycle: number;
      tick: number;
      unit: string;
      unitSide?: Side;
      unitSlot?: number;
      unitUnitId?: UnitId;
      unitStar?: Star;
    })
  | (CombatEventActorFields & {
      type: 'revive';
      cycle: number;
      tick: number;
      unit: string;
      hpAfter: number;
      unitSide?: Side;
      unitSlot?: number;
      unitUnitId?: UnitId;
      unitStar?: Star;
    })
  | (CombatEventActorFields & {
      type: 'heal';
      cycle: number;
      tick: number;
      target: string;
      by: string;
      amount: number;
      targetHpAfter: number;
      targetSide?: Side;
      targetSlot?: number;
      targetUnitId?: UnitId;
      targetStar?: Star;
      bySide?: Side;
      bySlot?: number;
      byUnitId?: UnitId;
      byStar?: Star;
    })
  | (CombatEventActorFields & {
      type: 'lifesteal';
      cycle: number;
      tick: number;
      unit: string;
      amount: number;
      hpAfter: number;
      unitSide?: Side;
      unitSlot?: number;
      unitUnitId?: UnitId;
      unitStar?: Star;
    })
  | (CombatEventActorFields & {
      type: 'pierce';
      cycle: number;
      tick: number;
      attacker: string;
      target: string;
      damage: number;
      attackerSide?: Side;
      attackerSlot?: number;
      attackerUnitId?: UnitId;
      attackerStar?: Star;
      targetSide?: Side;
      targetSlot?: number;
      targetUnitId?: UnitId;
      targetStar?: Star;
    })
  | (CombatEventActorFields & {
      type: 'slow';
      cycle: number;
      tick: number;
      target: string;
      by: string;
      targetSide?: Side;
      targetSlot?: number;
      targetUnitId?: UnitId;
      targetStar?: Star;
      bySide?: Side;
      bySlot?: number;
      byUnitId?: UnitId;
      byStar?: Star;
    })
  | (CombatEventActorFields & { type: 'cycle_end'; cycle: number })
  | (CombatEventActorFields & { type: 'battle_end'; cycle: number; winner: Side | null });

export const enemySideOf = (side: Side): Side => (side === 'p1' ? 'p2' : 'p1');

export const unitsOf = (sim: BattleSim, side: Side): UnitInstance[] =>
  side === 'p1' ? sim.p1Units : sim.p2Units;
