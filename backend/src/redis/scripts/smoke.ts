/**
 * Smoke harness for P0-BE-06 (Lua atomic primitives).
 *
 * Replaces the P0-BE-01 placeholder-return smoke with real-semantics
 * checks. Each scenario exercises the contract in `docs/03 §13` / §15:
 *
 *   phase_flip
 *     1. shop_place → battle succeeds, tags combatLockInstance
 *     2. repeat call (phase now battle) returns 0
 *     3. source-phase mismatch returns 0 (battle → resolved fails when expected=shop_place)
 *
 *   combat_done
 *     4. first ack returns 1 (count after insert)
 *     5. duplicate ack from same player returns 1 (no-op, still count 1)
 *     6. second player's ack returns 2; key has EXPIRE ≈ 90
 *
 *   action_log
 *     7. first action returns 1
 *     8. duplicate action returns 0
 *
 *   match_pair
 *     9. with 2 members in the queue, returns [userId1, userId2]
 *    10. with empty queue, returns []
 *
 *   regression (from P0-BE-01 smoke)
 *    11. SCRIPT FLUSH + EVALSHA reproduces NOSCRIPT; reload + retry works
 *
 * Run inside the docker network:
 *   docker compose exec nest-1 npx ts-node -T src/redis/scripts/smoke.ts
 * Or from the host against an exposed Redis on :6390 (see package.json smoke):
 *   REDIS_URL=redis://localhost:6390 npx ts-node -T src/redis/scripts/smoke.ts
 */
import Redis from 'ioredis';
import { LUA_SCRIPTS } from './index';

interface ScriptLoadResult {
  name: string;
  sha: string;
}

interface TestResult {
  name: string;
  passed: boolean;
  detail: string;
}

const REDIS_URL = process.env.REDIS_URL ?? 'redis://localhost:6390';
const KEY = (suffix: string) => `smoke:${Date.now()}:${suffix}`;

async function run(): Promise<void> {
  const client = new Redis(REDIS_URL, { lazyConnect: false, maxRetriesPerRequest: 3 });
  await client.ping();
  console.log(`[connect] ${REDIS_URL}`);
  const results: TestResult[] = [];

  // ─── Load all 4 scripts the way RedisService.onModuleInit does ─────────
  const loaded: ScriptLoadResult[] = [];
  for (const [name, source] of Object.entries(LUA_SCRIPTS)) {
    const sha = (await client.script('LOAD', source)) as string;
    loaded.push({ name, sha });
    console.log(`[load] ${name.padEnd(12)} sha=${sha}`);
  }
  if (loaded.length !== 4) throw new Error(`Expected 4 scripts loaded, got ${loaded.length}`);
  const sha = (n: string) => loaded.find((l) => l.name === n)!.sha;

  // ─── phase_flip ────────────────────────────────────────────────────────
  const runtimeKey = KEY('runtime');
  await client.del(runtimeKey);
  await client.hset(runtimeKey, 'phase', 'shop_place');

  // 1. CAS: shop_place → battle
  {
    const ret = await client.evalsha(sha('phase_flip'), 1, runtimeKey, 'shop_place', 'battle', 'nest-1');
    const hash = await client.hgetall(runtimeKey);
    const ok =
      ret === 1 &&
      hash.phase === 'battle' &&
      hash.combatLockInstance === 'nest-1';
    results.push({
      name: '1. phase_flip shop_place → battle (success + tags combatLockInstance)',
      passed: ok,
      detail: `ret=${ret} hash=${JSON.stringify(hash)}`,
    });
  }
  // 2. repeat: phase is now battle, so shop_place expected → 0
  {
    const ret = await client.evalsha(sha('phase_flip'), 1, runtimeKey, 'shop_place', 'battle', 'nest-2');
    results.push({
      name: '2. phase_flip repeat (phase already advanced → 0)',
      passed: ret === 0,
      detail: `ret=${ret}`,
    });
  }
  // 3. battle → resolved fails when caller still expects shop_place (mismatch)
  {
    const ret = await client.evalsha(sha('phase_flip'), 1, runtimeKey, 'shop_place', 'resolved', 'nest-3');
    results.push({
      name: '3. phase_flip source-phase mismatch → 0',
      passed: ret === 0,
      detail: `ret=${ret}`,
    });
  }
  await client.del(runtimeKey);

  // ─── combat_done ───────────────────────────────────────────────────────
  const ackKey = KEY('combat-done');
  await client.del(ackKey);
  // 4. first ack
  {
    const ret = await client.evalsha(sha('combat_done'), 1, ackKey, 'u1', '100');
    results.push({
      name: '4. combat_done first ack (u1) → 1',
      passed: ret === 1,
      detail: `ret=${ret}`,
    });
  }
  // 5. duplicate from u1: must NOT change the stored timestamp, count stays 1
  {
    const ret = await client.evalsha(sha('combat_done'), 1, ackKey, 'u1', '999');
    const stored = await client.hget(ackKey, 'u1');
    results.push({
      name: '5. combat_done duplicate (u1) → 1, stored ts unchanged',
      passed: ret === 1 && stored === '100',
      detail: `ret=${ret} stored=${stored} (expected '100')`,
    });
  }
  // 6. second player: count → 2; key TTL ≈ 90
  {
    const ret = await client.evalsha(sha('combat_done'), 1, ackKey, 'u2', '300');
    const ttl = await client.ttl(ackKey);
    results.push({
      name: '6. combat_done second ack (u2) → 2, EXPIRE 90',
      passed: ret === 2 && ttl > 80 && ttl <= 90,
      detail: `ret=${ret} ttl=${ttl} (expected 81-90)`,
    });
  }
  await client.del(ackKey);

  // ─── action_log ────────────────────────────────────────────────────────
  const logKey = KEY('actionLog:u1');
  await client.del(logKey);
  // 7. first action
  {
    const ret = await client.evalsha(sha('action_log'), 1, logKey, 'act-1', '100');
    results.push({
      name: '7. action_log first → 1',
      passed: ret === 1,
      detail: `ret=${ret}`,
    });
  }
  // 8. duplicate action
  {
    const ret = await client.evalsha(sha('action_log'), 1, logKey, 'act-1', '200');
    const stored = await client.hget(logKey, 'act-1');
    const ttl = await client.ttl(logKey);
    results.push({
      name: '8. action_log duplicate → 0, ts unchanged, EXPIRE 120',
      passed: ret === 0 && stored === '100' && ttl > 110 && ttl <= 120,
      detail: `ret=${ret} stored=${stored} ttl=${ttl}`,
    });
  }
  await client.del(logKey);

  // ─── match_pair ────────────────────────────────────────────────────────
  const queueKey = KEY('matchmaking');
  await client.del(queueKey);
  // 9. two members
  {
    await client.zadd(queueKey, 1, 'user-A', 2, 'user-B');
    const ret = (await client.evalsha(sha('match_pair'), 1, queueKey)) as string[];
    const remaining = await client.zrange(queueKey, 0, -1);
    results.push({
      name: '9. match_pair with 2 members → [user-A, user-B], ZREM drains queue',
      passed:
        Array.isArray(ret) &&
        ret.length === 2 &&
        ret.includes('user-A') &&
        ret.includes('user-B') &&
        remaining.length === 0,
      detail: `ret=${JSON.stringify(ret)} remaining=${JSON.stringify(remaining)}`,
    });
  }
  // 10. empty queue
  {
    const ret = (await client.evalsha(sha('match_pair'), 1, queueKey)) as unknown[];
    results.push({
      name: '10. match_pair empty queue → []',
      passed: Array.isArray(ret) && ret.length === 0,
      detail: `ret=${JSON.stringify(ret)}`,
    });
  }
  await client.del(queueKey);

  // ─── regression: SCRIPT FLUSH + NOSCRIPT reload ───────────────────────
  {
    const flushSha = sha('phase_flip');
    await client.script('FLUSH');
    const after = (await client.script('EXISTS', flushSha)) as number[];
    if (after[0] !== 0) throw new Error('SCRIPT FLUSH did not clear cache');

    let gotNoscript = false;
    try {
      await client.evalsha(flushSha, 1, runtimeKey, 'shop_place', 'battle', 'nest-1');
    } catch (e: unknown) {
      gotNoscript = String((e as Error)?.message ?? '').includes('NOSCRIPT');
    }
    if (!gotNoscript) throw new Error('Expected NOSCRIPT after flush');

    // Reload + retry path (mirrors RedisService.eval<T>() NOSCRIPT fallback).
    const reloaded = (await client.script('LOAD', LUA_SCRIPTS.phase_flip)) as string;
    await client.del(runtimeKey);
    await client.hset(runtimeKey, 'phase', 'shop_place');
    const retried = await client.evalsha(reloaded, 1, runtimeKey, 'shop_place', 'battle', 'nest-1');
    results.push({
      name: '11. NOSCRIPT fallback (SCRIPT FLUSH → reload → retry works)',
      passed: retried === 1,
      detail: `reloadedSha=${reloaded} retried=${retried}`,
    });
    await client.del(runtimeKey);
  }

  // ─── Report ────────────────────────────────────────────────────────────
  await client.quit();

  console.log('\n[results]');
  let pass = 0;
  for (const r of results) {
    const tag = r.passed ? 'PASS' : 'FAIL';
    if (r.passed) pass++;
    console.log(`  ${tag}  ${r.name.padEnd(62)} ${r.detail}`);
  }
  console.log(`\n[summary] ${pass}/${results.length} passed`);

  if (pass !== results.length) process.exit(1);
}

run().catch((e: unknown) => {
  console.error('[FAIL]', e);
  process.exit(1);
});
