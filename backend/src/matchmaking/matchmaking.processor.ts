import { Processor, WorkerHost } from '@nestjs/bullmq';
import { Logger } from '@nestjs/common';
import { Job } from 'bullmq';
import { JOB_NAMES, QUEUE_NAMES } from '../queue/queue.constants';
import { MatchmakingService } from './matchmaking.service';

/** Consumes the one-second BullMQ poll and attempts one atomic FIFO pair. */
@Processor(QUEUE_NAMES.MATCH_PAIR)
export class MatchmakingProcessor extends WorkerHost {
  private readonly logger = new Logger(MatchmakingProcessor.name);

  constructor(private readonly matchmaking: MatchmakingService) {
    super();
  }

  async process(job: Job): Promise<void> {
    if (job.name !== JOB_NAMES.MATCH_PAIR) {
      this.logger.warn(`ignoring unknown match-pair job: ${job.name}`);
      return;
    }
    await this.matchmaking.tryPair();
  }
}
