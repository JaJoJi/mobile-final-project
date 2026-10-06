import type { RedisService } from '../redis/redis.service';

/** Immediate completed-job removal; keep the last 100 failures for diagnosis. */
export const JOB_RETENTION = {
  removeOnComplete: true,
  removeOnFail: 100,
} as const;

export function queueConnectionOptions(redis: RedisService) {
  return {
    connection: redis.bullClient,
    defaultJobOptions: JOB_RETENTION,
  };
}
