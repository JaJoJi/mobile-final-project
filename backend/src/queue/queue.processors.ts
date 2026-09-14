import { Processor, WorkerHost } from '@nestjs/bullmq';
import { Logger } from '@nestjs/common';
import { Job } from 'bullmq';
import { MatchRuntimeAdapter } from '../runtime/match.runtime.adapter';
import { JOB_NAMES, QUEUE_NAMES } from './queue.constants';

interface RoundJob {
  matchId: string;
  round: number;
}

@Processor(QUEUE_NAMES.PHASE_TIMER)
export class PhaseTimerProcessor extends WorkerHost {
  private readonly logger = new Logger(PhaseTimerProcessor.name);

  constructor(private readonly runtime: MatchRuntimeAdapter) {
    super();
  }

  async process(job: Job<RoundJob>): Promise<void> {
    if (job.name !== JOB_NAMES.PHASE_START) return;
    const started = await this.runtime.tryStartCombat(job.data.matchId, job.data.round);
    this.logger.log(
      `phase timer match=${job.data.matchId} round=${job.data.round} started=${started}`,
    );
  }
}

@Processor(QUEUE_NAMES.COMBAT_DONE_TIMEOUT)
export class CombatDoneTimeoutProcessor extends WorkerHost {
  private readonly logger = new Logger(CombatDoneTimeoutProcessor.name);

  constructor(private readonly runtime: MatchRuntimeAdapter) {
    super();
  }

  async process(job: Job<RoundJob>): Promise<void> {
    if (job.name !== JOB_NAMES.COMBAT_DONE_TIMEOUT) return;
    const advanced = await this.runtime.applyDamageAndAdvance(
      job.data.matchId,
      job.data.round,
    );
    this.logger.log(
      `combat timeout match=${job.data.matchId} round=${job.data.round} advanced=${advanced}`,
    );
  }
}

@Processor(QUEUE_NAMES.DISCONNECT_DETECT)
export class DisconnectDetectProcessor extends WorkerHost {
  private readonly logger = new Logger(DisconnectDetectProcessor.name);

  constructor(private readonly runtime: MatchRuntimeAdapter) {
    super();
  }

  async process(job: Job<{ matchId: string; userId: string }>): Promise<void> {
    if (job.name !== JOB_NAMES.DISCONNECT_DETECT) return;
    const forfeited = await this.runtime.handleDisconnect(
      job.data.matchId,
      job.data.userId,
    );
    this.logger.log(
      `disconnect match=${job.data.matchId} user=${job.data.userId} forfeited=${forfeited}`,
    );
  }
}

export const RUNTIME_QUEUE_PROCESSORS = [
  PhaseTimerProcessor,
  CombatDoneTimeoutProcessor,
  DisconnectDetectProcessor,
];
