import { ConflictException, Injectable, Logger } from '@nestjs/common';
import { DataSource } from 'typeorm';
import { queryOnSlave } from '../database/postgres-replication';
import { RedisService } from '../redis/redis.service';

export interface LeaderboardEntry {
  rank: number;
  username: string;
  rating: number;
}

export interface LeaderboardResponse {
  entries: LeaderboardEntry[];
  me: LeaderboardEntry;
  limit: number;
  offset: number;
  total: number;
}

/** Version counter backing versioned cache keys (O(1) invalidation). */
export const LEADERBOARD_VERSION_KEY = 'leaderboard:version';

/**
 * `leaderboard:{version}:{userId}:{limit}:{offset}` — old versions expire via
 * TTL. The caller id is required because the response contains the private
 * `me` row in addition to the shared page.
 */
export const leaderboardCacheKey = (
  version: string,
  userId: string,
  limit: number,
  offset: number,
): string => `leaderboard:${version}:${userId}:${limit}:${offset}`;

/** Cache TTL in seconds — also the natural expiry for stale versions. */
export const LEADERBOARD_CACHE_TTL_SECONDS = 30;

/** Version used when no rating change has ever bumped the counter. */
const INITIAL_VERSION = '0';

/**
 * Leaderboard for Issue #256 (`GET /leaderboard`).
 *
 * PostgreSQL is the source of truth — rank comes from
 * `RANK() OVER (ORDER BY rating DESC)` (ties share a rank, gaps follow),
 * page order is deterministic (`rating DESC, id ASC`). No new table, no
 * Redis ZSET; Redis holds only versioned cache entries.
 *
 * Read routing: raw SQL goes to the REPLICA via `queryOnSlave` (eventual
 * consistency is acceptable — results are additionally cached for 30 s, so
 * sub-second WAL lag is negligible). Writes/ratings still land on PRIMARY.
 *
 * Invalidation is a version bump (`INCR leaderboard:version`) from
 * `MatchService.finalize`, so no `KEYS`/`SCAN + DEL` over pagination keys.
 * Every Redis failure fails OPEN to PostgreSQL.
 */
@Injectable()
export class LeaderboardService {
  private readonly logger = new Logger(LeaderboardService.name);

  constructor(
    private readonly dataSource: DataSource,
    private readonly redis: RedisService,
  ) {}

  async getLeaderboard(
    userId: string,
    limit: number,
    offset: number,
  ): Promise<LeaderboardResponse> {
    const version = await this.readVersion();
    if (version !== null) {
      try {
        const cached = await this.redis.client.get(
          leaderboardCacheKey(version, userId, limit, offset),
        );
        if (cached) {
          return JSON.parse(cached) as LeaderboardResponse;
        }
      } catch (e: unknown) {
        this.logger.warn(
          `leaderboard cache GET failed, falling back to PG: ${(e as Error).message}`,
        );
      }
    }

    const response = await this.computeLeaderboard(userId, limit, offset);

    if (version !== null) {
      try {
        await this.redis.client.set(
          leaderboardCacheKey(version, userId, limit, offset),
          JSON.stringify(response),
          'EX',
          LEADERBOARD_CACHE_TTL_SECONDS,
        );
      } catch (e: unknown) {
        this.logger.warn(`leaderboard cache SET failed: ${(e as Error).message}`);
      }
    }
    return response;
  }

  /**
   * Logically invalidates every pagination entry by rotating the version.
   * Called from `MatchService.finalize` after a terminal commit.
   * Never throws — stale versions additionally expire via TTL.
   */
  async bumpVersion(): Promise<void> {
    try {
      await this.redis.client.incr(LEADERBOARD_VERSION_KEY);
    } catch (e: unknown) {
      this.logger.warn(`leaderboard version bump failed: ${(e as Error).message}`);
    }
  }

  /** Version read; `null` means "bypass the cache" (Redis unavailable). */
  private async readVersion(): Promise<string | null> {
    try {
      return (await this.redis.client.get(LEADERBOARD_VERSION_KEY)) ?? INITIAL_VERSION;
    } catch (e: unknown) {
      this.logger.warn(
        `leaderboard version read failed, bypassing cache: ${(e as Error).message}`,
      );
      return null;
    }
  }

  private async computeLeaderboard(
    userId: string,
    limit: number,
    offset: number,
  ): Promise<LeaderboardResponse> {
    const totalRows = (await queryOnSlave<Array<{ count: string }>>(
      this.dataSource,
      `SELECT COUNT(*) AS "count" FROM "users"`,
    ));
    const pageRows = (await queryOnSlave<
      Array<{ username: string; rating: number; rank: string }>
    >(
      this.dataSource,
      `SELECT "username", "rating",
              RANK() OVER (ORDER BY "rating" DESC) AS "rank"
         FROM "users"
        ORDER BY "rating" DESC, "id" ASC
        LIMIT $1 OFFSET $2`,
      [limit, offset],
    ));
    const meRows = (await queryOnSlave<
      Array<{ username: string; rating: number; rank: string }>
    >(
      this.dataSource,
      `SELECT "username", "rating",
              (SELECT COUNT(*) FROM "users" AS "u2"
                WHERE "u2"."rating" > "u1"."rating") + 1 AS "rank"
         FROM "users" AS "u1"
        WHERE "u1"."id" = $1`,
      [userId],
    ));
    const me = meRows[0];
    if (!me) {
      // Same convention as GET /user/me for an unknown caller.
      throw new ConflictException('user not found');
    }
    return {
      entries: pageRows.map((row) => ({
        rank: Number(row.rank),
        username: row.username,
        rating: Number(row.rating),
      })),
      me: {
        rank: Number(me.rank),
        username: me.username,
        rating: Number(me.rating),
      },
      limit,
      offset,
      total: Number(totalRows[0]?.count ?? 0),
    };
  }
}
