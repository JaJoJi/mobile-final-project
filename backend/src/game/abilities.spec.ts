import {
  applyHealerSupport,
  applyLifesteal,
  applyPierce,
  applySlow,
  clearHealerSlows,
} from './abilities';
import { spdFor } from './constants';
import type { CombatEvent } from './types';
import { eventsOfType, makeSim, makeUnit } from './fixtures/board-builder';

describe('Fighter Lifesteal (docs/05 §4.1)', () => {
  it('1★ heals floor(dmg * 0.05)', () => {
    const fighter = makeUnit({ unitId: 'fighter', star: 1, slot: 0, hp: 50, maxHp: 100 });
    const events: CombatEvent[] = [];
    applyLifesteal(fighter, 22, 1, 1, events);
    expect(fighter.hp).toBe(51);
    expect(events).toEqual([
      { type: 'lifesteal', cycle: 1, tick: 1, unit: fighter.instanceId, amount: 1, hpAfter: 51 },
    ]);
  });

  it('2★ heals floor(dmg * 0.10)', () => {
    const fighter = makeUnit({ unitId: 'fighter', star: 2, slot: 0, hp: 50, maxHp: 100 });
    const events: CombatEvent[] = [];
    applyLifesteal(fighter, 30, 1, 1, events);
    expect(fighter.hp).toBe(53);
  });

  it('E15: overheal is capped at maxHp', () => {
    const fighter = makeUnit({ unitId: 'fighter', star: 2, slot: 0, hp: 99, maxHp: 100 });
    const events: CombatEvent[] = [];
    applyLifesteal(fighter, 100, 1, 1, events); // raw heal 10, cap 1
    expect(fighter.hp).toBe(100);
    expect((events[0] as { amount: number }).amount).toBe(1);
  });
});

describe('Ranger Pierce (docs/05 §4.2)', () => {
  const ranger = makeUnit({ unitId: 'ranger', star: 1, slot: 0, side: 'p1' });

  it('spills 10% of the primary damage to the alive unit one row behind (row+1)', () => {
    const front = makeUnit({ unitId: 'fighter', slot: 0, side: 'p2', id: 'front', hp: 100 });
    const behind = makeUnit({ unitId: 'fighter', slot: 3, side: 'p2', id: 'behind', hp: 100 });
    const events: CombatEvent[] = [];
    applyPierce(ranger, front, 18, makeSim([ranger], [front, behind]), 1, 1, events);

    expect(behind.hp).toBe(99); // floor(18 * 0.1) = 1
    expect(events).toEqual([
      { type: 'pierce', cycle: 1, tick: 1, attacker: ranger.instanceId, target: 'behind', damage: 1 },
    ]);
  });

  it('omits the pierce when row+1 is empty — it does NOT skip to row+2', () => {
    const front = makeUnit({ unitId: 'fighter', slot: 0, side: 'p2', id: 'front' });
    const twoBack = makeUnit({ unitId: 'fighter', slot: 6, side: 'p2', id: 'twoBack' });
    const events: CombatEvent[] = [];
    applyPierce(ranger, front, 50, makeSim([ranger], [front, twoBack]), 1, 1, events);
    expect(events).toHaveLength(0);
  });

  it('a lethal pierce kills the unit behind (death event, no revive)', () => {
    const front = makeUnit({ unitId: 'fighter', slot: 0, side: 'p2', id: 'front' });
    const behind = makeUnit({ unitId: 'tank', star: 1, slot: 3, side: 'p2', id: 'behind', hp: 1 });
    const events: CombatEvent[] = [];
    applyPierce(ranger, front, 100, makeSim([ranger], [front, behind]), 1, 1, events);
    expect(behind.alive).toBe(false);
    expect(events.map((e) => e.type)).toEqual(['pierce', 'death']);
  });
});

describe('Healer support (docs/05 §4.4)', () => {
  it('0★/1★ heals the lowest-HP ally (self included) for up to 10', () => {
    const healer = makeUnit({ unitId: 'healer', star: 0, slot: 0, hp: 70, maxHp: 70 });
    const ally = makeUnit({ unitId: 'fighter', slot: 1, side: 'p1', id: 'ally', hp: 40, maxHp: 100 });
    const events: CombatEvent[] = [];
    applyHealerSupport(healer, makeSim([healer, ally], []), 1, 1, events);
    expect(ally.hp).toBe(50);
    expect(eventsOfType(events, 'heal')).toHaveLength(1);
  });

  it('2★ heals the two lowest-HP allies', () => {
    const healer = makeUnit({ unitId: 'healer', star: 2, slot: 0, hp: 70, maxHp: 70 });
    const a = makeUnit({ unitId: 'fighter', slot: 1, side: 'p1', id: 'a', hp: 40, maxHp: 100 });
    const b = makeUnit({ unitId: 'fighter', slot: 2, side: 'p1', id: 'b', hp: 50, maxHp: 100 });
    const events: CombatEvent[] = [];
    applyHealerSupport(healer, makeSim([healer, a, b], []), 1, 1, events);
    expect(a.hp).toBe(50);
    expect(b.hp).toBe(60);
    expect(eventsOfType(events, 'heal')).toHaveLength(2);
  });

  it('E13: healing a full-HP roster emits no heal event', () => {
    const healer = makeUnit({ unitId: 'healer', star: 0, slot: 0, hp: 70, maxHp: 70 });
    const ally = makeUnit({ unitId: 'fighter', slot: 1, side: 'p1', id: 'ally', hp: 100, maxHp: 100 });
    const events: CombatEvent[] = [];
    applyHealerSupport(healer, makeSim([healer, ally], []), 1, 1, events);
    expect(events).toHaveLength(0);
  });

  it('E14: a 2★ Healer with only itself alive heals once', () => {
    const healer = makeUnit({ unitId: 'healer', star: 2, slot: 0, hp: 40, maxHp: 70 });
    const events: CombatEvent[] = [];
    applyHealerSupport(healer, makeSim([healer], []), 1, 1, events);
    expect(eventsOfType(events, 'heal')).toHaveLength(1);
  });
});

describe('Healer Slow (docs/05 §4.4)', () => {
  it('sets the target effectiveSpd to round(baseSpd * 0.7) and emits slow', () => {
    const healer = makeUnit({ unitId: 'healer', star: 1, slot: 0, side: 'p1' });
    const enemy = makeUnit({ unitId: 'fighter', slot: 0, side: 'p2', id: 'enemy' });
    const events: CombatEvent[] = [];
    applySlow(healer, enemy, 1, 1, events);

    expect(enemy.effectiveSpd).toBe(Math.round(spdFor('fighter') * 0.7)); // 14
    expect(enemy.slowActive).toBe(true);
    expect(enemy.slowUntilHealerAct).toBe(healer.instanceId);
    expect(events).toEqual([
      { type: 'slow', cycle: 1, tick: 1, target: 'enemy', by: healer.instanceId },
    ]);
  });

  it('clearHealerSlows restores the base SPD for units this Healer slowed', () => {
    const healer = makeUnit({ unitId: 'healer', star: 1, slot: 0, side: 'p1' });
    const enemy = makeUnit({ unitId: 'ranger', slot: 0, side: 'p2', id: 'enemy' });
    const events: CombatEvent[] = [];
    applySlow(healer, enemy, 1, 1, events);
    clearHealerSlows(healer, makeSim([healer], [enemy]));

    expect(enemy.effectiveSpd).toBe(spdFor('ranger'));
    expect(enemy.slowActive).toBe(false);
  });
});
