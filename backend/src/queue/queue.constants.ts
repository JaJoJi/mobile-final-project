/**
 * Queue + job naming conventions for BullMQ.
 *
 * Every queue name doubles as a Redis key prefix (e.g. `bull:phase-timer:*`),
 * so do not rename without a Redis-side data migration.
 *
 * Job names are nested under each queue so producers and consumers can
 * branch on `job.name` instead of inspecting `job.data` for a discriminator.
 */
export const QUEUE_NAMES = {
  PHASE_TIMER: 'phase-timer',
  COMBAT_DONE_TIMEOUT: 'combat-done-timeout',
  DISCONNECT_DETECT: 'disconnect-detect',
  MATCH_PAIR: 'match-pair',
  MATCH_CLEANUP: 'match-cleanup',
} as const;

export type QueueName = (typeof QUEUE_NAMES)[keyof typeof QUEUE_NAMES];

export const JOB_NAMES = {
  // phase-timer
  PHASE_START: 'phase-timer:start',
  // combat-done-timeout
  COMBAT_DONE_TIMEOUT: 'combat-done-timeout:fire',
  // disconnect-detect
  DISCONNECT_DETECT: 'disconnect-detect:fire',
  // match-pair
  MATCH_PAIR: 'match-pair:tick',
  // match-cleanup
  MATCH_CLEANUP: 'match-cleanup:run',
} as const;

export type JobName = (typeof JOB_NAMES)[keyof typeof JOB_NAMES];
