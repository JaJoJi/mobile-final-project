/**
 * Smoke harness for P0-BE-09 (combat engine).
 *
 * Pure — no Redis / DB / socket. Runs `runBattle` over a few crafted
 * boards and asserts the ticket's "Done when" items that don't need the
 * full P3-BE-01 spec suite:
 *   - determinism: same input (and a fresh copy of it) → identical events
 *   - terminates: ≤ 30 cycles, last event is `battle_end`
 *   - performance: < 500 ms for a full 9v9
 *   - no `Math.random` / `Date` in backend/src/game
 *   - targeted checks: tank revive, fighter lifesteal, ranger pierce
 *     (adjacent row only), healer slow
 *
 * Run:
 *   cd backend && npx ts-node -T src/game/engine.smoke.ts
 */
import { readFileSync, readdirSync } from 'fs';
import { join } from 'path';
import { runBattle } from './engine';
import { BattleState, CombatEvent, Star, UnitId, UnitInstance } from './types';

let failures = 0;
function check(name: string, ok: boolean, extra = ''): void {
  console.log(`  ${ok ? 'OK  ' : 'FAIL'} ${name}${extra ? '  — ' + extra : ''}`);
  if (!ok) failures++;
}

let seq = 0;
function unit(
  side: 'p1' | 'p2',
  unitId: UnitId,
  star: Star,
  slot: number,
  hp: number,
  maxHp: number,
): UnitInstance {
  seq++;
  return {
    instanceId: `${side}-${unitId}-${String(seq).padStart(2, '0')}`,
    unitId,
    star,
    hp,
    maxHp,
    slot,
    side,
    alive: true,
  };
}

function state(p1Units: UnitInstance[], p2Units: UnitInstance[], roundSeed = 42): BattleState {
  return { p1Units, p2Units, roundSeed, matchSeed: 'smoke-match-seed' };
}

/** Deep structural clone so a re-run can't share mutable unit objects. */
const clone = <T>(v: T): T => JSON.parse(JSON.stringify(v));

function typeCounts(events: CombatEvent[]): Record<string, number> {
  const out: Record<string, number> = {};
  for (const e of events) out[e.type] = (out[e.type] ?? 0) + 1;
  return out;
}

// ---------------------------------------------------------------------------

function fullBoard(side: 'p1' | 'p2'): UnitInstance[] {
  // front: 3 fighters | middle: ranger, healer, ranger | back: tank, tank, fighter
  return [
    unit(side, 'fighter', 1, 0, 100, 100),
    unit(side, 'fighter', 0, 1, 100, 100),
    unit(side, 'fighter', 2, 2, 100, 100),
    unit(side, 'ranger', 1, 3, 60, 60),
    unit(side, 'healer', 1, 4, 70, 70),
    unit(side, 'ranger', 2, 5, 60, 60),
    unit(side, 'tank', 1, 6, 150, 150),
    unit(side, 'tank', 0, 7, 150, 150),
    unit(side, 'fighter', 0, 8, 100, 100),
  ];
}

function testDeterminismAndTermination(): void {
  console.log('\n[full 9v9 — determinism + termination]');
  const base = state(fullBoard('p1'), fullBoard('p2'));

  const t0 = Date.now();
  const a = runBattle(base);
  const ms = Date.now() - t0;

  const b = runBattle(base); // same object — engine must not have mutated it
  const c = runBattle(clone(base)); // structurally identical, different identity

  check('run A produced events', a.length > 0, `${a.length} events`);
  check('A === B (input not mutated between runs)', JSON.stringify(a) === JSON.stringify(b));
  check('A === C (fresh structural copy)', JSON.stringify(a) === JSON.stringify(c));

  const last = a[a.length - 1];
  check('last event is battle_end', last?.type === 'battle_end', last?.type);
  check(
    'battle_end.cycle within 1..30',
    last?.type === 'battle_end' && last.cycle >= 1 && last.cycle <= 30,
    last?.type === 'battle_end' ? `cycle ${last.cycle}` : '',
  );

  const cycleEnds = a.filter((e) => e.type === 'cycle_end').length;
  check('cycle_end count ≤ 30', cycleEnds <= 30, `${cycleEnds}`);
  check(
    'no event past battle_end.cycle',
    a.every((e) => !('cycle' in e) || e.type === 'battle_end' || e.cycle <= (last as { cycle: number }).cycle),
  );
  check(
    'every tick in 1..100, every cycle in 1..30',
    a.every(
      (e) =>
        !('tick' in e) ||
        (Number.isInteger(e.tick) && e.tick >= 1 && e.tick <= 100 && e.cycle >= 1 && e.cycle <= 30),
    ),
  );
  check('performance < 500 ms', ms < 500, `${ms} ms`);
  console.log('  counts:', typeCounts(a));
}

function testTankRevive(): void {
  console.log('\n[tank revive — lethal hit on Tank 1★ revives once]');
  const ranger = unit('p1', 'ranger', 2, 0, 60, 60); // atk 24, global target
  const tank = unit('p2', 'tank', 1, 0, 20, 150); // low hp, will take a lethal hit
  const events = runBattle(state([ranger], [tank]));

  const revives = events.filter((e) => e.type === 'revive');
  check('exactly one revive event', revives.length === 1, `${revives.length}`);
  check(
    'revive restores floor(maxHp/2)',
    revives[0]?.type === 'revive' && revives[0].unit === tank.instanceId && revives[0].hpAfter === 75,
    revives[0]?.type === 'revive' ? `hpAfter ${revives[0].hpAfter}` : '',
  );
  check('tank still dies eventually', events.some((e) => e.type === 'death'));
}

function testFighterLifesteal(): void {
  console.log('\n[fighter lifesteal — 1★ heals floor(dmg * 0.05)]');
  const fighter = unit('p1', 'fighter', 1, 0, 50, 100); // atk floor(15*1.5)=22, wounded
  const dummy = unit('p2', 'tank', 0, 0, 999, 999); // soaks hits, never revives
  const events = runBattle(state([fighter], [dummy]));

  const ls = events.filter((e) => e.type === 'lifesteal');
  check('lifesteal events emitted', ls.length > 0, `${ls.length}`);
  check(
    'lifesteal amount == floor(22 * 0.05) == 1',
    ls.every((e) => e.type === 'lifesteal' && e.amount === 1),
  );
  check(
    'fighter never exceeds maxHp',
    ls.every((e) => e.type === 'lifesteal' && e.hpAfter <= fighter.maxHp),
  );
}

function testRangerPierceAdjacentOnly(): void {
  console.log('\n[ranger pierce — hits row+1 only, never skips a row]');

  // Primary target front (row 0). A unit sits at row 2 (back), row 1 empty.
  const ranger = unit('p1', 'ranger', 1, 0, 60, 60); // lane col 0
  const front = unit('p2', 'fighter', 0, 0, 999, 999); // p2 slot 0 → row0 col0
  const back = unit('p2', 'fighter', 0, 6, 999, 999); // p2 slot 6 → row2 col0
  const skipEvents = runBattle(state([ranger], [front, back]));
  check(
    'no pierce when only row+2 is occupied',
    !skipEvents.some((e) => e.type === 'pierce'),
  );

  // Now put a unit directly behind (row 1).
  seq = 0;
  const ranger2 = unit('p1', 'ranger', 1, 0, 60, 60);
  const front2 = unit('p2', 'fighter', 0, 0, 999, 999); // row0 col0
  const behind2 = unit('p2', 'fighter', 0, 3, 999, 999); // row1 col0 — adjacent
  const hitEvents = runBattle(state([ranger2], [front2, behind2]));
  const pierces = hitEvents.filter((e) => e.type === 'pierce');
  check('pierce fires when row+1 is occupied', pierces.length > 0, `${pierces.length}`);
  check(
    'pierce target is the adjacent-row unit',
    pierces.every((e) => e.type === 'pierce' && e.target === behind2.instanceId),
  );
  check(
    'pierce damage == floor(18 * 0.10) == 1',
    pierces.every((e) => e.type === 'pierce' && e.damage === 1),
  );
}

function testHealerSlow(): void {
  console.log('\n[healer slow — 1★ slows last-attacked enemy]');
  const healer = unit('p1', 'healer', 1, 0, 70, 70);
  const enemy = unit('p2', 'fighter', 0, 0, 999, 999);
  const events = runBattle(state([healer], [enemy]));

  const slows = events.filter((e) => e.type === 'slow');
  check('slow events emitted', slows.length > 0, `${slows.length}`);
  check(
    'slow target is the attacked enemy, by the healer',
    slows.every((e) => e.type === 'slow' && e.target === enemy.instanceId && e.by === healer.instanceId),
  );
  check('healer heals itself while attacking', events.some((e) => e.type === 'heal'));
}

function testNoNondeterminismInSource(): void {
  console.log('\n[source scan — no Math.random / Date in backend/src/game]');
  const dir = __dirname;
  const offenders: string[] = [];
  const stripComments = (s: string): string =>
    s.replace(/\/\*[\s\S]*?\*\//g, '').replace(/\/\/[^\n]*/g, '');
  for (const f of readdirSync(dir)) {
    if (!f.endsWith('.ts') || f.endsWith('.smoke.ts')) continue;
    const src = stripComments(readFileSync(join(dir, f), 'utf8'));
    if (/Math\s*\.\s*random\s*\(/.test(src)) offenders.push(`${f}: Math.random()`);
    if (/\bDate\s*\.\s*now\s*\(/.test(src)) offenders.push(`${f}: Date.now()`);
    if (/new\s+Date\b/.test(src)) offenders.push(`${f}: new Date`);
  }
  check('no forbidden non-deterministic calls', offenders.length === 0, offenders.join('; '));
}

function testEmptyBoards(): void {
  console.log('\n[edge — empty boards / one-sided]');
  const bothEmpty = runBattle(state([], []));
  const be = bothEmpty[bothEmpty.length - 1];
  check('both empty → tie in cycle 1', be?.type === 'battle_end' && be.winner === null && be.cycle === 1);

  seq = 0;
  const oneSide = runBattle(state([unit('p1', 'fighter', 0, 0, 100, 100)], []));
  const os = oneSide[oneSide.length - 1];
  check('p2 empty → winner p1 in cycle 1', os?.type === 'battle_end' && os.winner === 'p1' && os.cycle === 1);
}

// ---------------------------------------------------------------------------

testDeterminismAndTermination();
testTankRevive();
testFighterLifesteal();
testRangerPierceAdjacentOnly();
testHealerSlow();
testEmptyBoards();
testNoNondeterminismInSource();

if (failures > 0) {
  console.error(`\n[FAIL] ${failures} smoke check(s) failed`);
  process.exit(1);
}
console.log('\n[OK] all combat-engine smoke checks passed');
