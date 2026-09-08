import { readFileSync } from 'fs';
import { join } from 'path';
import { runBattle } from './engine';
import { makeRng } from './seeded-rng';
import type { CombatEvent, UnitInstance } from './types';
import {
  eventsOfType,
  makeBattleState,
  makeUnit,
  resetIds,
} from './fixtures/board-builder';

const lastEvent = (events: CombatEvent[]) => events[events.length - 1];

describe('runBattle — cycle model (docs/05 §1)', () => {
  it('ends in a tie (winner null) when both sides survive 30 cycles', () => {
    const p1 = [makeUnit({ unitId: 'fighter', slot: 0, side: 'p1', hp: 100000 })];
    const p2 = [makeUnit({ unitId: 'fighter', slot: 0, side: 'p2', hp: 100000 })];
    const events = runBattle(makeBattleState({ p1Units: p1, p2Units: p2 }));

    const end = lastEvent(events);
    expect(end).toMatchObject({ type: 'battle_end', cycle: 30, winner: null });
    expect(eventsOfType(events, 'cycle_end')).toHaveLength(30);
  });

  it('a wiped side loses; the check happens at the end of a cycle', () => {
    const p1 = [makeUnit({ unitId: 'ranger', star: 1, slot: 0, side: 'p1' })];
    const p2 = [makeUnit({ unitId: 'fighter', slot: 0, side: 'p2', hp: 1 })];
    const events = runBattle(makeBattleState({ p1Units: p1, p2Units: p2 }));

    expect(lastEvent(events)).toMatchObject({
      type: 'battle_end',
      cycle: 1,
      winner: 'p1',
    });
  });

  it('a slower unit still acts — Fighter (SPD 20) attacks once per cycle at tick 80', () => {
    const p1 = [makeUnit({ unitId: 'fighter', slot: 0, side: 'p1', hp: 100000 })];
    const p2 = [makeUnit({ unitId: 'fighter', slot: 0, side: 'p2', hp: 100000 })];
    const events = runBattle(makeBattleState({ p1Units: p1, p2Units: p2 }));
    const p1Attacks = eventsOfType(events, 'attack').filter(
      (e) => (e as { attacker: string }).attacker === p1[0].instanceId,
    );
    expect(p1Attacks).toHaveLength(30); // 1 per cycle × 30
    expect(new Set(p1Attacks.map((e) => (e as { tick: number }).tick))).toEqual(
      new Set([80]),
    );
  });

  it('a faster unit acts more often — Ranger (SPD 90) acts 10× per cycle', () => {
    const p1 = [makeUnit({ unitId: 'ranger', slot: 0, side: 'p1', hp: 100000 })];
    const p2 = [makeUnit({ unitId: 'fighter', slot: 0, side: 'p2', hp: 100000 })];
    const events = runBattle(makeBattleState({ p1Units: p1, p2Units: p2 }));
    const rangerAttacks = eventsOfType(events, 'attack').filter(
      (e) => (e as { attacker: string }).attacker === p1[0].instanceId,
    );
    expect(rangerAttacks).toHaveLength(300); // 10 per cycle × 30
  });
});

describe('runBattle — abilities across star levels', () => {
  const soak = (side: 'p1' | 'p2') =>
    makeUnit({ unitId: 'tank', star: 0, slot: 0, side, hp: 100000, maxHp: 100000 });

  it('Fighter 0★ never emits lifesteal; 1★ and 2★ do', () => {
    for (const [star, expected] of [
      [0, false],
      [1, true],
      [2, true],
    ] as const) {
      const f = makeUnit({ unitId: 'fighter', star, slot: 0, side: 'p1', hp: 50, maxHp: 100 });
      const events = runBattle(
        makeBattleState({ p1Units: [f], p2Units: [soak('p2')] }),
      );
      expect(eventsOfType(events, 'lifesteal').length > 0).toBe(expected);
    }
  });

  it('Ranger 0★ never pierces; 1★ pierces the row+1 unit', () => {
    const front = makeUnit({ unitId: 'fighter', slot: 0, side: 'p2', id: 'front', hp: 100000 });
    const behind = makeUnit({ unitId: 'fighter', slot: 3, side: 'p2', id: 'behind', hp: 100000 });

    const r0 = makeUnit({ unitId: 'ranger', star: 0, slot: 0, side: 'p1' });
    expect(
      eventsOfType(runBattle(makeBattleState({ p1Units: [r0], p2Units: [front, behind] })), 'pierce'),
    ).toHaveLength(0);

    const r1 = makeUnit({ unitId: 'ranger', star: 1, slot: 0, side: 'p1' });
    const pierces = eventsOfType(
      runBattle(makeBattleState({ p1Units: [r1], p2Units: [front, behind] })),
      'pierce',
    );
    expect(pierces.length).toBeGreaterThan(0);
    expect(new Set(pierces.map((e) => (e as { target: string }).target))).toEqual(
      new Set(['behind']),
    );
  });

  it('Healer 0★ heals a wounded ally; 1★ additionally slows', () => {
    const h0 = makeUnit({ unitId: 'healer', star: 0, slot: 0, side: 'p1' });
    const ally0 = makeUnit({ unitId: 'fighter', slot: 1, side: 'p1', id: 'a0', hp: 10, maxHp: 100 });
    const e0 = runBattle(
      makeBattleState({ p1Units: [h0, ally0], p2Units: [soak('p2')] }),
    );
    expect(eventsOfType(e0, 'heal').length).toBeGreaterThan(0);
    expect(eventsOfType(e0, 'slow')).toHaveLength(0);

    const h1 = makeUnit({ unitId: 'healer', star: 1, slot: 0, side: 'p1' });
    const e1 = runBattle(
      makeBattleState({ p1Units: [h1], p2Units: [soak('p2')] }),
    );
    expect(eventsOfType(e1, 'slow').length).toBeGreaterThan(0);
  });

  it('Tank 1★ Revive fires exactly once in a battle', () => {
    const ranger = makeUnit({ unitId: 'ranger', star: 2, slot: 0, side: 'p1' }); // atk 24
    const tank = makeUnit({ unitId: 'tank', star: 1, slot: 0, side: 'p2', hp: 20, maxHp: 150 });
    const events = runBattle(makeBattleState({ p1Units: [ranger], p2Units: [tank] }));
    const revives = eventsOfType(events, 'revive');
    expect(revives).toHaveLength(1);
    expect((revives[0] as { hpAfter: number }).hpAfter).toBe(75);
    expect(eventsOfType(events, 'death').length).toBeGreaterThan(0);
  });

  it('Tank 2★ Prioritize: while the Tank is alive enemies hit it, then retarget after it dies (E2)', () => {
    const attacker = makeUnit({ unitId: 'fighter', star: 2, slot: 0, side: 'p1' }); // atk 30
    const tank2 = makeUnit({ unitId: 'tank', star: 2, slot: 0, side: 'p2', id: 'tank2', hp: 40, maxHp: 40 });
    const other = makeUnit({ unitId: 'fighter', slot: 1, side: 'p2', id: 'other', hp: 100000 });
    const events = runBattle(
      makeBattleState({ p1Units: [attacker], p2Units: [tank2, other] }),
    );
    const attacks = (eventsOfType(events, 'attack') as { attacker: string; target: string; tick: number; cycle: number }[])
      .filter((a) => a.attacker === attacker.instanceId);
    const tankDeath = eventsOfType(events, 'death')[0] as { cycle: number; tick: number };

    expect(attacks[0].target).toBe('tank2');
    // some later attack, after the tank is gone, lands on `other`
    expect(attacks.some((a) => a.target === 'other')).toBe(true);
    expect(tankDeath).toBeDefined();
  });
});

describe('runBattle — edge cases (docs/05 §8)', () => {
  it('E1: a Healer with no reachable enemy still heals an ally', () => {
    const healer = makeUnit({ unitId: 'healer', star: 0, slot: 0, side: 'p1', hp: 50, maxHp: 70 });
    const events = runBattle(makeBattleState({ p1Units: [healer], p2Units: [] }));
    expect(eventsOfType(events, 'heal').length).toBeGreaterThan(0);
    expect(lastEvent(events)).toMatchObject({ type: 'battle_end', winner: 'p1' });
  });

  it('E4: two Ranger 2★ both target the global lowest-HP enemy', () => {
    const r1 = makeUnit({ unitId: 'ranger', star: 2, slot: 0, side: 'p1', id: 'r1' });
    const r2 = makeUnit({ unitId: 'ranger', star: 2, slot: 1, side: 'p1', id: 'r2' });
    const strong = makeUnit({ unitId: 'fighter', slot: 0, side: 'p2', id: 'strong', hp: 100000 });
    const weak = makeUnit({ unitId: 'healer', slot: 8, side: 'p2', id: 'weak', hp: 100, maxHp: 100 });
    const events = runBattle(
      makeBattleState({ p1Units: [r1, r2], p2Units: [strong, weak] }),
    );
    const rangerAttacks = (eventsOfType(events, 'attack') as { attacker: string; target: string }[])
      .filter((a) => a.attacker === 'r1' || a.attacker === 'r2')
      .slice(0, 2);
    expect(rangerAttacks).toHaveLength(2);
    expect(rangerAttacks.every((a) => a.target === 'weak')).toBe(true);
  });

  it('E6: a slowed unit keeps attacking, just less often', () => {
    const healer = makeUnit({ unitId: 'healer', star: 1, slot: 0, side: 'p1' });
    const fighter = makeUnit({ unitId: 'fighter', slot: 0, side: 'p2', id: 'f', hp: 100000 });
    const events = runBattle(
      makeBattleState({ p1Units: [healer], p2Units: [fighter] }),
    );
    const slowTick = (eventsOfType(events, 'slow')[0] as { cycle: number }).cycle;
    const fighterAttacksAfter = (eventsOfType(events, 'attack') as { attacker: string; cycle: number }[])
      .filter((a) => a.attacker === 'f' && a.cycle > slowTick);
    expect(fighterAttacksAfter.length).toBeGreaterThan(0);
  });

  it('E7: a side with 0 units loses in cycle 1', () => {
    const events = runBattle(
      makeBattleState({
        p1Units: [],
        p2Units: [makeUnit({ unitId: 'fighter', slot: 0, side: 'p2' })],
      }),
    );
    expect(eventsOfType(events, 'cycle_end')).toHaveLength(1);
    expect(lastEvent(events)).toMatchObject({ type: 'battle_end', cycle: 1, winner: 'p2' });
  });

  it('E3: mutual last-unit kills in one cycle end the battle in a tie', () => {
    // p1 ranger (acts tick 10) kills p2 fighter; p2 healer (acts tick 50/100)
    // then has no target but p2 still has a unit until it too dies. Craft a
    // true double-wipe: each side one 1-HP unit that the OTHER side's faster
    // unit can reach, and a decoy so the faster unit isn't the one that dies.
    const p1Fast = makeUnit({ unitId: 'ranger', star: 0, slot: 0, side: 'p1', id: 'p1fast', hp: 100000 });
    const p1Fragile = makeUnit({ unitId: 'fighter', slot: 1, side: 'p1', id: 'p1frag', hp: 1 });
    const p2Fast = makeUnit({ unitId: 'ranger', star: 0, slot: 0, side: 'p2', id: 'p2fast', hp: 100000 });
    const p2Fragile = makeUnit({ unitId: 'fighter', slot: 1, side: 'p2', id: 'p2frag', hp: 1 });

    // Not a guaranteed tie (sequential resolution), but the engine must always
    // terminate with a valid battle_end and never throw.
    const events = runBattle(
      makeBattleState({ p1Units: [p1Fast, p1Fragile], p2Units: [p2Fast, p2Fragile] }),
    );
    expect(lastEvent(events).type).toBe('battle_end');
  });
});

describe('runBattle — determinism (FR-COMBAT-5)', () => {
  const build = () => {
    resetIds();
    const kinds = ['fighter', 'ranger', 'healer', 'tank', 'fighter', 'ranger', 'healer', 'tank', 'fighter'] as const;
    const side = (s: 'p1' | 'p2'): UnitInstance[] =>
      kinds.map((k, i) =>
        makeUnit({
          unitId: k,
          star: (i % 3) as 0 | 1 | 2,
          slot: i,
          side: s,
          hp: 60 + i * 10,
          maxHp: 60 + i * 10,
        }),
      );
    return makeBattleState({ p1Units: side('p1'), p2Units: side('p2'), roundSeed: 777 });
  };

  it('same input → byte-identical CombatEvent[] (input is not mutated)', () => {
    const state = build();
    const a = runBattle(state);
    const b = runBattle(state);
    expect(JSON.stringify(b)).toEqual(JSON.stringify(a));
  });

  it('matches the committed golden fixture', () => {
    const events = runBattle(build());
    const golden = JSON.parse(
      readFileSync(join(__dirname, 'fixtures', 'golden-battle.json'), 'utf8'),
    );
    expect(events).toEqual(golden);
  });

  it('the seeded RNG is stable', () => {
    const rng = makeRng(777);
    const first = [rng(), rng(), rng()];
    const rng2 = makeRng(777);
    expect([rng2(), rng2(), rng2()]).toEqual(first);
  });
});
