import { readFileSync } from 'fs';
import { join } from 'path';
import RedisMock from 'ioredis-mock';

/**
 * Behavioural tests for the atomic Lua primitives (P3-BE-02).
 *
 * Runs each script through `EVAL` against an in-memory Redis
 * (`ioredis-mock`) — no server, no `SCRIPT LOAD`. The SHA-cache /
 * NOSCRIPT-reload plumbing in `RedisService.eval()` is exercised
 * separately by `scripts/smoke.ts` against a real Redis.
 */
const load = (name: string): string =>
  readFileSync(join(__dirname, `${name}.lua`), 'utf8');

describe('phase_flip.lua — atomic CAS phase transition (R6/R10)', () => {
  let redis: InstanceType<typeof RedisMock>;
  const src = load('phase_flip');
  const rt = 'match:m1:runtime';

  beforeEach(async () => {
    redis = new RedisMock();
    await redis.flushall();
    await redis.hset(rt, 'phase', 'shop_place');
  });

  it('flips when the expected phase matches and tags the lock on entering battle', async () => {
    const ret = await redis.eval(src, 1, rt, 'shop_place', 'battle', 'inst-7');
    expect(ret).toBe(1);
    expect(await redis.hget(rt, 'phase')).toBe('battle');
    expect(await redis.hget(rt, 'combatLockInstance')).toBe('inst-7');
  });

  it('is a no-op and returns 0 when the current phase does not match (lost CAS)', async () => {
    const ret = await redis.eval(src, 1, rt, 'battle', 'resolved', 'inst-7');
    expect(ret).toBe(0);
    expect(await redis.hget(rt, 'phase')).toBe('shop_place');
  });

  it('does not tag combatLockInstance for a non-battle transition', async () => {
    await redis.hset(rt, 'phase', 'battle');
    await redis.eval(src, 1, rt, 'battle', 'resolved', 'inst-7');
    expect(await redis.hget(rt, 'combatLockInstance')).toBeNull();
  });
});

describe('combat_done.lua — idempotent per-player ack (R12)', () => {
  let redis: InstanceType<typeof RedisMock>;
  const src = load('combat_done');
  const key = 'match:m1:combat-done';

  beforeEach(async () => {
    redis = new RedisMock();
    await redis.flushall();
  });

  it('counts distinct acks and ignores a repeat from the same player', async () => {
    expect(await redis.eval(src, 1, key, 'p1', '1000')).toBe(1);
    expect(await redis.eval(src, 1, key, 'p1', '2000')).toBe(1); // dup — no-op
    expect(await redis.eval(src, 1, key, 'p2', '3000')).toBe(2);
  });

  it('keeps the FIRST ack timestamp for a player', async () => {
    await redis.eval(src, 1, key, 'p1', '1000');
    await redis.eval(src, 1, key, 'p1', '9999');
    expect(await redis.hget(key, 'p1')).toBe('1000');
  });

  it('sets a TTL on the hash', async () => {
    await redis.eval(src, 1, key, 'p1', '1000');
    expect(await redis.ttl(key)).toBeGreaterThan(0);
  });
});

describe('action_log.lua — idempotent action write (R7)', () => {
  let redis: InstanceType<typeof RedisMock>;
  const src = load('action_log');
  const key = 'match:m1:actionLog:u1';

  beforeEach(async () => {
    redis = new RedisMock();
    await redis.flushall();
  });

  it('records a new clientActionId once, rejects the duplicate', async () => {
    expect(await redis.eval(src, 1, key, 'act-A', '1000')).toBe(1);
    expect(await redis.eval(src, 1, key, 'act-A', '2000')).toBe(0);
    expect(await redis.eval(src, 1, key, 'act-B', '3000')).toBe(1);
  });

  it('keeps the first timestamp and sets a TTL', async () => {
    await redis.eval(src, 1, key, 'act-A', '1000');
    await redis.eval(src, 1, key, 'act-A', '9999');
    expect(await redis.hget(key, 'act-A')).toBe('1000');
    expect(await redis.ttl(key)).toBeGreaterThan(0);
  });
});

describe('match_pair.lua — atomic FIFO pop (R4/R5)', () => {
  let redis: InstanceType<typeof RedisMock>;
  const src = load('match_pair');
  const q = 'matchmaking:queue';

  beforeEach(async () => {
    redis = new RedisMock();
    await redis.flushall();
  });

  it('returns the two longest-waiting members and removes them', async () => {
    await redis.zadd(q, 1, 'alice', 2, 'bob', 3, 'carol');
    const pair = await redis.eval(src, 1, q);
    expect(pair).toEqual(['alice', 'bob']);
    expect(await redis.zrange(q, 0, -1)).toEqual(['carol']);
  });

  it('returns an empty array and touches nothing with fewer than two members', async () => {
    await redis.zadd(q, 1, 'alice');
    expect(await redis.eval(src, 1, q)).toEqual([]);
    expect(await redis.zrange(q, 0, -1)).toEqual(['alice']);
  });

  it('is FIFO by score (join timestamp), not insertion order', async () => {
    await redis.zadd(q, 30, 'late', 10, 'early', 20, 'mid');
    expect(await redis.eval(src, 1, q)).toEqual(['early', 'mid']);
  });
});
