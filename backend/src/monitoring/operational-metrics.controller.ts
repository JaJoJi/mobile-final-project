import { Controller, Get, Header, Inject } from '@nestjs/common';
import { InjectQueue } from '@nestjs/bullmq';
import { Queue } from 'bullmq';
import { DataSource } from 'typeorm';
import { RedisService } from '../redis/redis.service';
import { QUEUE_NAMES } from '../queue/queue.constants';

const QUEUES = Object.values(QUEUE_NAMES);
const REDIS_NAMESPACES = ['match:', 'room:', 'user:', 'matchmaking:', 'bull:'] as const;

@Controller()
export class OperationalMetricsController {
  constructor(
    private readonly dataSource: DataSource,
    private readonly redis: RedisService,
    @InjectQueue(QUEUE_NAMES.PHASE_TIMER) private readonly phaseTimer: Queue,
    @InjectQueue(QUEUE_NAMES.COMBAT_DONE_TIMEOUT) private readonly combatDone: Queue,
    @InjectQueue(QUEUE_NAMES.DISCONNECT_DETECT) private readonly disconnect: Queue,
    @InjectQueue(QUEUE_NAMES.MATCH_PAIR) private readonly matchPair: Queue,
    @InjectQueue(QUEUE_NAMES.MATCH_CLEANUP) private readonly cleanup: Queue,
  ) {}

  @Get('metrics')
  @Header('Content-Type', 'text/plain; version=0.0.4; charset=utf-8')
  async metrics(): Promise<string> {
    const lines = ['# HELP app_database_size_bytes PostgreSQL database size in bytes.', '# TYPE app_database_size_bytes gauge'];
    const [database] = await this.dataSource.query(
      `SELECT pg_database_size(current_database())::bigint AS bytes`,
    );
    lines.push(`app_database_size_bytes ${Number(database.bytes)}`);

    lines.push('# HELP app_table_size_bytes Total table and index size in bytes.', '# TYPE app_table_size_bytes gauge');
    lines.push('# HELP app_table_rows_estimate PostgreSQL planner row estimate.', '# TYPE app_table_rows_estimate gauge');
    const tables = await this.dataSource.query(
      `SELECT c.relname AS table_name,
              pg_total_relation_size(c.oid)::bigint AS bytes,
              GREATEST(c.reltuples, 0)::bigint AS rows
         FROM pg_class c
         JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = current_schema()
          AND c.relname IN ('matches', 'match_rounds')`,
    );
    for (const table of tables) {
      const labels = `{table="${table.table_name}"}`;
      lines.push(`app_table_size_bytes${labels} ${Number(table.bytes)}`);
      lines.push(`app_table_rows_estimate${labels} ${Number(table.rows)}`);
    }

    const info = await this.redis.client.info('memory');
    const usedMemory = this.infoNumber(info, 'used_memory');
    const maxMemory = this.infoNumber(info, 'maxmemory');
    lines.push('# HELP app_redis_used_memory_bytes Redis memory in use.', '# TYPE app_redis_used_memory_bytes gauge');
    lines.push(`app_redis_used_memory_bytes ${usedMemory}`);
    lines.push('# HELP app_redis_maxmemory_bytes Configured Redis memory limit; zero means unlimited.', '# TYPE app_redis_maxmemory_bytes gauge');
    lines.push(`app_redis_maxmemory_bytes ${maxMemory}`);
    lines.push('# HELP app_redis_keys Redis keys by top-level namespace.', '# TYPE app_redis_keys gauge');
    lines.push(`app_redis_keys{namespace="all"} ${await this.redis.client.dbsize()}`);
    for (const namespace of REDIS_NAMESPACES) {
      lines.push(`app_redis_keys{namespace="${namespace.slice(0, -1)}"} ${await this.countKeys(`${namespace}*`)}`);
    }

    lines.push('# HELP app_bullmq_jobs BullMQ jobs by queue and state.', '# TYPE app_bullmq_jobs gauge');
    lines.push('# HELP app_bullmq_oldest_waiting_age_seconds Age of the oldest waiting job.', '# TYPE app_bullmq_oldest_waiting_age_seconds gauge');
    for (const [name, queue] of this.queueEntries()) {
      const counts = await queue.getJobCounts('waiting', 'active', 'completed', 'failed', 'delayed');
      for (const state of ['waiting', 'active', 'completed', 'failed', 'delayed'] as const) {
        lines.push(`app_bullmq_jobs{queue="${name}",state="${state}"} ${counts[state] ?? 0}`);
      }
      const oldest = await queue.getJobs(['waiting'], 0, 0);
      const ageSeconds = oldest[0] ? Math.max(0, (Date.now() - oldest[0].timestamp) / 1000) : 0;
      lines.push(`app_bullmq_oldest_waiting_age_seconds{queue="${name}"} ${ageSeconds}`);
    }
    return `${lines.join('\n')}\n`;
  }

  private queueEntries(): Array<[string, Queue]> {
    return [
      [QUEUES[0], this.phaseTimer],
      [QUEUES[1], this.combatDone],
      [QUEUES[2], this.disconnect],
      [QUEUES[3], this.matchPair],
      [QUEUES[4], this.cleanup],
    ];
  }

  private infoNumber(info: string, name: string): number {
    const value = info.match(new RegExp(`^${name}:(\\d+)`, 'm'))?.[1];
    return value ? Number(value) : 0;
  }

  private async countKeys(pattern: string): Promise<number> {
    let cursor = '0';
    let count = 0;
    do {
      const [next, keys] = await this.redis.client.scan(cursor, 'MATCH', pattern, 'COUNT', 1000);
      cursor = next;
      count += keys.length;
    } while (cursor !== '0');
    return count;
  }
}
