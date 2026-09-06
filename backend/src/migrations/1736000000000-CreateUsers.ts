import { MigrationInterface, QueryRunner } from 'typeorm';

/**
 * Initial schema: `users` table.
 *
 * Hand-written (instead of generated) because the schema is small and
 * stable. Future schema changes can use `npm run migration:generate`
 * to diff against this entity.
 *
 * Mirrors `src/user/user.entity.ts` 1:1.
 */
export class CreateUsers1736000000000 implements MigrationInterface {
  name = 'CreateUsers1736000000000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    // gen_random_uuid() is built-in to PostgreSQL ≥ 13 (no extension
    // needed). Skipping CREATE EXTENSION avoids a race when multiple
    // Nest instances boot at once and try to install pgcrypto.
    await queryRunner.query(`
      CREATE TABLE "users" (
        "id"            uuid         NOT NULL DEFAULT gen_random_uuid(),
        "email"         varchar(254) NOT NULL,
        "username"      varchar(20)  NOT NULL,
        "passwordHash"  varchar(60)  NOT NULL,
        "rating"        int          NOT NULL DEFAULT 1000,
        "createdAt"     timestamptz  NOT NULL DEFAULT now(),
        CONSTRAINT "PK_users_id" PRIMARY KEY ("id"),
        CONSTRAINT "UQ_users_email"    UNIQUE ("email"),
        CONSTRAINT "UQ_users_username" UNIQUE ("username")
      )
    `);
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`DROP TABLE IF EXISTS "users"`);
  }
}
