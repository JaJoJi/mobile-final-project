import { Injectable, Logger } from '@nestjs/common';
import { DataSource } from 'typeorm';

const DEFAULT_EVENT_DAYS = 90;
const DEFAULT_HISTORY_DAYS = 365;
const DEFAULT_BATCH_SIZE = 500;

export interface RetentionReport {
  eventRowsEligible: number;
  eventBytesEligible: number;
  matchesEligible: number;
  batchSize: number;
  dryRun: boolean;
  eventsCleared: number;
  matchesDeleted: number;
}

@Injectable()
export class MatchRetentionService {
  private readonly logger = new Logger(MatchRetentionService.name);

  constructor(private readonly dataSource: DataSource) {}

  async run(dryRun = false): Promise<RetentionReport> {
    const eventDays = this.readPositiveInt('MATCH_EVENT_RETENTION_DAYS', DEFAULT_EVENT_DAYS);
    const historyDays = this.readPositiveInt('MATCH_HISTORY_RETENTION_DAYS', DEFAULT_HISTORY_DAYS);
    const batchSize = this.readPositiveInt('MATCH_RETENTION_BATCH_SIZE', DEFAULT_BATCH_SIZE, 10_000);
    if (historyDays < eventDays) {
      throw new Error('MATCH_HISTORY_RETENTION_DAYS must be greater than or equal to MATCH_EVENT_RETENTION_DAYS');
    }

    const [eventEligibility] = await this.dataSource.query(
      `SELECT COUNT(*)::bigint AS rows,
              COALESCE(SUM(pg_column_size(r."events")), 0)::bigint AS bytes
         FROM "match_rounds" r
         JOIN "matches" m ON m."id" = r."matchId"
        WHERE r."events" IS NOT NULL
          AND m."status" IN ('finished', 'forfeited')
          AND m."finishedAt" < now() - ($1::int * interval '1 day')
          AND m."finishedAt" >= now() - ($2::int * interval '1 day')`,
      [eventDays, historyDays],
    );
    const [matchEligibility] = await this.dataSource.query(
      `SELECT COUNT(*)::bigint AS rows
         FROM "matches"
        WHERE "status" IN ('finished', 'forfeited')
          AND "finishedAt" < now() - ($1::int * interval '1 day')`,
      [historyDays],
    );

    const report: RetentionReport = {
      eventRowsEligible: Number(eventEligibility.rows),
      eventBytesEligible: Number(eventEligibility.bytes),
      matchesEligible: Number(matchEligibility.rows),
      batchSize,
      dryRun,
      eventsCleared: 0,
      matchesDeleted: 0,
    };
    this.logger.log(`retention preview ${JSON.stringify(report)}`);
    if (dryRun) return report;

    while (true) {
      const result = await this.dataSource.query(
        `WITH batch AS (
           SELECT r."id"
             FROM "match_rounds" r
             JOIN "matches" m ON m."id" = r."matchId"
            WHERE r."events" IS NOT NULL
              AND m."status" IN ('finished', 'forfeited')
              AND m."finishedAt" < now() - ($1::int * interval '1 day')
              AND m."finishedAt" >= now() - ($3::int * interval '1 day')
            ORDER BY r."createdAt", r."id"
            LIMIT $2
            FOR UPDATE OF r SKIP LOCKED
         )
         UPDATE "match_rounds" r SET "events" = NULL
          FROM batch WHERE r."id" = batch."id"
         RETURNING r."id"`,
        [eventDays, batchSize, historyDays],
      );
      report.eventsCleared += result.length;
      if (result.length < batchSize) break;
    }

    while (true) {
      const result = await this.dataSource.query(
        `WITH batch AS (
           SELECT "id"
             FROM "matches"
            WHERE "status" IN ('finished', 'forfeited')
              AND "finishedAt" < now() - ($1::int * interval '1 day')
            ORDER BY "finishedAt", "id"
            LIMIT $2
            FOR UPDATE SKIP LOCKED
         )
         DELETE FROM "matches" m USING batch
          WHERE m."id" = batch."id"
         RETURNING m."id"`,
        [historyDays, batchSize],
      );
      report.matchesDeleted += result.length;
      if (result.length < batchSize) break;
    }

    this.logger.log(`retention complete ${JSON.stringify(report)}`);
    return report;
  }

  private readPositiveInt(name: string, fallback: number, maximum = Number.MAX_SAFE_INTEGER): number {
    const value = process.env[name];
    if (value === undefined || value === '') return fallback;
    const parsed = Number(value);
    if (!Number.isInteger(parsed) || parsed < 1 || parsed > maximum) {
      throw new Error(`${name} must be an integer between 1 and ${maximum}`);
    }
    return parsed;
  }
}
