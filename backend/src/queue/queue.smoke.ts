/**
 * Smoke harness for P0-BE-03 (BullMQ queues + workers).
 *
 * Connects to Redis, schedules one job per queue, and reports the
 * resulting BullMQ Redis keys. Verifies the producers can enqueue
 * jobs into every queue and that the workers (running inside the
 * Nest instances) actually pick them up. Worker processing is
 * confirmed separately via `docker compose logs nest-1 nest-2 nest-3
 * | grep "\[phase-timer\]"` etc.
 *
 * Run inside the docker network, e.g.:
 *   docker compose exec nest-1 npx ts-node -T src/queue/queue.smoke.ts
 * or from the host against an exposed Redis:
 *   REDIS_URL=redis://localhost:6379 npx ts-node -T src/queue/queue.smoke.ts
 */
import { Queue } from 'bullmq';
import { randomUUID } from 'crypto';
import Redis from 'ioredis';
import { JOB_NAMES, QUEUE_NAMES } from './queue.constants';

interface Result {
  queue: string;
  jobName: string;
  jobId: string | undefined;
  delayed: boolean;
  repeatable: boolean;
  scheduledAt: number;
}

async function run() {
  const url = process.env.REDIS_URL ?? 'redis://localhost:6379';
  const connection = new Redis(url, { maxRetriesPerRequest: 3 });
  await connection.ping();
  console.log('[connect]', url);

  const results: Result[] = [];
  const start = Date.now();
  const smokeMatchId = randomUUID();
  const smokeUserId = randomUUID();

  // 1. phase-timer — delayed 2 s
  const phaseQ = new Queue(QUEUE_NAMES.PHASE_TIMER, { connection });
  const phaseJob = await phaseQ.add(JOB_NAMES.PHASE_START, { matchId: smokeMatchId, round: 1 }, { delay: 2000 });
  results.push({
    queue: QUEUE_NAMES.PHASE_TIMER,
    jobName: JOB_NAMES.PHASE_START,
    jobId: phaseJob.id,
    delayed: phaseJob.opts.delay === 2000,
    repeatable: false,
    scheduledAt: start,
  });

  // 2. combat-done-timeout — delayed 3 s
  const combatQ = new Queue(QUEUE_NAMES.COMBAT_DONE_TIMEOUT, { connection });
  const combatJob = await combatQ.add(JOB_NAMES.COMBAT_DONE_TIMEOUT, { matchId: smokeMatchId, round: 1 }, { delay: 3000 });
  results.push({
    queue: QUEUE_NAMES.COMBAT_DONE_TIMEOUT,
    jobName: JOB_NAMES.COMBAT_DONE_TIMEOUT,
    jobId: combatJob.id,
    delayed: combatJob.opts.delay === 3000,
    repeatable: false,
    scheduledAt: start,
  });

  // 3. disconnect-detect — delayed 4 s
  const discQ = new Queue(QUEUE_NAMES.DISCONNECT_DETECT, { connection });
  const discJob = await discQ.add(JOB_NAMES.DISCONNECT_DETECT, { matchId: smokeMatchId, userId: smokeUserId }, { delay: 4000 });
  results.push({
    queue: QUEUE_NAMES.DISCONNECT_DETECT,
    jobName: JOB_NAMES.DISCONNECT_DETECT,
    jobId: discJob.id,
    delayed: discJob.opts.delay === 4000,
    repeatable: false,
    scheduledAt: start,
  });

  // 4. match-pair — repeatable every 1500 ms, limited to 2 occurrences
  //    (smaller than production 1000 ms for faster smoke verification)
  const pairQ = new Queue(QUEUE_NAMES.MATCH_PAIR, { connection });
  const pairJob = await pairQ.add(
    JOB_NAMES.MATCH_PAIR,
    {},
    { repeat: { every: 1500, limit: 2 }, jobId: 'smoke-match-pair' },
  );
  results.push({
    queue: QUEUE_NAMES.MATCH_PAIR,
    jobName: JOB_NAMES.MATCH_PAIR,
    jobId: pairJob.id,
    delayed: false,
    repeatable: true,
    scheduledAt: start,
  });

  // 5. match-cleanup — scheduled at +5s
  const cleanupAt = Date.now() + 5000;
  const cleanQ = new Queue(QUEUE_NAMES.MATCH_CLEANUP, { connection });
  const cleanJob = await cleanQ.add(
    JOB_NAMES.MATCH_CLEANUP,
    { matchId: smokeMatchId },
    { delay: 5000, jobId: 'smoke-cleanup' },
  );
  results.push({
    queue: QUEUE_NAMES.MATCH_CLEANUP,
    jobName: JOB_NAMES.MATCH_CLEANUP,
    jobId: cleanJob.id,
    delayed: cleanJob.opts.delay === 5000,
    repeatable: false,
    scheduledAt: start,
  });

  // 6. Sanity: BullMQ keys are present in Redis
  const allKeys = await connection.keys('bull:*');
  const sampleKeys = allKeys.slice(0, 8).sort();
  console.log('\n[bullmq-keys]', allKeys.length, 'keys, sample:', sampleKeys);

  // 7. Report
  console.log('\n[scheduled]');
  for (const r of results) {
    console.log(
      `  ${r.queue.padEnd(22)} job=${r.jobName.padEnd(28)} id=${String(r.jobId).padEnd(6)} delayed=${r.delayed} repeatable=${r.repeatable}`,
    );
  }

  // 8. Wait for the longest delay (5s + jitter) so all delayed jobs are processed.
  //    The repeatable job has limit=2 + every=1500ms → ~3s total.
  console.log('\n[wait] 6 s — sleeping so workers can drain the smoke jobs...');
  await new Promise((r) => setTimeout(r, 6000));

  // 9. After drain — final state per queue
  console.log('\n[final-state]');
  for (const name of Object.values(QUEUE_NAMES)) {
    const counts = await new Queue(name, { connection }).getJobCounts();
    console.log(`  ${name.padEnd(22)} counts=${JSON.stringify(counts)}`);
  }

  // Cleanup
  await phaseQ.close();
  await combatQ.close();
  await discQ.close();
  await pairQ.close();
  await cleanQ.close();
  await connection.quit();

  console.log('\n[OK] smoke schedule complete. Check `docker compose logs` for worker processing lines.');
}

run().catch((e) => {
  console.error('[FAIL]', e);
  process.exit(1);
});
