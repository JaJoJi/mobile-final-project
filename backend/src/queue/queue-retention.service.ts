import type { Queue } from 'bullmq';
import { QUEUE_NAMES } from './queue.constants';

const COMPLETED_GRACE_MS = 60 * 60 * 1000;
const FAILED_GRACE_MS = 7 * 24 * 60 * 60 * 1000;
const BATCH_LIMIT = 1000;

type RetainedQueue = Pick<Queue, 'getJobCounts' | 'clean'>;

/** Run once per invocation; never touches waiting, delayed, active or repeat schedules. */
export async function cleanRetainedJobs(
  queues: Record<string, RetainedQueue>,
  apply = false,
) {
  const results = [];
  for (const name of Object.values(QUEUE_NAMES)) {
    const queue = queues[name];
    if (!queue) throw new Error(`Missing queue ${name}`);
    const before = await queue.getJobCounts('completed', 'failed');
    const completedRemoved = apply
      ? (await queue.clean(COMPLETED_GRACE_MS, BATCH_LIMIT, 'completed')).length
      : 0;
    const failedRemoved = apply
      ? (await queue.clean(FAILED_GRACE_MS, BATCH_LIMIT, 'failed')).length
      : 0;
    results.push({
      queue: name,
      completed: before.completed ?? 0,
      failed: before.failed ?? 0,
      completedRemoved,
      failedRemoved,
      apply,
    });
  }
  return results;
}
