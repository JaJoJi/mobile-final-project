import { Processor, WorkerHost } from '@nestjs/bullmq';
import { Logger } from '@nestjs/common';
import { Job } from 'bullmq';
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

  async process(job: Job): Promise<void> {
    this.logger.log(
      `[match-cleanup] job=${job.name} id=${job.id} data=${JSON.stringify(job.data)}`,
    );
  }
}

export const QUEUE_WORKERS = [
  MatchCleanupWorker,
];

// Re-export so external verifiers don't need to know the exact JOB_NAMES value.
export { JOB_NAMES, QUEUE_NAMES };
