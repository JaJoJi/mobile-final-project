import { MigrationInterface, QueryRunner } from 'typeorm';

/**
 * Adds a leaderboard index on `users` for #256.
 *
 * The leaderboard page query is `ORDER BY rating DESC, id ASC LIMIT/OFFSET`
 * with `RANK() OVER (ORDER BY rating DESC)`. A mixed-direction btree serves
 * both the window ordering and the deterministic tie-break without a sort.
 *
 * Migration-only (no entity change): TypeORM `@Index` cannot express
 * per-column sort direction, and a plain ASC composite would leave the
 * tie-break to the planner. See `backend/src/migrations/README.md`
 * §"Workflow: write a hand-crafted migration".
 */
export class LeaderboardRatingIndex1788900000000 implements MigrationInterface {
  name = 'LeaderboardRatingIndex1788900000000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(
      `CREATE INDEX "IDX_users_rating_id" ON "users" ("rating" DESC, "id" ASC)`,
    );
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`DROP INDEX IF EXISTS "public"."IDX_users_rating_id"`);
  }
}
