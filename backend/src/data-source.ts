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
import { join } from 'path';
import { DataSource } from 'typeorm';
import { ENTITIES } from './database/entities';

export default new DataSource({
  type: 'postgres',
  url: process.env.DATABASE_URL,
  entities: ENTITIES,
  migrations: [join(__dirname, 'migrations', '*.{ts,js}')],
  synchronize: false,
  logging: ['error', 'warn', 'migration'],
});
