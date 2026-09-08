import Redis from 'ioredis';
import { LUA_SCRIPTS } from './index';

interface ScriptLoadResult {
  name: string;
  sha: string;
}

interface ScriptExistsResult {
  name: string;
  exists: boolean;
}

async function run() {
  const client = new Redis({ port: 6390, lazyConnect: false });

  // 1. SCRIPT LOAD each script the way RedisService.onModuleInit does.
  const loaded: ScriptLoadResult[] = [];
  for (const [name, source] of Object.entries(LUA_SCRIPTS)) {
    const sha = (await client.script('LOAD', source)) as string;
    loaded.push({ name, sha });
    console.log(`[load] ${name.padEnd(12)} sha=${sha}`);
  }

  if (loaded.length !== 4) {
    throw new Error(`Expected 4 scripts loaded, got ${loaded.length}`);
  }

  // 2. SCRIPT EXISTS — verify all 4 SHAs are in the cache.
  const shas = loaded.map((l) => l.sha);
  const exists = (await client.script('EXISTS', ...shas)) as number[];
  const existsReport: ScriptExistsResult[] = loaded.map((l, i) => ({
    name: l.name,
    exists: exists[i] === 1,
  }));
  console.log('[exists]', existsReport);

  const allPresent = existsReport.every((r) => r.exists);
  if (!allPresent) throw new Error('Some scripts missing from cache');

  // 3. EVALSHA — run each script by SHA, expect the placeholder return values.
  const evalshaResults: { name: string; result: unknown }[] = [];
  for (const l of loaded) {
    let result: unknown;
    if (l.name === 'match_pair') {
      result = await client.evalsha(l.sha, 0);
    } else {
      result = await client.evalsha(l.sha, 1, 'match:abc:runtime', 'shop_place');
    }
    evalshaResults.push({ name: l.name, result });
  }
  console.log('[evalsha]', evalshaResults);

  // Verify the actual return values match the placeholder contract.
  // NB: In RESP, a Lua `return false` becomes NIL → `null` in JS.
  const expectedReturn: Record<string, unknown> = {
    phase_flip: 1,
    combat_done: 1,
    action_log: 1,
    match_pair: null,
  };
  for (const r of evalshaResults) {
    if (r.result !== expectedReturn[r.name]) {
      throw new Error(
        `Unexpected result for ${r.name}: got ${JSON.stringify(r.result)}, expected ${JSON.stringify(expectedReturn[r.name])}`,
      );
    }
  }

  // 4. NOSCRIPT fallback — SCRIPT FLUSH the cache, then EVALSHA again.
  await client.script('FLUSH');
  const afterFlush = (await client.script('EXISTS', shas[0])) as number[];
  if (afterFlush[0] !== 0) {
    throw new Error('SCRIPT FLUSH did not clear cache');
  }
  console.log('[flush] cache cleared, sha[0] no longer cached');

  const sha = shas[0];
  try {
    await client.evalsha(sha, 1, 'match:abc:runtime', 'shop_place');
    throw new Error('Expected NOSCRIPT error after flush');
  } catch (e: any) {
    if (!String(e?.message ?? '').includes('NOSCRIPT')) {
      throw new Error(`Expected NOSCRIPT error, got: ${e?.message}`);
    }
    console.log('[evalsha] NOSCRIPT error reproduced:', e.message.split('\n')[0]);
  }
  // Reload and retry — this is exactly what RedisService.eval<T>() does.
  const reloaded = (await client.script('LOAD', LUA_SCRIPTS.phase_flip)) as string;
  const retried = await client.evalsha(reloaded, 1, 'match:abc:runtime', 'shop_place');
  console.log('[evalsha-retry] phase_flip returned', retried, 'after reload');
  if (retried !== 1) throw new Error('Retry after reload did not return 1');

  console.log('\n[OK] All 5 smoke checks passed:');
  console.log('  - 4 Lua scripts SCRIPT LOADed and SCRIPT EXISTS');
  console.log('  - EVALSHA returns expected placeholder values');
  console.log('  - NOSCRIPT error reproduced after SCRIPT FLUSH');
  console.log('  - SCRIPT LOAD + EVALSHA retry path returns the expected value');

  await client.quit();
}

run().catch((err) => {
  console.error('[FAIL]', err);
  process.exit(1);
});
