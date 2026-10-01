import {
  STATS_CACHE_TTL_SECONDS,
  StatsService,
  statsCacheKey,
} from './stats.service';

interface MatchCounts {
  matches: string;
  wins: string;
  losses: string;
}

class FakeDataSource {
  counts: MatchCounts = { matches: '0', wins: '0', losses: '0' };
  greater = '0';
  failOn: '' | 'matches' | 'users' = '';
  readonly queries: string[] = [];
  readonly runnerModes: string[] = [];

  createQueryRunner(mode: string) {
    this.runnerModes.push(mode);
    const pg = this;
    return {
      query: (sql: string, params: unknown[]) => pg.query(sql, params),
      release: async () => undefined,
    };
  }

  async query(sql: string, _params: unknown[]): Promise<unknown[]> {
    this.queries.push(sql);
    if (sql.includes('FROM "matches"')) {
      if (this.failOn === 'matches') throw new Error('PG down');
      return [this.counts];
    }
    if (this.failOn === 'users') throw new Error('PG down');
    return [{ count: this.greater }];
  }
}

class FakeRedisClient {
  readonly store = new Map<string, { value: string; ttl: number }>();
  readonly sets: Array<{ key: string; ttl: number }> = [];
  readonly gets: string[] = [];
  readonly dels: string[][] = [];
  failGet = false;
  failSet = false;

  async get(key: string): Promise<string | null> {
    this.gets.push(key);
    if (this.failGet) throw new Error('Redis down');
    return this.store.get(key)?.value ?? null;
  }

  async set(key: string, value: string, mode: string, ttl: number): Promise<string> {
    if (this.failSet) throw new Error('Redis down');
    if (mode !== 'EX') throw new Error(`expected EX, got ${mode}`);
    this.store.set(key, { value, ttl });
    this.sets.push({ key, ttl });
    return 'OK';
  }

  async del(...keys: string[]): Promise<number> {
    this.dels.push(keys);
    for (const key of keys) this.store.delete(key);
    return keys.length;
  }
}

class FakeUsers {
  rating: number | null = 1000;

  async findById(_id: string): Promise<{ rating: number } | null> {
    return this.rating === null ? null : { rating: this.rating };
  }
}

const makeService = () => {
  const pg = new FakeDataSource();
  const client = new FakeRedisClient();
  const users = new FakeUsers();
  const service = new StatsService(
    pg as any,
    { client } as any,
    users as any,
  );
  return { pg, client, users, service };
};

describe('StatsService (#254)', () => {
  it('returns zeros and null winRate/rank for a user with no matches', async () => {
    const { service } = makeService();
    await expect(service.getStats('user-1')).resolves.toEqual({
      matches: 0,
      wins: 0,
      losses: 0,
      winRate: null,
      currentRank: 1,
    });
  });

  it('counts finished matches and computes winRate', async () => {
    const { pg, service } = makeService();
    pg.counts = { matches: '5', wins: '3', losses: '1' };
    await expect(service.getStats('user-1')).resolves.toMatchObject({
      matches: 5,
      wins: 3,
      losses: 1,
      winRate: 60,
    });
  });

  it('counts forfeited matches as terminal and draws as matches but not losses', async () => {
    const { pg, service } = makeService();
    // 4 terminal: 2 wins, 1 loss, 1 draw (winnerId NULL).
    pg.counts = { matches: '4', wins: '2', losses: '1' };
    const stats = await service.getStats('user-1');
    expect(stats.matches).toBe(4);
    expect(stats.wins + stats.losses).toBeLessThan(stats.matches);
    expect(stats.winRate).toBe(50);
  });

  it('rounds winRate with Math.round', async () => {
    const { pg, service } = makeService();
    pg.counts = { matches: '3', wins: '1', losses: '2' };
    await expect(service.getStats('user-1')).resolves.toMatchObject({ winRate: 33 });
    pg.counts = { matches: '3', wins: '2', losses: '1' };
    // Bust the cache written by the first call.
    await service.invalidateUsers(['user-1']);
    await expect(service.getStats('user-1')).resolves.toMatchObject({ winRate: 67 });
  });

  it('shares rank on rating ties (RANK semantics)', async () => {
    const { pg, users, service } = makeService();
    users.rating = 1500;
    pg.greater = '2'; // two players strictly above; tied peers do not outrank.
    await expect(service.getStats('user-1')).resolves.toMatchObject({ currentRank: 3 });
  });

  it('returns null rank when the user cannot be found', async () => {
    const { users, service } = makeService();
    users.rating = null;
    await expect(service.getStats('ghost')).resolves.toMatchObject({
      matches: 0,
      winRate: null,
      currentRank: null,
    });
  });

  it('propagates PostgreSQL errors instead of masking them as null rank', async () => {
    const { pg, service } = makeService();
    pg.failOn = 'matches';
    await expect(service.getStats('user-1')).rejects.toThrow('PG down');
  });

  it('cache MISS queries PG, caches with ~60s TTL; HIT skips PG', async () => {
    const { pg, client, service } = makeService();
    pg.counts = { matches: '2', wins: '2', losses: '0' };

    const first = await service.getStats('user-1');
    expect(first).toMatchObject({ matches: 2, winRate: 100 });
    expect(client.sets).toEqual([
      { key: statsCacheKey('user-1'), ttl: STATS_CACHE_TTL_SECONDS },
    ]);
    expect(STATS_CACHE_TTL_SECONDS).toBe(60);

    pg.queries.length = 0;
    const second = await service.getStats('user-1');
    expect(second).toEqual(first);
    expect(pg.queries).toHaveLength(0);
    expect(client.gets).toEqual([statsCacheKey('user-1'), statsCacheKey('user-1')]);
  });

  it('fails open to PG when Redis GET/SET fail', async () => {
    const { pg, client, service } = makeService();
    pg.counts = { matches: '1', wins: '1', losses: '0' };
    client.failGet = true;
    client.failSet = true;
    await expect(service.getStats('user-1')).resolves.toMatchObject({
      matches: 1,
      winRate: 100,
      currentRank: 1,
    });
  });

  it('routes aggregate SQL through "slave" runners (replica)', async () => {
    const { pg, service } = makeService();
    await service.getStats('user-1');
    expect(pg.queries.length).toBeGreaterThan(0);
    expect(pg.runnerModes.length).toBe(pg.queries.length);
    expect(pg.runnerModes).not.toContain('master');
  });

  it('invalidateUsers deletes affected players best-effort', async () => {
    const { client, service } = makeService();
    await service.getStats('p1');
    await service.invalidateUsers(['p1', 'p2']);
    expect(client.dels).toEqual([[statsCacheKey('p1'), statsCacheKey('p2')]]);
    await expect(service.invalidateUsers([])).resolves.toBeUndefined();
  });
});
