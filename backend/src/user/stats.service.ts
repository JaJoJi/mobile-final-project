import { Injectable, Logger } from '@nestjs/common';
import { DataSource } from 'typeorm';
import { queryOnSlave } from '../database/postgres-replication';
import { RedisService } from '../redis/redis.service';
import { UserService } from './user.service';

export interface PlayerStats {
  matches: number;
  wins: number;
  losses: number;
  winRate: number | null;
  currentRank: number | null;
}

/** Redis key for the stats cache-aside entry (cache only, never source of truth). */
export const statsCacheKey = (userId: string): string => `stats:${userId}`;

/** Cache TTL in seconds — fallback in case finalization invalidation is missed. */
export const STATS_CACHE_TTL_SECONDS = 60;

/**
 * Player statistics for Issue #254 (`GET /user/me/stats`).
 *
 * PostgreSQL is the source of truth. Statistics are derived from existing
 * data — no new table:
 *   1. one aggregate pass over terminal `matches` rows (no row loading);
 *   2. the caller's `rating` plus a greater-count for `RANK()` semantics
 *      (ties share a rank: rank = COUNT(rating > mine) + 1).
 *
 * Caching is cache-aside + explicit invalidation (from `MatchService.finalize`)
 * + TTL fallback. Redis failures fail OPEN to PostgreSQL; PostgreSQL errors
 * propagate and are never masked as `currentRank: null` (`null` rank means
 * only: user not found / no rating).
 *
 * Read routing: aggregate SQL goes to the REPLICA via `queryOnSlave`
 * (eventual consistency is acceptable — cached for 60 s anyway). The
 * per-user rating lookup stays on PRIMARY (`UserService.findById`).
 */
@Injectable()
export class StatsService {
  private readonly logger = new Logger(StatsService.name);

  constructor(
    private readonly dataSource: DataSource,
    private readonly redis: RedisService,
    private readonly users: UserService,
  ) {}

  async getStats(userId: string): Promise<PlayerStats> {
    try {
      const cached = await this.redis.client.get(statsCacheKey(userId));
      if (cached) {
        return JSON.parse(cached) as PlayerStats;
      }
    } catch (e: unknown) {
      this.logger.warn(
        `stats cache GET failed for user=${userId}, falling back to PG: ${(e as Error).message}`,
      );
    }

    const stats = await this.computeStats(userId);

    try {
      await this.redis.client.set(
        statsCacheKey(userId),
        JSON.stringify(stats),
        'EX',
        STATS_CACHE_TTL_SECONDS,
      );
    } catch (e: unknown) {
      this.logger.warn(
        `stats cache SET failed for user=${userId}: ${(e as Error).message}`,
      );
    }
    return stats;
  }

  /**
   * Best-effort invalidation after a match reaches a terminal state.
   * Called from `MatchService.finalize` (the single seam covering hp_zero,
   * forfeit, and disconnect). Never throws — the 60 s TTL is the fallback.
   */
  async invalidateUsers(userIds: string[]): Promise<void> {
    if (userIds.length === 0) return;
    try {
      await this.redis.client.del(...userIds.map(statsCacheKey));
    } catch (e: unknown) {
      this.logger.warn(`stats cache DEL failed: ${(e as Error).message}`);
    }
  }

  private async computeStats(userId: string): Promise<PlayerStats> {
    const rows = (await queryOnSlave<
      Array<{ matches: string; wins: string; losses: string }>
    >(
      this.dataSource,
      `SELECT
         COUNT(*) FILTER (
           WHERE "status" IN ('finished', 'forfeited')
             AND ("player1Id" = $1 OR "player2Id" = $1)
         ) AS "matches",
         COUNT(*) FILTER (
           WHERE "status" IN ('finished', 'forfeited')
             AND ("player1Id" = $1 OR "player2Id" = $1)
             AND "winnerId" = $1
         ) AS "wins",
         COUNT(*) FILTER (
           WHERE "status" IN ('finished', 'forfeited')
             AND ("player1Id" = $1 OR "player2Id" = $1)
             AND "winnerId" IS NOT NULL
             AND "winnerId" <> $1
         ) AS "losses"
        FROM "matches"`,
      [userId],
    ));
    const row = rows[0] ?? { matches: '0', wins: '0', losses: '0' };
    const matches = Number(row.matches);
    const wins = Number(row.wins);
    // Draws (winnerId NULL) are counted in matches but never in losses,
    // so matches != wins + losses is valid when draws exist.
    const losses = Number(row.losses);
    const winRate = matches > 0 ? Math.round((wins / matches) * 100) : null;

    const user = await this.users.findById(userId);
    if (!user) {
      return { matches, wins, losses, winRate, currentRank: null };
    }
    const greater = await queryOnSlave<Array<{ count: string }>>(
      this.dataSource,
      `SELECT COUNT(*) AS "count" FROM "users" WHERE "rating" > $1`,
      [user.rating],
    );
    return {
      matches,
      wins,
      losses,
      winRate,
      currentRank: Number(greater[0]?.count ?? 0) + 1,
    };
  }
}
