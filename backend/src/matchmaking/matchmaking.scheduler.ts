import { Injectable, Logger, OnApplicationBootstrap } from '@nestjs/common';
import { QueueService } from '../queue/queue.service';

export const MATCHMAKING_POLL_INTERVAL_MS = 1000;

/** Ensures the shared BullMQ schedule exists when a Nest replica starts. */
@Injectable()
export class MatchmakingScheduler implements OnApplicationBootstrap {
  private readonly logger = new Logger(MatchmakingScheduler.name);

  constructor(private readonly queues: QueueService) {}

  async onApplicationBootstrap(): Promise<void> {
    const jobs = await this.queues.ensureMatchPairRepeating(MATCHMAKING_POLL_INTERVAL_MS);
    this.logger.log(`matchmaking poller ready (repeatable jobs=${jobs.length})`);
  }
}
