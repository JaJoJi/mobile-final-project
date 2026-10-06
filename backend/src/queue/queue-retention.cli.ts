import { Queue } from 'bullmq';
import Redis from 'ioredis';
import { QUEUE_NAMES } from './queue.constants';
import { cleanRetainedJobs } from './queue-retention.service';

async function main(): Promise<void> {
  const args = process.argv.slice(2);
  if (args.some((arg) => arg !== '--apply')) {
    throw new Error('Usage: node dist/queue/queue-retention.cli.js [--apply]');
  }
  const connection = new Redis(process.env.REDIS_URL ?? 'redis://localhost:6379', {
    maxRetriesPerRequest: 3,
  });
  const queues = Object.fromEntries(
    Object.values(QUEUE_NAMES).map((name) => [name, new Queue(name, { connection })]),
  ) as Record<string, Queue>;
  try {
    const report = await cleanRetainedJobs(queues, args.includes('--apply'));
    console.log(JSON.stringify(report, null, 2));
  } finally {
    await Promise.all(Object.values(queues).map((queue) => queue.close()));
    await connection.quit();
  }
}

main().catch((error: unknown) => {
  console.error(error);
  process.exitCode = 1;
});
