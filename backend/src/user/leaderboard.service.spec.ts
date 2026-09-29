import {
  LEADERBOARD_CACHE_TTL_SECONDS,
  LEADERBOARD_VERSION_KEY,
  LeaderboardService,
  leaderboardCacheKey,
} from './leaderboard.service';

interface UserRow {
  id: string;
  username: string;
  rating: number;
}

/** Faithful in-memory emulation of the leaderboard SQL semantics. */
class FakeDataSource {
  constructor(public users: UserRow[]) {}
  readonly queries: Array<{ sql: string; params: unknown[] }> = [];

  async query(sql: string, params: unknown[] = []): Promise<unknown[]> {
    this.queries.push({ sql, params });
    if (sql.includes('RANK() OVER')) {
      const [limit, offset] = params as [number, number];
      const sorted = [...this.users].sort(
        (a, b) => b.rating - a.rating || (a.id < b.id ? -1 : 1),
      );
      let rank = 0;
      let prev = Number.NaN;
      return sorted
        .map((u) => {
          if (u.rating !== prev) {
            prev = u.rating;
            rank = sorted.indexOf(u) + 1;
          }
          return { username: u.username, rating: u.rating, rank: String(rank) };
        })
        .slice(offset, offset + limit);
    }
    if (sql.includes('"u1"."id"')) {
      const me = this.users.find((u) => u.id === params[0]);
      if (!me) return [];
      const greater = this.users.filter((u) => u.rating > me.rating).length;
      return [{ username: me.username, rating: me.rating, rank: String(greater + 1) }];
    }
    return [{ count: String(this.users.length) }];
  }
}

class FakeRedisClient {
  readonly store = new Map<string, string>();
  readonly sets: Array<{ key: string; ttl: number }> = [];
  readonly gets: string[] = [];
  failGet = false;
  failSet = false;
  failIncr = false;
  failVersionRead = false;

  async get(key: string): Promise<string | null> {
    this.gets.push(key);
    if (key === LEADERBOARD_VERSION_KEY && this.failVersionRead) {
      throw new Error('Redis down');
    }
    if (key !== LEADERBOARD_VERSION_KEY && this.failGet) throw new Error('Redis down');
    return this.store.get(key) ?? null;
  }

  async set(key: string, value: string, mode: string, ttl: number): Promise<string> {
    if (this.failSet) throw new Error('Redis down');
    if (mode !== 'EX') throw new Error(`expected EX, got ${mode}`);
    this.store.set(key, value);
    this.sets.push({ key, ttl });
    return 'OK';
  }

  async incr(key: string): Promise<number> {
    if (this.failIncr) throw new Error('Redis down');
    const next = Number(this.store.get(key) ?? '0') + 1;
    this.store.set(key, String(next));
    return next;
  }
}

const USERS: UserRow[] = [
  { id: 'u1', username: 'MoonKnight', rating: 2000 },
  { id: 'u2', username: 'BlueRanger', rating: 2000 },
  { id: 'u3', username: 'StoneGuard', rating: 1800 },
  { id: 'u4', username: 'JaJoJi', rating: 1700 },
];

const makeService = (users: UserRow[] = USERS) => {
  const pg = new FakeDataSource(users);
  const client = new FakeRedisClient();
  const service = new LeaderboardService(pg as any, { client } as any);
  return { pg, client, service };
};

describe('LeaderboardService (#256)', () => {
  it('returns RANK() gaps, not row numbers (1,1,3,4)', async () => {
    const { service } = makeService();
    const res = await service.getLeaderboard('u4', 20, 0);
    expect(res.entries.map((e) => e.rank)).toEqual([1, 1, 3, 4]);
    expect(res.total).toBe(4);
    expect(res.limit).toBe(20);
    expect(res.offset).toBe(0);
  });

  it('orders ties deterministically by id ASC', async () => {
    const { service } = makeService();
    const res = await service.getLeaderboard('u4', 2, 0);
    expect(res.entries.map((e) => e.username)).toEqual(['MoonKnight', 'BlueRanger']);
  });

  it('paginates with limit/offset', async () => {
    const { service } = makeService();
    const res = await service.getLeaderboard('u4', 2, 1);
    expect(res.entries.map((e) => e.username)).toEqual(['BlueRanger', 'StoneGuard']);
    expect(res.entries.map((e) => e.rank)).toEqual([1, 3]);
  });

  it('always returns me, even outside the page', async () => {
    const { service } = makeService();
    const res = await service.getLeaderboard('u4', 1, 0);
    expect(res.entries).toHaveLength(1);
    expect(res.me).toEqual({ rank: 4, username: 'JaJoJi', rating: 1700 });
  });

  it('returns me inside the top page with the same rank', async () => {
    const { service } = makeService();
    const res = await service.getLeaderboard('u1', 20, 0);
    expect(res.me).toEqual({ rank: 1, username: 'MoonKnight', rating: 2000 });
  });

  it('throws for an unknown caller instead of inventing a rank', async () => {
    const { service } = makeService();
    await expect(service.getLeaderboard('ghost', 20, 0)).rejects.toMatchObject({
      status: 409,
    });
  });

  it('issues RANK() window plus deterministic ordering SQL', async () => {
    const { pg, service } = makeService();
    await service.getLeaderboard('u4', 20, 0);
    const sql = pg.queries.map((q) => q.sql).join('\n');
    expect(sql).toContain('RANK() OVER (ORDER BY "rating" DESC)');
    expect(sql).toContain('ORDER BY "rating" DESC, "id" ASC');
    expect(sql).not.toContain('ROW_NUMBER()');
  });

  it('MISS caches with versioned key and ~30s TTL; HIT skips PG', async () => {
    const { pg, client, service } = makeService();
    const first = await service.getLeaderboard('u4', 20, 0);
    expect(client.sets).toEqual([
      { key: leaderboardCacheKey('0', 20, 0), ttl: LEADERBOARD_CACHE_TTL_SECONDS },
    ]);
    expect(LEADERBOARD_CACHE_TTL_SECONDS).toBe(30);

    pg.queries.length = 0;
    await expect(service.getLeaderboard('u4', 20, 0)).resolves.toEqual(first);
    expect(pg.queries).toHaveLength(0);
  });

  it('version bump retires old keys without DEL', async () => {
    const { pg, client, service } = makeService();
    await service.getLeaderboard('u4', 20, 0);
    await service.bumpVersion();
    pg.queries.length = 0;
    await service.getLeaderboard('u4', 20, 0);
    expect(pg.queries.length).toBeGreaterThan(0);
    expect(client.sets.at(-1)?.key).toBe(leaderboardCacheKey('1', 20, 0));
  });

  it('fails open to PG on Redis GET/SET/version failures', async () => {
    const { client, service } = makeService();
    client.failGet = true;
    client.failSet = true;
    await expect(service.getLeaderboard('u4', 20, 0)).resolves.toMatchObject({
      total: 4,
      me: { rank: 4, username: 'JaJoJi' },
    });

    client.failGet = false;
    client.failSet = false;
    client.failVersionRead = true;
    await expect(service.getLeaderboard('u4', 20, 0)).resolves.toMatchObject({
      total: 4,
    });
    expect(client.sets).toHaveLength(0);
  });

  it('bumpVersion never throws', async () => {
    const { client, service } = makeService();
    client.failIncr = true;
    await expect(service.bumpVersion()).resolves.toBeUndefined();
  });
});
