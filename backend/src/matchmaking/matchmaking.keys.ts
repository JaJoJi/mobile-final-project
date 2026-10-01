/**
 * Shared Redis key for the FIFO matchmaking queue.
 *
 * Lives in its own leaf module so unit-testable services (e.g. rooms) can
 * reference the key without importing `MatchmakingService` — which pulls
 * the BullMQ worker chain (`queue.service` → `@nestjs/bullmq`, ESM-only
 * and unparseable by the ts-jest unit config).
 */
export const MATCHMAKING_QUEUE_KEY = 'matchmaking:queue';
