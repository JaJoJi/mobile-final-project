import { pickTarget } from './targeting';
import { makeSim, makeUnit } from './fixtures/board-builder';

describe('pickTarget — 3×3 board (docs/05 §2)', () => {
  it('returns null when the enemy team is empty', () => {
    const attacker = makeUnit({ unitId: 'fighter', slot: 4, side: 'p1' });
    expect(pickTarget(attacker, makeSim([attacker], []))).toBeNull();
  });

  it('prefers the front row in the same lane', () => {
    const attacker = makeUnit({ unitId: 'fighter', slot: 4, side: 'p1' }); // col 1
    const front = makeUnit({ unitId: 'fighter', slot: 1, side: 'p2', id: 'front' });
    const middle = makeUnit({ unitId: 'fighter', slot: 4, side: 'p2', id: 'middle' });
    const t = pickTarget(attacker, makeSim([attacker], [front, middle]));
    expect(t?.instanceId).toBe('front');
  });

  it('falls to the middle row when the front of the lane is empty', () => {
    const attacker = makeUnit({ unitId: 'fighter', slot: 4, side: 'p1' });
    const middle = makeUnit({ unitId: 'fighter', slot: 4, side: 'p2', id: 'middle' });
    const back = makeUnit({ unitId: 'fighter', slot: 7, side: 'p2', id: 'back' });
    const t = pickTarget(attacker, makeSim([attacker], [middle, back]));
    expect(t?.instanceId).toBe('middle');
  });

  it('falls to the back row when front and middle of the lane are empty', () => {
    const attacker = makeUnit({ unitId: 'fighter', slot: 4, side: 'p1' });
    const back = makeUnit({ unitId: 'fighter', slot: 7, side: 'p2', id: 'back' });
    const t = pickTarget(attacker, makeSim([attacker], [back]));
    expect(t?.instanceId).toBe('back');
  });

  it('cross-lane fallback checks each col fully (front→mid→back) before the next col', () => {
    const attacker = makeUnit({ unitId: 'fighter', slot: 5, side: 'p1' }); // col 2, empty lane
    const col1Front = makeUnit({ unitId: 'fighter', slot: 1, side: 'p2', id: 'c1f' });
    const col0Middle = makeUnit({ unitId: 'fighter', slot: 3, side: 'p2', id: 'c0m' });
    const t = pickTarget(attacker, makeSim([attacker], [col1Front, col0Middle]));
    // col 0 is scanned first: its middle row wins before col 1 is looked at
    expect(t?.instanceId).toBe('c0m');
  });

  it('Tank 2★ Prioritize: a fighter targets the enemy 2★ Tank over the front row', () => {
    const attacker = makeUnit({ unitId: 'fighter', slot: 4, side: 'p1' });
    const frontFighter = makeUnit({ unitId: 'fighter', slot: 1, side: 'p2', id: 'ff' });
    const tank2 = makeUnit({ unitId: 'tank', star: 2, slot: 8, side: 'p2', id: 'tank2' });
    const t = pickTarget(attacker, makeSim([attacker], [frontFighter, tank2]));
    expect(t?.instanceId).toBe('tank2');
  });

  it('Tank 2★ Prioritize does NOT steer a Ranger', () => {
    const ranger = makeUnit({ unitId: 'ranger', star: 1, slot: 4, side: 'p1' });
    const frontFighter = makeUnit({
      unitId: 'fighter',
      slot: 1,
      side: 'p2',
      id: 'ff',
      hp: 100,
    });
    const tank2 = makeUnit({
      unitId: 'tank',
      star: 2,
      slot: 8,
      side: 'p2',
      id: 'tank2',
      hp: 150,
    });
    const t = pickTarget(ranger, makeSim([ranger], [frontFighter, tank2]));
    expect(t?.instanceId).toBe('ff'); // lane rule + lowest HP within candidates
  });

  it('Ranger 2★ Global: lowest HP anywhere on the 9-slot team, ignoring lanes', () => {
    const ranger = makeUnit({ unitId: 'ranger', star: 2, slot: 0, side: 'p1' });
    const full = makeUnit({ unitId: 'fighter', slot: 0, side: 'p2', id: 'full', hp: 100 });
    const weak = makeUnit({ unitId: 'healer', slot: 8, side: 'p2', id: 'weak', hp: 7 });
    const t = pickTarget(ranger, makeSim([ranger], [full, weak]));
    expect(t?.instanceId).toBe('weak');
  });

  it('Fighter tie-break: lowest col, then lowest row, then instanceId', () => {
    const attacker = makeUnit({ unitId: 'fighter', slot: 4, side: 'p1' }); // col 1 (empty lane)
    const col2 = makeUnit({ unitId: 'fighter', slot: 2, side: 'p2', id: 'col2' }); // row0 col2
    const col0 = makeUnit({ unitId: 'fighter', slot: 0, side: 'p2', id: 'col0' }); // row0 col0
    const t = pickTarget(attacker, makeSim([attacker], [col2, col0]));
    expect(t?.instanceId).toBe('col0');
  });

  it('Ranger 0★/1★ picks the lowest-HP unit among the lane candidates', () => {
    const ranger = makeUnit({ unitId: 'ranger', star: 1, slot: 4, side: 'p1' });
    const strong = makeUnit({ unitId: 'fighter', slot: 1, side: 'p2', id: 'strong', hp: 100 });
    const weak = makeUnit({ unitId: 'fighter', slot: 4, side: 'p2', id: 'weak', hp: 20 });
    // both in col 1: strong front (row0), weak middle (row1) → front row wins the
    // candidate filter, so only `strong` is a candidate.
    const t1 = pickTarget(ranger, makeSim([ranger], [strong, weak]));
    expect(t1?.instanceId).toBe('strong');

    // now both in the front row → lowest HP wins
    const weakFront = makeUnit({ unitId: 'fighter', slot: 0, side: 'p2', id: 'weakFront', hp: 20 });
    const strongFront = makeUnit({ unitId: 'fighter', slot: 1, side: 'p2', id: 'strongFront', hp: 100 });
    const t2 = pickTarget(
      makeUnit({ unitId: 'ranger', star: 1, slot: 0, side: 'p1' }),
      makeSim([], [weakFront, strongFront]),
    );
    expect(t2?.instanceId).toBe('weakFront');
  });

  it('skips dead enemies', () => {
    const attacker = makeUnit({ unitId: 'fighter', slot: 4, side: 'p1' });
    const dead = makeUnit({ unitId: 'fighter', slot: 1, side: 'p2', id: 'dead', hp: 0 });
    const alive = makeUnit({ unitId: 'fighter', slot: 4, side: 'p2', id: 'alive' });
    const t = pickTarget(attacker, makeSim([attacker], [dead, alive]));
    expect(t?.instanceId).toBe('alive');
  });
});
