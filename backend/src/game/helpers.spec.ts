import { makeRng, rngInt } from './seeded-rng';
import { enemySideOf, slotToPosition, unitsOf } from './types';
import { makeSim, makeUnit } from './fixtures/board-builder';

describe('seeded-rng', () => {
  it('rngInt stays within the inclusive range and is seed-stable', () => {
    const a = makeRng(42);
    const b = makeRng(42);
    for (let i = 0; i < 200; i++) {
      const x = rngInt(a, 3, 9);
      expect(x).toBeGreaterThanOrEqual(3);
      expect(x).toBeLessThanOrEqual(9);
      expect(x).toBe(rngInt(b, 3, 9));
    }
  });

  it('rngInt with min === max always returns that value', () => {
    const rng = makeRng(1);
    expect(rngInt(rng, 5, 5)).toBe(5);
  });
});

describe('type helpers', () => {
  it('slotToPosition maps row-major slots to {row, col}', () => {
    expect(slotToPosition(0)).toEqual({ row: 0, col: 0 });
    expect(slotToPosition(4)).toEqual({ row: 1, col: 1 });
    expect(slotToPosition(8)).toEqual({ row: 2, col: 2 });
    expect(slotToPosition(5)).toEqual({ row: 1, col: 2 });
  });

  it('enemySideOf flips the side', () => {
    expect(enemySideOf('p1')).toBe('p2');
    expect(enemySideOf('p2')).toBe('p1');
  });

  it('unitsOf returns the requested side', () => {
    const p1 = [makeUnit({ unitId: 'fighter', slot: 0, side: 'p1' })];
    const p2 = [makeUnit({ unitId: 'tank', slot: 0, side: 'p2' })];
    const sim = makeSim(p1, p2);
    expect(unitsOf(sim, 'p1')).toBe(p1);
    expect(unitsOf(sim, 'p2')).toBe(p2);
  });
});
