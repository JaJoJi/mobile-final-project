import { Global, Module } from '@nestjs/common';
import { BullModule } from '@nestjs/bullmq';
import { RedisService } from '../redis/redis.service';
import { QUEUE_NAMES } from './queue.constants';
import { QueueService } from './queue.service';
import { QUEUE_WORKERS } from './workers/queue.workers';

/**
 * BullMQ wiring for the orchestrator's delayed / repeatable / scheduled jobs.
 *
 * Multi-instance: every Nest replica registers all 5 queues. Four generic
 * workers live here; the match-pair worker lives in MatchmakingModule with
 * its domain service. BullMQ's WorkerHost acquires a per-queue lock, so only
 * one replica actively polls a given queue at a time. If that replica
 * dies, BullMQ's stalled-job detector (default 30s) releases the lock
 * and another replica takes over. No env flag needed.
 *
 * Producers (Orchestrator, Matchmaking, Match Lifecycle) inject
 * `QueueService` to schedule jobs. No need to re-import this module.
 *
 * Connection: each queue uses `registerQueueAsync` with explicit
 * `RedisService.bullClient` injection. That client is configured with
 * `maxRetriesPerRequest: null` as BullMQ requires for blocking worker
 * commands (separate from the script-eval client which keeps
 * `maxRetriesPerRequest: 3`). Synchronous construction is required so
 * `RedisService.bullClient` is available when BullModule's useFactory
 * runs during module instantiation, before any onModuleInit hook.
 */
@Global()
@Module({
  imports: [
    BullModule.forRootAsync({
      inject: [RedisService],
      useFactory: (redis: RedisService) => ({ connection: redis.bullClient }),
    }),
    BullModule.registerQueueAsync(
      {
        name: QUEUE_NAMES.PHASE_TIMER,
        inject: [RedisService],
        useFactory: (redis: RedisService) => ({ connection: redis.bullClient }),
      },
      {
        name: QUEUE_NAMES.COMBAT_DONE_TIMEOUT,
        inject: [RedisService],
        useFactory: (redis: RedisService) => ({ connection: redis.bullClient }),
      },
      {
        name: QUEUE_NAMES.DISCONNECT_DETECT,
        inject: [RedisService],
        useFactory: (redis: RedisService) => ({ connection: redis.bullClient }),
      },
      {
        name: QUEUE_NAMES.MATCH_PAIR,
        inject: [RedisService],
        useFactory: (redis: RedisService) => ({ connection: redis.bullClient }),
      },
      {
        name: QUEUE_NAMES.MATCH_CLEANUP,
        inject: [RedisService],
        useFactory: (redis: RedisService) => ({ connection: redis.bullClient }),
      },
    ),
  ],
  providers: [QueueService, ...QUEUE_WORKERS],
  exports: [QueueService, BullModule],
})
export class QueueModule {}
