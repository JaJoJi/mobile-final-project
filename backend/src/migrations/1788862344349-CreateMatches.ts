import { MigrationInterface, QueryRunner } from 'typeorm';

/**
 * Adds the `matches` and `match_rounds` tables for P0-BE-07.
 *
 * Mirrors `backend/src/match/match.entity.ts` and
 * `backend/src/match/match-round.entity.ts` 1:1.
 *
 * Manual edits applied on top of `migration:generate`:
 *   1. `gen_random_uuid()` instead of `uuid_generate_v4()` — built-in
 *      to Postgres ≥ 13, avoids the `CREATE EXTENSION pgcrypto` race
 *      that `migration:generate` would otherwise emit. See
 *      `backend/src/migrations/README.md` §"Conventions".
 *   2. Removed the spurious `CREATE UNIQUE INDEX "UQ_users_*"` lines
 *      — `users.email` / `users.username` already have named unique
 *      CONSTRAINTs from `CreateUsers1736000000000` (table-level, not
 *      separate indexes). Re-emitting them would error with
 *      `relation "UQ_users_username" already exists`.
 *   3. Explicit named constraints (`PK_matches_id`, `PK_match_rounds_id`)
 *      to match the convention in `CreateUsers1736000000000`.
 *   4. `FOREIGN KEY (matchId) REFERENCES matches(id) ON DELETE CASCADE`
 *      on `match_rounds` — application writes plain uuid columns (so
 *      the entity stays cheap to insert from hot-path code), but the
 *      schema still enforces referential integrity and avoids orphan
 *      rounds when a match is purged.
 */
export class CreateMatches1788862344349 implements MigrationInterface {
  name = 'CreateMatches1788862344349';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`
      CREATE TABLE "matches" (
        "id"            uuid         NOT NULL DEFAULT gen_random_uuid(),
        "player1Id"     uuid         NOT NULL,
        "player2Id"     uuid         NOT NULL,
        "winnerId"      uuid,
        "status"        varchar(16)  NOT NULL DEFAULT 'in_progress',
        "matchSeed"     uuid         NOT NULL,
        "wipeIndexP1"   int          NOT NULL DEFAULT 0,
        "wipeIndexP2"   int          NOT NULL DEFAULT 0,
        "p1State"       jsonb        NOT NULL,
        "p2State"       jsonb        NOT NULL,
        "createdAt"     timestamptz  NOT NULL DEFAULT now(),
        "finishedAt"    timestamptz,
        CONSTRAINT "PK_matches_id" PRIMARY KEY ("id"),
        CONSTRAINT "UQ_matches_seed" UNIQUE ("matchSeed")
      )
    `);

    await queryRunner.query(`
      CREATE TABLE "match_rounds" (
        "id"           uuid        NOT NULL DEFAULT gen_random_uuid(),
        "matchId"      uuid        NOT NULL,
        "roundNumber"  int         NOT NULL,
        "events"       jsonb       NOT NULL,
        "createdAt"    timestamptz NOT NULL DEFAULT now(),
        CONSTRAINT "PK_match_rounds_id" PRIMARY KEY ("id"),
        CONSTRAINT "FK_match_rounds_matchId"
          FOREIGN KEY ("matchId") REFERENCES "matches"("id") ON DELETE CASCADE
      )
    `);
    await queryRunner.query(`CREATE INDEX "IDX_match_rounds_matchId" ON "match_rounds" ("matchId")`);
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`DROP INDEX IF EXISTS "public"."IDX_match_rounds_matchId"`);
    await queryRunner.query(`DROP TABLE IF EXISTS "match_rounds"`);
    await queryRunner.query(`DROP TABLE IF EXISTS "matches"`);
  }
}
