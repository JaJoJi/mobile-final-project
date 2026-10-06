import { QUEUE_NAMES } from './queue.constants';
import { cleanRetainedJobs } from './queue-retention.service';
import { JOB_RETENTION, queueConnectionOptions } from './queue.retention';

describe('BullMQ retention (#390)', () => {
  it('sets the same defaults for every registered queue', () => {
    const client = {};
    const options = queueConnectionOptions({ bullClient: client } as any);
    expect(options).toEqual({ connection: client, defaultJobOptions: JOB_RETENTION });
    expect(JOB_RETENTION).toEqual({ removeOnComplete: true, removeOnFail: 100 });
  });

  it('previews each queue without deleting any jobs', async () => {
    const clean = jest.fn();
    const queues = Object.fromEntries(Object.values(QUEUE_NAMES).map((name) => [name, {
      getJobCounts: jest.fn(async () => ({ completed: 1200, failed: 150 })),
      clean,
    }]));
    const report = await cleanRetainedJobs(queues as any);
    expect(report).toHaveLength(5);
    expect(report[0]).toMatchObject({ completed: 1200, failed: 150, completedRemoved: 0, failedRemoved: 0, apply: false });
    expect(clean).not.toHaveBeenCalled();
  });

  it('cleans only old completed/failed jobs in bounded batches', async () => {
    const clean = jest.fn(async (_grace: number, _limit: number, state: string) =>
      state === 'completed' ? ['c1', 'c2'] : ['f1']);
    const queues = Object.fromEntries(Object.values(QUEUE_NAMES).map((name) => [name, {
      getJobCounts: jest.fn(async () => ({ completed: 1200, failed: 150 })),
      clean,
    }]));
    const report = await cleanRetainedJobs(queues as any, true);
    expect(report.every((row) => row.completedRemoved === 2 && row.failedRemoved === 1)).toBe(true);
    expect(clean).toHaveBeenCalledTimes(10);
    for (const [grace, limit, state] of clean.mock.calls) {
      expect(limit).toBe(1000);
      expect(grace).toBeGreaterThan(0);
      expect(['completed', 'failed']).toContain(state);
    }
    expect(clean).toHaveBeenCalledWith(60 * 60 * 1000, 1000, 'completed');
    expect(clean).toHaveBeenCalledWith(7 * 24 * 60 * 60 * 1000, 1000, 'failed');
  });
});
