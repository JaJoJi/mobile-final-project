import { Processor, WorkerHost } from '@nestjs/bullmq';
import { Logger } from '@nestjs/common';
import { Job } from 'bullmq';
import { JOB_NAMES, QUEUE_NAMES } from '../queue.constants';

/**
 * Stub workers for P0-BE-03 plumbing. They only log job arrival so we
 * can prove end-to-end delivery in the smoke test. Real processing logic
 * arrives in P0-BE-11 (Matchmaking) and P0-BE-13 (Round Orchestrator).
 *
 * Multi-instance behavior: every Nest replica starts one of each worker.
 * BullMQ's WorkerHost acquires a per-queue lock so only one replica's
 * worker actively pulls jobs at a time; the others sit idle.
 */

@Processor(QUEUE_NAMES.PHASE_TIMER)
export class PhaseTimerWorker extends WorkerHost {
  private readonly logger = new Logger(PhaseTimerWorker.name);

  async process(job: Job): Promise<void> {
    this.logger.log(
      `[phase-timer] job=${job.name} id=${job.id} data=${JSON.stringify(job.data)}`,
    );
  }
}

@Processor(QUEUE_NAMES.COMBAT_DONE_TIMEOUT)
export class CombatDoneTimeoutWorker extends WorkerHost {
  private readonly logger = new Logger(CombatDoneTimeoutWorker.name);

  async process(job: Job): Promise<void> {
    this.logger.log(
      `[combat-done-timeout] job=${job.name} id=${job.id} data=${JSON.stringify(job.data)}`,
    );
  }
}

@Processor(QUEUE_NAMES.DISCONNECT_DETECT)
export class DisconnectDetectWorker extends WorkerHost {
  private readonly logger = new Logger(DisconnectDetectWorker.name);

  async process(job: Job): Promise<void> {
    this.logger.log(
      `[disconnect-detect] job=${job.name} id=${job.id} data=${JSON.stringify(job.data)}`,
    );
  }
}

@Processor(QUEUE_NAMES.MATCH_PAIR)
export class MatchPairWorker extends WorkerHost {
  private readonly logger = new Logger(MatchPairWorker.name);

  async process(job: Job): Promise<void> {
    this.logger.log(
      `[match-pair] job=${job.name} id=${job.id} ts=${new Date().toISOString()}`,
    );
  }
}

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
  PhaseTimerWorker,
  CombatDoneTimeoutWorker,
  DisconnectDetectWorker,
  MatchPairWorker,
  MatchCleanupWorker,
];

// Re-export so external verifiers don't need to know the exact JOB_NAMES value.
export { JOB_NAMES, QUEUE_NAMES };
