jest.mock('@nestjs/bullmq', () => ({
  InjectQueue: () => () => undefined,
}));

import { DataSource } from 'typeorm';
import { RedisService } from '../redis/redis.service';
import { OperationalMetricsController } from './operational-metrics.controller';

describe('OperationalMetricsController (#391)', () => {
  it('exports database, Redis, and all BullMQ queue states for Prometheus', async () => {
    const dataSource = {
      query: jest.fn()
        .mockResolvedValueOnce([{ bytes: '4096' }])
        .mockResolvedValueOnce([
          { table_name: 'matches', bytes: '1024', rows: '7' },
          { table_name: 'match_rounds', bytes: '2048', rows: '15' },
        ]),
    } as unknown as DataSource;
    const scan = jest.fn(async (cursor: string, _match: string, pattern: string) => {
      if (pattern === 'match:*' && cursor === '0') return ['1', ['match:a']];
      if (pattern === 'match:*' && cursor === '1') return ['0', ['match:b']];
      return ['0', []];
    });
    const redis = {
      client: {
        info: jest.fn(async () => '# Memory\r\nused_memory:512\r\nmaxmemory:1024\r\n'),
        dbsize: jest.fn(async () => 6),
        scan,
      },
    } as unknown as RedisService;
    const queue = (waiting: number) => ({
      getJobCounts: jest.fn(async () => ({ waiting, active: 1, completed: 3, failed: 2, delayed: 4 })),
      getJobs: jest.fn(async () => waiting ? [{ timestamp: 4_000 }] : []),
    });
    const queues = [queue(2), queue(0), queue(0), queue(0), queue(0)];
    const now = jest.spyOn(Date, 'now').mockReturnValue(10_000);

    try {
      const controller = new OperationalMetricsController(
        dataSource,
        redis,
        queues[0] as any,
        queues[1] as any,
        queues[2] as any,
        queues[3] as any,
        queues[4] as any,
      );
      const body = await controller.metrics();

      expect(body).toContain('app_database_size_bytes 4096\n');
      expect(body).toContain('app_table_size_bytes{table="matches"} 1024\n');
      expect(body).toContain('app_table_rows_estimate{table="match_rounds"} 15\n');
      expect(body).toContain('app_redis_used_memory_bytes 512\n');
      expect(body).toContain('app_redis_maxmemory_bytes 1024\n');
      expect(body).toContain('app_redis_keys{namespace="match"} 2\n');
      expect(body).toContain('app_redis_keys{namespace="all"} 6\n');
      expect(body).toContain('app_bullmq_jobs{queue="phase-timer",state="waiting"} 2\n');
      expect(body).toContain('app_bullmq_jobs{queue="phase-timer",state="failed"} 2\n');
      expect(body).toContain('app_bullmq_oldest_waiting_age_seconds{queue="phase-timer"} 6\n');
      expect(body).toContain('app_bullmq_jobs{queue="match-cleanup",state="completed"} 3\n');
      expect(body.endsWith('\n')).toBe(true);
      expect(scan).toHaveBeenCalledWith('1', 'MATCH', 'match:*', 'COUNT', 1000);
      for (const namedQueue of queues) {
        expect(namedQueue.getJobCounts).toHaveBeenCalledWith(
          'waiting', 'active', 'completed', 'failed', 'delayed',
        );
      }
    } finally {
      now.mockRestore();
    }
  });
});
