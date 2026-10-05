jest.mock('@nestjs/bullmq', () => ({
  Processor: () => () => undefined,
  WorkerHost: class WorkerHost {},
  InjectQueue: () => () => undefined,
}));

import { JOB_NAMES } from './queue.constants';
import {
  CombatDoneTimeoutProcessor,
  DisconnectDetectProcessor,
  PhaseTimerProcessor,
} from './queue.processors';
import { MatchCleanupWorker } from './workers/queue.workers';
import RedisMock from 'ioredis-mock';
import { randomUUID } from 'crypto';

const roundJob = (name: string, matchId = 'match-1', round = 2) =>
  ({ name, data: { matchId, round } }) as any;

describe('PhaseTimerProcessor (#307)', () => {
  it('ignores unknown job names without touching the runtime', async () => {
    const runtime = { tryStartCombat: jest.fn() };
    const processor = new PhaseTimerProcessor(runtime as any);
    await processor.process({ name: 'something-else', data: {} } as any);
    expect(runtime.tryStartCombat).not.toHaveBeenCalled();
  });

  it('delegates phase starts and passes the started flag through', async () => {
    const runtime = { tryStartCombat: jest.fn(async () => true) };
    const processor = new PhaseTimerProcessor(runtime as any);
    await processor.process(roundJob(JOB_NAMES.PHASE_START));
    expect(runtime.tryStartCombat).toHaveBeenCalledWith('match-1', 2);
  });

  it('a stale timer for an already-advanced round is a safe no-op', async () => {
    // tryStartCombat returns false when phase/round moved on (CAS loser);
    // the processor must not retry or throw.
    const runtime = { tryStartCombat: jest.fn(async () => false) };
    const processor = new PhaseTimerProcessor(runtime as any);
    await expect(
      processor.process(roundJob(JOB_NAMES.PHASE_START, 'match-1', 1)),
    ).resolves.toBeUndefined();
    expect(runtime.tryStartCombat).toHaveBeenCalledWith('match-1', 1);
  });
});

describe('CombatDoneTimeoutProcessor (#307)', () => {
  it('ignores unknown job names', async () => {
    const runtime = { applyDamageAndAdvance: jest.fn() };
    const processor = new CombatDoneTimeoutProcessor(runtime as any);
    await processor.process({ name: 'nope', data: {} } as any);
    expect(runtime.applyDamageAndAdvance).not.toHaveBeenCalled();
  });

  it('fires the shared advance path so late timeouts converge safely', async () => {
    const runtime = { applyDamageAndAdvance: jest.fn(async () => true) };
    const processor = new CombatDoneTimeoutProcessor(runtime as any);
    await processor.process(roundJob(JOB_NAMES.COMBAT_DONE_TIMEOUT));
    expect(runtime.applyDamageAndAdvance).toHaveBeenCalledWith('match-1', 2);
  });

  it('a timeout arriving after both acks already advanced is a no-op', async () => {
    const runtime = { applyDamageAndAdvance: jest.fn(async () => false) };
    const processor = new CombatDoneTimeoutProcessor(runtime as any);
    await expect(
      processor.process(roundJob(JOB_NAMES.COMBAT_DONE_TIMEOUT)),
    ).resolves.toBeUndefined();
  });

  it('advances a resolved round when the ready grace expires', async () => {
    const runtime = { advanceResolvedRound: jest.fn(async () => true) };
    const processor = new CombatDoneTimeoutProcessor(runtime as any);
    await processor.process(roundJob(JOB_NAMES.ROUND_READY_TIMEOUT));
    expect(runtime.advanceResolvedRound).toHaveBeenCalledWith('match-1', 2);
  });
});

describe('DisconnectDetectProcessor (#307)', () => {
  it('ignores unknown job names', async () => {
    const runtime = { handleDisconnect: jest.fn() };
    const processor = new DisconnectDetectProcessor(runtime as any);
    await processor.process({ name: 'nope', data: {} } as any);
    expect(runtime.handleDisconnect).not.toHaveBeenCalled();
  });

  it('forwards the explicit match+user form so stale jobs cannot hit newer matches', async () => {
    const runtime = { handleDisconnect: jest.fn(async () => true) };
    const processor = new DisconnectDetectProcessor(runtime as any);
    await processor.process({
      name: JOB_NAMES.DISCONNECT_DETECT,
      data: { matchId: 'match-1', userId: 'player-1' },
    } as any);
    expect(runtime.handleDisconnect).toHaveBeenCalledWith('match-1', 'player-1');
  });
});

describe('MatchCleanupWorker (#388)', () => {
  it('runs retention for the scheduled job and lets BullMQ retry failures', async () => {
    const retention = { run: jest.fn().mockRejectedValueOnce(new Error('database unavailable')) };
    const worker = new MatchCleanupWorker(retention as any, {} as any, {} as any);
    const job = { name: JOB_NAMES.MATCH_RETENTION_RUN, data: {} } as any;

    await expect(worker.process(job)).rejects.toThrow('database unavailable');
    await expect(worker.process(job)).resolves.toBeUndefined();
    expect(retention.run).toHaveBeenCalledTimes(2);
  });
});

describe('MatchCleanupWorker (#389)', () => {
  const matchId = randomUUID();
  const liveId = randomUUID();
  let client: InstanceType<typeof RedisMock>;
  let rows: Map<string, { status: string; finishedAt: Date | null }>;
  let worker: MatchCleanupWorker;

  beforeEach(() => {
    client = new RedisMock();
    rows = new Map([
      [matchId, { status: 'finished', finishedAt: new Date() }],
      [liveId, { status: 'in_progress', finishedAt: null }],
    ]);
    worker = new MatchCleanupWorker(
      { run: jest.fn() } as any,
      { query: async (_sql: string, [id]: string[]) => rows.has(id) ? [rows.get(id)] : [] } as any,
      { client } as any,
    );
  });

  afterEach(async () => { await client.quit(); });

  it('removes only terminal match runtime, shop, combat and transient keys; repeat is safe', async () => {
    const own = ['runtime', 'shop:p1', 'shop-lock:p1', 'actionLog:p1', 'combat-result', 'combat-done']
      .map((suffix) => `match:${matchId}:${suffix}`);
    for (const key of own) await client.set(key, 'data');
    const foreign = `match:${liveId}:runtime`;
    await client.set(foreign, 'live');
    await worker.process({ name: JOB_NAMES.MATCH_CLEANUP, data: { matchId } } as any);
    await worker.process({ name: JOB_NAMES.MATCH_CLEANUP, data: { matchId } } as any);
    for (const key of own) expect(await client.exists(key)).toBe(0);
    expect(await client.get(foreign)).toBe('live');
  });

  it('leaves a live match untouched even when a stale cleanup job arrives', async () => {
    const key = `match:${liveId}:runtime`;
    await client.set(key, 'live');
    await worker.process({ name: JOB_NAMES.MATCH_CLEANUP, data: { matchId: liveId } } as any);
    expect(await client.get(key)).toBe('live');
  });

  it('propagates Redis errors so BullMQ retries, then removes the key', async () => {
    const key = `match:${matchId}:runtime`;
    await client.set(key, 'old');
    const unlink = client.unlink.bind(client);
    const failOnce = jest.spyOn(client, 'unlink').mockRejectedValueOnce(new Error('redis unavailable'));
    const job = { name: JOB_NAMES.MATCH_CLEANUP, data: { matchId } } as any;
    await expect(worker.process(job)).rejects.toThrow('redis unavailable');
    expect(await client.exists(key)).toBe(1);
    failOnce.mockImplementation(unlink);
    await expect(worker.process(job)).resolves.toBeUndefined();
    expect(await client.exists(key)).toBe(0);
  });

  it('rejects unsafe IDs before scanning Redis', async () => {
    await expect(worker.process({ name: JOB_NAMES.MATCH_CLEANUP, data: { matchId: '*' } } as any))
      .rejects.toThrow('Invalid match-cleanup matchId');
  });
});
