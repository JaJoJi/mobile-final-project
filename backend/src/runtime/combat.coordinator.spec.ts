import RedisMock from 'ioredis-mock';

// QueueService pulls @nestjs/bullmq (ESM-only under ts-jest); the match
// module chain is stubbed the same way — specs inject their own fakes.
jest.mock('../queue/queue.service', () => ({
  QueueService: class QueueService {},
}));
jest.mock('../match/match.service', () => ({
  MatchService: class MatchService {},
}));

import { CombatCoordinator } from './combat.coordinator';
import { initialRuntimeHash, runtimeKey } from './match.runtime-state';

type Mock = InstanceType<typeof RedisMock>;

const OWNER = { player1Id: 'p1', player2Id: 'p2', player1Name: 'a', player2Name: 'b' };

const makeMatch = (id: string) => ({
  id,
  player1Id: 'p1',
  player2Id: 'p2',
  matchSeed: 'seed-1',
  wipeIndexP1: 0,
  wipeIndexP2: 0,
  p1State: {
    hp: 100,
    gold: 5,
    ready: false,
    board: [
      { instanceId: 'a1', unitId: 'fighter', star: 0, hp: 100, maxHp: 100 },
      null, null, null, null, null, null, null, null,
    ],
    bench: Array(8).fill(null),
  },
  p2State: {
    hp: 100,
    gold: 5,
    ready: false,
    board: [
      { instanceId: 'b1', unitId: 'fighter', star: 0, hp: 100, maxHp: 100 },
      null, null, null, null, null, null, null, null,
    ],
    bench: Array(8).fill(null),
  },
});

const BATTLE_EVENTS = [
  { type: 'attack', cycle: 1 },
  { type: 'battle_end', cycle: 3, winner: 'p1' },
];

const makeCoordinator = () => {
  const mock: Mock = new RedisMock();
  const appended: unknown[] = [];
  const published: unknown[] = [];
  const timeouts: unknown[] = [];
  const results = new Map<string, unknown>();
  const redis = { client: mock };
  const pubsub = {
    writeCombatResult: async (matchId: string, events: unknown) => {
      results.set(matchId, events);
    },
    publish: async (matchId: string, type: string, payload: unknown) => {
      published.push({ matchId, type, payload });
    },
    getCombatResult: async (matchId: string) => results.get(matchId) ?? null,
  };
  const matches = {
    appendRoundEvents: async (...args: unknown[]) => {
      appended.push(args);
    },
  };
  const queue = {
    scheduleCombatDoneTimeout: async (...args: unknown[]) => {
      timeouts.push(args);
    },
  };
  const engine = jest.fn(() => BATTLE_EVENTS);
  const coordinator = new CombatCoordinator(
    redis as any,
    pubsub as any,
    matches as any,
    queue as any,
    engine as any,
  );
  return { mock, appended, published, timeouts, engine, coordinator };
};

const seedBattle = async (mock: Mock, matchId: string, round: number, phase = 'battle') => {
  await mock.hset(runtimeKey(matchId), {
    ...initialRuntimeHash(makeMatch(matchId) as any, OWNER as any),
    phase,
    round: String(round),
  });
};

beforeEach(async () => {
  await new RedisMock().flushall();
});

describe('CombatCoordinator single-runner (#306)', () => {
  it('winner runs the engine once and persists, publishes, schedules', async () => {
    const { mock, appended, published, timeouts, engine, coordinator } = makeCoordinator();
    await seedBattle(mock, 'm1', 2);

    await expect(coordinator.runCombat('m1', 2)).resolves.toBe(true);

    expect(engine).toHaveBeenCalledTimes(1);
    expect(appended).toHaveLength(1);
    expect(published).toEqual([
      expect.objectContaining({ matchId: 'm1', type: 'game:combat:events' }),
    ]);
    expect(timeouts).toHaveLength(1);
    expect(await mock.hget(runtimeKey('m1'), 'combatRound')).toBe('2');
    // Lock released via compare-and-delete, not left to expire.
    expect(await mock.get('combat-lock:m1')).toBeNull();
  });

  it('loser of the lock exits safely without touching anything', async () => {
    const { engine, coordinator } = makeCoordinator();
    const holder: Mock = new RedisMock();
    await holder.set('combat-lock:m1', 'other-owner', 'EX', 30);

    await expect(coordinator.runCombat('m1', 1)).resolves.toBe(false);
    expect(engine).not.toHaveBeenCalled();
  });

  it('bails out on stale phase/round and releases the lock', async () => {
    const { mock, engine, coordinator } = makeCoordinator();
    await seedBattle(mock, 'm1', 1, 'shop_place');

    await expect(coordinator.runCombat('m1', 1)).resolves.toBe(false);
    expect(engine).not.toHaveBeenCalled();
    expect(await mock.get('combat-lock:m1')).toBeNull();
  });

  it('does not re-run a round that already has combatRound set', async () => {
    const { mock, engine, coordinator } = makeCoordinator();
    await seedBattle(mock, 'm1', 2);
    await mock.hset(runtimeKey('m1'), 'combatRound', '2');

    await expect(coordinator.runCombat('m1', 2)).resolves.toBe(false);
    expect(engine).not.toHaveBeenCalled();
  });

  it('releases the lock even when the engine throws', async () => {
    const { mock, engine, coordinator } = makeCoordinator();
    await seedBattle(mock, 'm1', 1);
    engine.mockImplementationOnce(() => {
      throw new Error('engine blew up');
    });

    await expect(coordinator.runCombat('m1', 1)).rejects.toThrow('engine blew up');
    expect(await mock.get('combat-lock:m1')).toBeNull();
  });

  it('concurrent runners execute the engine exactly once', async () => {
    const { mock, engine, coordinator } = makeCoordinator();
    await seedBattle(mock, 'm1', 1);

    const results = await Promise.allSettled([
      coordinator.runCombat('m1', 1),
      coordinator.runCombat('m1', 1),
    ]);
    const wins = results.filter((r) => r.status === 'fulfilled' && r.value === true);
    expect(wins).toHaveLength(1);
    expect(engine).toHaveBeenCalledTimes(1);
  });
});
