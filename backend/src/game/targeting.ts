import {
  BattleSim,
  UnitInstance,
  enemySideOf,
  unitsOf,
} from './types';

/**
 * `pickTarget` — `docs/05-combat-spec.md §2`.
 *
 * Order of rules:
 *   1. No alive enemies → `null` (caller skips the attack).
 *   2. Ranger 2★ → global lowest-HP enemy (ignores lanes).
 *   3. Fighter / Tank / Healer, when an alive enemy 2★ Tank exists →
 *      that Tank (Prioritize overlay).
 *   4. Base rule: same lane (col), prefer front row → middle → back.
 *   5. Still nothing → fall back across lanes col 0→1→2, front→middle→back.
 *   6. Tie-break within candidates:
 *        - ranger 0★/1★: lowest current HP
 *        - everyone else: lowest col, then lowest row, then lowest instanceId
 */
export function pickTarget(
  attacker: UnitInstance,
  sim: BattleSim,
): UnitInstance | null {
  const enemies = unitsOf(sim, enemySideOf(attacker.side)).filter((u) => u.alive);
  if (enemies.length === 0) return null;

  // 2★ global rules first.
  if (attacker.unitId === 'ranger' && attacker.star === 2) {
    return lowestHp(enemies);
  }

  // Tank 2★ Prioritize — only fighter / tank / healer attackers are steered.
  if (
    attacker.unitId === 'fighter' ||
    attacker.unitId === 'tank' ||
    attacker.unitId === 'healer'
  ) {
    const tank2 = enemies.find((e) => e.unitId === 'tank' && e.star === 2);
    if (tank2) return tank2;
  }

  const attackerCol = attacker.slot % 3;
  const sameLane = enemies.filter((e) => e.slot % 3 === attackerCol);

  let candidates = firstNonEmptyRow(sameLane);

  if (candidates.length === 0) {
    for (const col of [0, 1, 2] as const) {
      const laneCandidates = firstNonEmptyRow(
        enemies.filter((e) => e.slot % 3 === col),
      );
      if (laneCandidates.length > 0) {
        candidates = laneCandidates;
        break;
      }
    }
  }

  if (candidates.length === 0) return null; // unreachable (enemies non-empty), keeps TS happy

  if (attacker.unitId === 'ranger') {
    return lowestHp(candidates);
  }
  return byPositionThenId(candidates)[0];
}

/** Among a lane's units, the front row if any, else middle, else back. */
function firstNonEmptyRow(laneUnits: UnitInstance[]): UnitInstance[] {
  for (const row of [0, 1, 2] as const) {
    const inRow = laneUnits.filter((u) => Math.floor(u.slot / 3) === row);
    if (inRow.length > 0) return inRow;
  }
  return [];
}

/** Lowest HP; ties broken by lowest col, then row, then instanceId. */
function lowestHp(units: UnitInstance[]): UnitInstance {
  return byPositionThenId(units).reduce((a, b) => (b.hp < a.hp ? b : a));
}

/** Sort a copy by: col asc, row asc, instanceId asc. */
function byPositionThenId(units: UnitInstance[]): UnitInstance[] {
  return [...units].sort((a, b) => {
    const ca = a.slot % 3;
    const cb = b.slot % 3;
    if (ca !== cb) return ca - cb;
    const ra = Math.floor(a.slot / 3);
    const rb = Math.floor(b.slot / 3);
    if (ra !== rb) return ra - rb;
    return a.instanceId.localeCompare(b.instanceId);
  });
}
