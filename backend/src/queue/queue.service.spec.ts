// @nestjs/bullmq is ESM-only under ts-jest; stub the decorator factory.
// Specs inject fake queues directly, so no worker behavior is needed.
jest.mock('@nestjs/bullmq', () => ({
  InjectQueue: () => () => undefined,
}));

import { JOB_NAMES, QUEUE_NAMES } from './queue.constants';
import { QueueService } from './queue.service';

class FakeQueue {
  readonly added: Array<{ name: string; data: unknown; opts: unknown }> = [];
  repeatable: unknown[] = [];

  async add(name: string, data: unknown, opts: unknown): Promise<unknown> {
    this.added.push({ name, data, opts });
    return { id: `${name}-id` };
  }

  async getRepeatableJobs(): Promise<unknown[]> {
    return this.repeatable;
  }
}

const makeService = () => {
  const phaseTimer = new FakeQueue();
  const combatDoneTimeout = new FakeQueue();
  const disconnectDetect = new FakeQueue();
  const matchPair = new FakeQueue();
  const matchCleanup = new FakeQueue();
  const service = new QueueService(
    phaseTimer as any,
    combatDoneTimeout as any,
    disconnectDetect as any,
    matchPair as any,
    matchCleanup as any,
  );
  return { phaseTimer, combatDoneTimeout, disconnectDetect, matchPair, matchCleanup, service };
};

describe('QueueService job contracts (#306)', () => {
  it('schedules one daily retention run with retries across module starts', async () => {
    const { matchCleanup, service } = makeService();
    await service.onModuleInit();
    expect(matchCleanup.added).toEqual([{
      name: JOB_NAMES.MATCH_RETENTION_RUN,
      data: {},
      opts: expect.objectContaining({
        repeat: { every: 86_400_000 },
        jobId: 'match-retention-daily',
        attempts: 3,
        removeOnComplete: true,
      }),
    }]);

    matchCleanup.repeatable = [{ name: JOB_NAMES.MATCH_RETENTION_RUN, every: 86_400_000 }];
    await service.onModuleInit();
    expect(matchCleanup.added).toHaveLength(1);
  });

  it('schedules one phase timer per match+round (dedup by jobId)', async () => {
    const { phaseTimer, service } = makeService();
    await service.schedulePhaseStart('m1', 2, 40000);
    expect(phaseTimer.added).toEqual([
      {
        name: JOB_NAMES.PHASE_START,
        data: { matchId: 'm1', round: 2 },
        opts: expect.objectContaining({ delay: 40000, jobId: 'phase-m1-2' }),
      },
    ]);
    expect(QUEUE_NAMES.PHASE_TIMER).toBe('phase-timer');
  });

  it('schedules one combat-done timeout per match+round', async () => {
    const { combatDoneTimeout, service } = makeService();
    await service.scheduleCombatDoneTimeout('m1', 2, 65000);
    expect(combatDoneTimeout.added).toEqual([
      {
        name: JOB_NAMES.COMBAT_DONE_TIMEOUT,
        data: { matchId: 'm1', round: 2 },
        opts: expect.objectContaining({ delay: 65000, jobId: 'combat-done-timeout-m1-2' }),
      },
    ]);
  });

  it('schedules one round-ready grace timeout per match+round', async () => {
    const { combatDoneTimeout, service } = makeService();
    await service.scheduleRoundReadyTimeout('m1', 2, 3000);
    expect(combatDoneTimeout.added).toEqual([
      {
        name: JOB_NAMES.ROUND_READY_TIMEOUT,
        data: { matchId: 'm1', round: 2 },
        opts: expect.objectContaining({
          delay: 3000,
          jobId: 'round-ready-timeout-m1-2',
        }),
      },
    ]);
  });

  it('schedules one disconnect check per match+user', async () => {
    const { disconnectDetect, service } = makeService();
    await service.scheduleDisconnectDetect('m1', 'u1', 30000);
    expect(disconnectDetect.added).toEqual([
      {
        name: JOB_NAMES.DISCONNECT_DETECT,
        data: { matchId: 'm1', userId: 'u1' },
        opts: expect.objectContaining({ delay: 30000, jobId: 'disconnect-m1-u1' }),
      },
    ]);
  });

  it('does not duplicate the match-pair poller when already scheduled', async () => {
    const { matchPair, service } = makeService();
    matchPair.repeatable = [{ name: JOB_NAMES.MATCH_PAIR, every: 1000 }];
    await service.ensureMatchPairRepeating(1000);
    expect(matchPair.added).toHaveLength(0);
  });

  it('creates the match-pair poller once with repeat + bounded retention', async () => {
    const { matchPair, service } = makeService();
    await service.ensureMatchPairRepeating(1000);
    expect(matchPair.added).toEqual([
      {
        name: JOB_NAMES.MATCH_PAIR,
        data: {},
        opts: expect.objectContaining({
          jobId: 'match-pair-every-1000',
          removeOnComplete: true,
        }),
      },
    ]);
  });

  it('schedules cleanup with non-negative delay from the target epoch', async () => {
    const { matchCleanup, service } = makeService();
    const now = Date.now();
    await service.scheduleMatchCleanup('m1', now + 5000);
    expect(matchCleanup.added[0]).toMatchObject({
      name: JOB_NAMES.MATCH_CLEANUP,
      data: { matchId: 'm1' },
    });
    const delay = (matchCleanup.added[0].opts as { delay: number }).delay;
    expect(delay).toBeGreaterThan(0);
    expect(delay).toBeLessThanOrEqual(5000);

    await service.scheduleMatchCleanup('m1', now - 1000);
    expect((matchCleanup.added[1].opts as { delay: number }).delay).toBe(0);
  });
});
