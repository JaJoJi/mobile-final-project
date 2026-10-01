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
 * Migrations and schema inspection must ALWAYS target the PRIMARY:
 * the replica is read-only (hot standby) and rejects DDL.
 */
import 'dotenv/config';
import { join } from 'path';
import { DataSource } from 'typeorm';
import { ENTITIES } from './database/entities';

const PRIMARY_URL = process.env.DATABASE_PRIMARY_URL ?? process.env.DATABASE_URL;

export default new DataSource({
  type: 'postgres',
  url: PRIMARY_URL,
  entities: ENTITIES,
  migrations: [join(__dirname, 'migrations', '*.{ts,js}')],
  synchronize: false,
  logging: ['error', 'warn', 'migration'],
});
