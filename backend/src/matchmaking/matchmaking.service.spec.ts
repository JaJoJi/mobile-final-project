import { readFileSync } from 'fs';
import { join } from 'path';
import RedisMock from 'ioredis-mock';

// MatchRuntimeAdapter pulls the BullMQ worker chain (ESM-only under ts-jest);
// specs inject their own fakes, so stub the module.
jest.mock('../runtime/match.runtime.adapter', () => ({
  MatchRuntimeAdapter: class MatchRuntimeAdapter {},
}));

import { MATCHMAKING_QUEUE_KEY } from './matchmaking.keys';
import { MatchmakingService } from './matchmaking.service';

const load = (name: string): string =>
  readFileSync(join(__dirname, '..', 'redis', 'scripts', `${name}.lua`), 'utf8');

type Mock = InstanceType<typeof RedisMock>;

class FakeMatches {
  readonly active = new Map<string, string>();
  readonly created: Array<{ player1Id: string; player2Id: string }> = [];
  failCreate = false;
  private seq = 0;

  async findActiveByUserId(userId: string): Promise<{ id: string } | null> {
    const id = this.active.get(userId);
    return id ? ({ id } as any) : null;
  }

  async create(input: { player1Id: string; player2Id: string }): Promise<any> {
    if (this.failCreate) throw new Error('PG down');
    this.created.push({ player1Id: input.player1Id, player2Id: input.player2Id });
    this.seq += 1;
    return { id: `match-${this.seq}`, ...input };
  }
}

const makeService = () => {
  const mock: Mock = new RedisMock();
  const matches = new FakeMatches();
  const initialized: unknown[] = [];
  const redis = {
    client: mock,
    eval: (name: string, keys: string[], args: (string | number)[]) =>
      mock.eval(load(name), keys.length, ...keys, ...args.map(String)),
  };
  const runtime = {
    initializeMatch: async (match: unknown) => {
      initialized.push(match);
    },
  };
  const service = new MatchmakingService(redis as any, matches as any, runtime as any);
  return { mock, matches, initialized, service };
};

// ioredis-mock instances share one global store — flush before every test.
beforeEach(async () => {
  await new RedisMock().flushall();
});

describe('MatchmakingService queue (#306)', () => {
  it('joins idempotently: NX preserves the original FIFO score', async () => {
    const { mock, service } = makeService();
    await expect(service.joinQueue('alice', 1000)).resolves.toEqual({ queued: true });
    await expect(service.joinQueue('alice', 2000)).resolves.toEqual({ queued: false });
    expect(await mock.zscore(MATCHMAKING_QUEUE_KEY, 'alice')).toBe('1000');
  });

  it('rejects join when the user already has an active match', async () => {
    const { matches, service } = makeService();
    matches.active.set('alice', 'match-9');
    await expect(service.joinQueue('alice')).rejects.toThrow('already has active match');
  });

  it('leaveQueue removes only an existing entry', async () => {
    const { service } = makeService();
    await expect(service.leaveQueue('ghost')).resolves.toBe(false);
    await service.joinQueue('alice', 1000);
    await expect(service.leaveQueue('alice')).resolves.toBe(true);
    await expect(service.leaveQueue('alice')).resolves.toBe(false);
  });
});

describe('MatchmakingService.tryPair (#306)', () => {
  it('pairs the two longest-waiting players and initializes exactly once', async () => {
    const { mock, matches, initialized, service } = makeService();
    await service.joinQueue('cara', 3000);
    await service.joinQueue('alice', 1000);
    await service.joinQueue('bob', 2000);

    const res = await service.tryPair();

    expect(res).toMatchObject({ player1Id: 'alice', player2Id: 'bob' });
    expect(typeof res?.matchId).toBe('string');
    expect(matches.created).toEqual([{ player1Id: 'alice', player2Id: 'bob' }]);
    expect(initialized).toHaveLength(1);
    expect(await mock.zrange(MATCHMAKING_QUEUE_KEY, 0, -1)).toEqual(['cara']);
  });

  it('is a no-op with fewer than two queued players', async () => {
    const { matches, initialized, service } = makeService();
    await service.joinQueue('solo', 1000);
    await expect(service.tryPair()).resolves.toBeNull();
    expect(matches.created).toHaveLength(0);
    expect(initialized).toHaveLength(0);
  });

  it('discards a stale entry and requeues the free player', async () => {
    const { mock, matches, service } = makeService();
    await service.joinQueue('busy', 1000);
    await service.joinQueue('free', 2000);
    matches.active.set('busy', 'match-old');

    await expect(service.tryPair()).resolves.toBeNull();
    expect(matches.created).toHaveLength(0);
    // Only the free player is back in the queue; the stale one is gone.
    expect(await mock.zrange(MATCHMAKING_QUEUE_KEY, 0, -1)).toEqual(['free']);
  });

  it('requeues both players when persistence fails, then throws', async () => {
    const { mock, matches, service } = makeService();
    await service.joinQueue('alice', 1000);
    await service.joinQueue('bob', 2000);
    matches.failCreate = true;

    await expect(service.tryPair()).rejects.toThrow('PG down');
    expect(await mock.zrange(MATCHMAKING_QUEUE_KEY, 0, -1)).toEqual(['alice', 'bob']);
  });

  it('concurrent workers pair disjoint players (atomic Lua pop)', async () => {
    const { mock, matches, service } = makeService();
    await service.joinQueue('p1', 1000);
    await service.joinQueue('p2', 2000);
    await service.joinQueue('p3', 3000);
    await service.joinQueue('p4', 4000);

    const results = await Promise.allSettled([
      service.tryPair(),
      service.tryPair(),
      service.tryPair(),
    ]);
    const pairs = results
      .filter((r) => r.status === 'fulfilled' && r.value)
      .map((r) => (r as PromiseFulfilledResult<any>).value);

    // Two disjoint pairs, no player used twice, queue drained.
    expect(pairs).toHaveLength(2);
    const used = pairs.flatMap((p) => [p.player1Id, p.player2Id]);
    expect(new Set(used).size).toBe(4);
    expect(matches.created).toHaveLength(2);
    expect(await mock.zrange(MATCHMAKING_QUEUE_KEY, 0, -1)).toEqual([]);
  });

  it('duplicate ticks after drain are harmless no-ops', async () => {
    const { matches, service } = makeService();
    await service.joinQueue('alice', 1000);
    await service.joinQueue('bob', 2000);
    await service.tryPair();
    await expect(service.tryPair()).resolves.toBeNull();
    expect(matches.created).toHaveLength(1);
  });
});
