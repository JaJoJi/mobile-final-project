import { InjectQueue } from '@nestjs/bullmq';
import { Injectable, Logger, OnModuleInit } from '@nestjs/common';
import { Queue } from 'bullmq';
import { JOB_NAMES, QUEUE_NAMES } from './queue.constants';

@Injectable()
export class QueueService implements OnModuleInit {
  private readonly logger = new Logger(QueueService.name);

  constructor(
    @InjectQueue(QUEUE_NAMES.PHASE_TIMER) private readonly phaseTimer: Queue,
    @InjectQueue(QUEUE_NAMES.COMBAT_DONE_TIMEOUT) private readonly combatDoneTimeout: Queue,
    @InjectQueue(QUEUE_NAMES.DISCONNECT_DETECT) private readonly disconnectDetect: Queue,
    @InjectQueue(QUEUE_NAMES.MATCH_PAIR) private readonly matchPair: Queue,
    @InjectQueue(QUEUE_NAMES.MATCH_CLEANUP) private readonly matchCleanup: Queue,
  ) {}

  async onModuleInit(): Promise<void> {
    await this.ensureMatchRetentionRepeating();
  }

  private async ensureMatchRetentionRepeating(intervalMs = 24 * 60 * 60 * 1000) {
    const existing = await this.matchCleanup.getRepeatableJobs();
    const already = existing.some(
      (job) => job.name === JOB_NAMES.MATCH_RETENTION_RUN && Number(job.every) === intervalMs,
    );
    if (already) return;
    await this.matchCleanup.add(
      JOB_NAMES.MATCH_RETENTION_RUN,
      {},
      {
        repeat: { every: intervalMs },
        jobId: 'match-retention-daily',
        attempts: 3,
        backoff: { type: 'exponential', delay: 60_000 },
        removeOnComplete: true,
        removeOnFail: 100,
      },
    );
  }

  /**
   * One-shot delayed timer. Used by the Round Orchestrator to auto-advance
   * the phase after N ms (e.g. 40 s shop → battle).
   */
  async schedulePhaseStart(matchId: string, round: number, delayMs: number) {
    return this.phaseTimer.add(
      JOB_NAMES.PHASE_START,
      { matchId, round },
      { delay: delayMs, jobId: `phase-${matchId}-${round}` },
    );
  }

  /**
   * Fallback for clients that never ack `game:match:combat_done`. Fires
   * `delayMs` after the orchestrator publishes combat events.
   */
  async scheduleCombatDoneTimeout(matchId: string, round: number, delayMs: number) {
    return this.combatDoneTimeout.add(
      JOB_NAMES.COMBAT_DONE_TIMEOUT,
      { matchId, round },
      { delay: delayMs, jobId: `combat-done-timeout-${matchId}-${round}` },
    );
  }

  /** Advances a resolved round after the first player has waited 3 seconds. */
  async scheduleRoundReadyTimeout(matchId: string, round: number, delayMs: number) {
    return this.combatDoneTimeout.add(
      JOB_NAMES.ROUND_READY_TIMEOUT,
      { matchId, round },
      { delay: delayMs, jobId: `round-ready-timeout-${matchId}-${round}` },
    );
  }

  /**
   * Gives a disconnected player `delayMs` to reconnect before the
   * orchestrator declares the other player the winner.
   */
  async scheduleDisconnectDetect(matchId: string, userId: string, delayMs: number) {
    return this.disconnectDetect.add(
      JOB_NAMES.DISCONNECT_DETECT,
      { matchId, userId },
      { delay: delayMs, jobId: `disconnect-${matchId}-${userId}` },
    );
  }

  /**
   * Repeatable poller. Boots once per Nest instance; the consumer
   * (P0-BE-11 Matchmaking) runs `match_pair.lua` on each tick. BullMQ's
   * Worker lock ensures only one replica's worker is active at a time.
   */
  async ensureMatchPairRepeating(intervalMs = 1000) {
    const existing = await this.matchPair.getRepeatableJobs();
    const already = existing.some(
      (j) => j.name === JOB_NAMES.MATCH_PAIR && Number(j.every) === intervalMs,
    );
    if (already) return existing;
    await this.matchPair.add(
      JOB_NAMES.MATCH_PAIR,
      {},
      {
        repeat: { every: intervalMs },
        jobId: `match-pair-every-${intervalMs}`,
        // This job runs forever; retaining every successful one-second tick
        // would grow the completed set without bound.
        removeOnComplete: true,
        removeOnFail: 100,
      },
    );
    return this.matchPair.getRepeatableJobs();
  }

  /**
   * One-shot job scheduled at a specific epoch (ms). Used for match-end
   * cleanup of Redis keys + match row persistence.
   */
  async scheduleMatchCleanup(matchId: string, atEpochMs: number) {
    return this.matchCleanup.add(
      JOB_NAMES.MATCH_CLEANUP,
      { matchId },
      { delay: Math.max(0, atEpochMs - Date.now()), jobId: `cleanup-${matchId}` },
    );
  }
}
