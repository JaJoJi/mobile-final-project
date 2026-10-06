jest.mock('@nestjs/bullmq', () => ({
  Processor: () => () => undefined,
  WorkerHost: class WorkerHost {},
}));

import { randomUUID } from 'crypto';
import RedisMock from 'ioredis-mock';
import { JOB_NAMES } from '../queue/queue.constants';
import { MatchCleanupWorker } from '../queue/workers/queue.workers';
import { MatchService, MatchEndReason } from './match.service';

describe('match terminal cleanup integration (#389)', () => {
  it.each([
    ['successful', 'hp_zero', 'p2'],
    ['failed or surrendered', 'forfeit', 'p2'],
    ['abandoned', 'forfeit', null],
    ['disconnected', 'disconnect', 'p2'],
  ] as Array<[string, MatchEndReason, string | null]>)('%s match enqueues and removes its transient state', async (_label, reason, winnerId) => {
    const matchId = randomUUID();
    const otherId = randomUUID();
    const client = new RedisMock();
    const match = {
      id: matchId, status: 'in_progress', finishedAt: null as Date | null,
      player1Id: 'p1', player2Id: 'p2', winnerId: null as string | null,
      p1State: { hp: 0 }, p2State: { hp: 10 },
    };
    const jobs: string[] = [];
    const dataSource = {
      transaction: async (work: (manager: object) => Promise<unknown>) => work({}),
      query: async (_sql: string, [id]: string[]) => id === matchId ? [match] : [],
    };
    const service = new MatchService(
      dataSource as any,
      {
        findByIdForUpdate: async () => match,
        finalize: async (_match: unknown, input: { status: string; finishedAt: Date; winnerId: string | null }) => Object.assign(match, input),
      } as any,
      { publish: async () => undefined } as any,
      {
        findByIdsForUpdate: async () => [{ id: 'p1', rating: 1000 }, { id: 'p2', rating: 1000 }],
        updateRating: async () => undefined,
      } as any,
      { invalidateUsers: async () => undefined } as any,
      { bumpVersion: async () => undefined } as any,
      { scheduleMatchCleanup: async (id: string) => { jobs.push(id); } } as any,
    );
    const worker = new MatchCleanupWorker(
      { run: async () => undefined } as any,
      dataSource as any,
      { client } as any,
    );
    const own = [`match:${matchId}:runtime`, `match:${matchId}:shop:p1`, `match:${matchId}:combat-result`];
    for (const key of own) await client.set(key, 'stale');
    await client.set(`match:${otherId}:runtime`, 'live');

    try {
      await expect(service.finalize(matchId, winnerId, reason)).resolves.toBe(true);
      expect(jobs).toEqual([matchId]);
      const job = { name: JOB_NAMES.MATCH_CLEANUP, data: { matchId } } as any;
      await worker.process(job);
      await worker.process(job);
      for (const key of own) expect(await client.exists(key)).toBe(0);
      expect(await client.get(`match:${otherId}:runtime`)).toBe('live');
    } finally {
      await client.quit();
    }
  });
});
