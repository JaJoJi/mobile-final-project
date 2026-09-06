/**
 * TypeORM CLI DataSource.
 *
 * Used by:
 *   - `npm run migration:generate -- src/migrations/MyMigration`
 *   - `npm run migration:run`
 *   - `npm run migration:revert`
 *
 * Not used at runtime — runtime reads TypeOrmModule config from `app.module.ts`.
 *
 * Reads `.env` from the repo root so DATABASE_URL is available.
 */
import 'dotenv/config';
import { DataSource } from 'typeorm';
import { User } from './user/user.entity';

export default new DataSource({
  type: 'postgres',
  url: process.env.DATABASE_URL,
  entities: [User],
  migrations: ['src/migrations/*.ts'],
  synchronize: false,
  logging: ['error', 'warn', 'migration'],
});
