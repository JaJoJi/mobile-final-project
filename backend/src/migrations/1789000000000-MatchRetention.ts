import { MigrationInterface, QueryRunner } from 'typeorm';

export class MatchRetention1789000000000 implements MigrationInterface {
  name = 'MatchRetention1789000000000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query('ALTER TABLE "match_rounds" ALTER COLUMN "events" DROP NOT NULL');
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query('UPDATE "match_rounds" SET "events" = \'[]\'::jsonb WHERE "events" IS NULL');
    await queryRunner.query('ALTER TABLE "match_rounds" ALTER COLUMN "events" SET NOT NULL');
  }
}
