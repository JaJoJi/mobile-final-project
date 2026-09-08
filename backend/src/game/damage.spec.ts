import { applyDamage } from './damage';
import type { CombatEvent } from './types';
import { makeUnit } from './fixtures/board-builder';

const src = makeUnit({ unitId: 'fighter', slot: 0, side: 'p1', id: 'src' });

describe('applyDamage (docs/05 §3)', () => {
  it('subtracts HP and emits only an attack event on a non-lethal hit', () => {
    const target = makeUnit({ unitId: 'fighter', slot: 0, side: 'p2', hp: 100 });
    const events: CombatEvent[] = [];
    applyDamage(target, 20, src, 1, 1, events);

    expect(target.hp).toBe(80);
    expect(target.alive).toBe(true);
    expect(events).toEqual([
      {
        type: 'attack',
        cycle: 1,
        tick: 1,
        attacker: 'src',
        target: target.instanceId,
        damage: 20,
        targetHpAfter: 80,
      },
    ]);
  });

  it('clamps HP to 0, marks dead, and emits death BEFORE attack on a lethal hit', () => {
    const target = makeUnit({ unitId: 'fighter', slot: 0, side: 'p2', hp: 10 });
    const events: CombatEvent[] = [];
    applyDamage(target, 20, src, 2, 3, events);

    expect(target.hp).toBe(0);
    expect(target.alive).toBe(false);
    expect(events.map((e) => e.type)).toEqual(['death', 'attack']);
    expect((events[1] as { targetHpAfter: number }).targetHpAfter).toBe(0);
  });

  it('Tank 1★ Revive: first lethal hit revives at floor(maxHp * 0.5), no attack event', () => {
    const tank = makeUnit({ unitId: 'tank', star: 1, slot: 4, side: 'p2', hp: 1, maxHp: 150 });
    const events: CombatEvent[] = [];
    applyDamage(tank, 40, src, 1, 5, events);

    expect(tank.hp).toBe(75);
    expect(tank.alive).toBe(true);
    expect(tank.revivedThisRound).toBe(true);
    expect(events).toEqual([
      { type: 'revive', cycle: 1, tick: 5, unit: tank.instanceId, hpAfter: 75 },
    ]);
  });

  it('Tank 1★ second lethal hit in the same battle kills normally', () => {
    const tank = makeUnit({ unitId: 'tank', star: 1, slot: 4, side: 'p2', hp: 1, maxHp: 150 });
    const events: CombatEvent[] = [];
    applyDamage(tank, 40, src, 1, 5, events); // revive → hp 75
    applyDamage(tank, 100, src, 1, 6, events); // lethal again

    expect(tank.hp).toBe(0);
    expect(tank.alive).toBe(false);
    expect(events.map((e) => e.type)).toEqual(['revive', 'death', 'attack']);
  });

  it('Tank 0★ has no Revive — dies on the first lethal hit', () => {
    const tank = makeUnit({ unitId: 'tank', star: 0, slot: 4, side: 'p2', hp: 5, maxHp: 150 });
    const events: CombatEvent[] = [];
    applyDamage(tank, 20, src, 1, 1, events);

    expect(tank.alive).toBe(false);
    expect(events.some((e) => e.type === 'revive')).toBe(false);
  });
});
