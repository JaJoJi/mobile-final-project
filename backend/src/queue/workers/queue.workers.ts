import { Processor, WorkerHost } from '@nestjs/bullmq';
import { Logger } from '@nestjs/common';
import { Job } from 'bullmq';
import { DataSource } from 'typeorm';
import { MatchRetentionService } from '../../match/match-retention.service';
import { RedisService } from '../../redis/redis.service';
import { JOB_NAMES, QUEUE_NAMES } from '../queue.constants';

/**
 * Generic workers that do not require a domain orchestrator. Match-pair
 * processing lives in MatchmakingModule (P0-BE-11); phase, combat timeout,
 * and disconnect workers live in RuntimeModule (P0-BE-13) so Nest can inject
 * the runtime adapter without creating a QueueModule import cycle.
 *
 * Multi-instance behavior: every Nest replica starts one of each worker
 * and they ALL pull from the queue concurrently — jobs are load-balanced
 * across replicas. BullMQ locks each individual job while it is `active`
 * (a stalled job's lock expires and it is re-queued), so a given job is
 * processed by exactly one worker at a time.
 */

@Processor(QUEUE_NAMES.MATCH_CLEANUP)
export class MatchCleanupWorker extends WorkerHost {
  private readonly logger = new Logger(MatchCleanupWorker.name);

  constructor(
    private readonly retention: MatchRetentionService,
    private readonly dataSource: DataSource,
    private readonly redis: RedisService,
  ) {
    super();
  }

  async process(job: Job): Promise<void> {
    if (job.name === JOB_NAMES.MATCH_RETENTION_RUN) {
      await this.retention.run();
      return;
    }
    if (job.name !== JOB_NAMES.MATCH_CLEANUP) return;
    const matchId: unknown = job.data?.matchId;
    if (typeof matchId !== 'string' || !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(matchId)) {
      throw new Error('Invalid match-cleanup matchId');
    }

    // A queued job can outlive a failed finalize; only the primary can
    // confirm that this match is terminal before its Redis state is removed.
    const rows: Array<{ status: string; finishedAt: Date | null }> = await this.dataSource.query(
      'SELECT "status", "finishedAt" FROM "matches" WHERE "id" = $1',
      [matchId],
    );
    if (!rows.length || !['finished', 'forfeited'].includes(rows[0].status) || !rows[0].finishedAt) {
      this.logger.warn(`cleanup skipped for non-terminal match=${matchId}`);
      return;
    }

    const pattern = `match:${matchId}:*`;
    let cursor = '0';
    let removed = 0;
    do {
      const [next, keys] = await this.redis.client.scan(cursor, 'MATCH', pattern, 'COUNT', 200);
      cursor = next;
      if (keys.length) removed += await this.redis.client.unlink(...keys);
    } while (cursor !== '0');
    this.logger.log(`cleaned match=${matchId} keys=${removed}`);
  }
}

export const QUEUE_WORKERS = [
  MatchCleanupWorker,
];

// Re-export so external verifiers don't need to know the exact JOB_NAMES value.
export { JOB_NAMES, QUEUE_NAMES };
