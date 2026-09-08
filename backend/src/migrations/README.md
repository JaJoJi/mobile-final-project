# Migrations

TypeORM migrations are the **only** way schema changes reach Postgres.
`synchronize: false` is enforced everywhere — see `src/app.module.ts`.

## Single-instance runner

Only **one** Nest replica runs migrations on boot:

| Service  | `RUN_MIGRATIONS` | Effect on boot                     |
|----------|------------------|------------------------------------|
| nest-1   | `true`           | Applies pending migrations         |
| nest-2   | unset (=false)   | Skips; logs "0 already up to date" |
| nest-3   | unset (=false)   | Skips; logs "0 already up to date" |

Configured in `docker-compose.yml`. **Do not** set `RUN_MIGRATIONS=true` on
more than one service or you risk `CREATE TABLE` races across replicas.

## Workflow: add a new entity / change a schema

```bash
# 1. Define or edit the entity.
#    e.g. backend/src/match/match.entity.ts
#    Decorate with @Entity('matches') and the columns/indexes you need.

# 2. Register it in the central entity list (CRITICAL — without this step
#    TypeORM will not see the entity and `migration:generate` will diff
#    against an empty schema and DROP your existing columns).
vim backend/src/database/entities.ts
# export const ENTITIES = [User, Match];

# 3. Generate the migration against the live primary.
cd backend
npm run migration:generate -- src/migrations/CreateMatches

# 4. Review the generated SQL. The generator is usually correct for
#    pgcrypto-less UUIDs (see Conventions below) but **always read it**.

# 5. Commit the migration file alongside the entity change.

# 6. Deploy. nest-1 picks it up on next boot.
```

## Workflow: write a hand-crafted migration

Use this when `migration:generate` can't express what you need (custom
CHECK constraints, partial indexes, data backfills, etc.).

```typescript
// src/migrations/1700000000000-BackfillUserRatings.ts
import { MigrationInterface, QueryRunner } from 'typeorm';

export class BackfillUserRatings1700000000000 implements MigrationInterface {
  name = 'BackfillUserRatings1700000000000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`UPDATE users SET rating = 1000 WHERE rating IS NULL`);
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    // No-op: you can't meaningfully roll back a rating backfill.
  }
}
```

## Conventions

- **Naming**: `<13-digit-timestamp>-<PascalCaseName>.ts`. The timestamp is
  the order migrations run in; pick a value greater than the last migration.
- **`up()` + `down()`**: both must be implemented. `down()` may be a no-op
  if the operation is irreversible — add a comment explaining why.
- **UUIDs**: use `gen_random_uuid()` (built-in to Postgres 13+). Do **not**
  add `CREATE EXTENSION pgcrypto` — it would race on first init of a fresh
  cluster.
- **Foreign keys**: name them explicitly (`fk_<table>_<column>`) when the
  auto-generated name isn't readable.
- **Indexes**: declare them in the entity with `@Index({ name: '...' })`
  so `migration:generate` produces a stable, named index.
- **No DDL in `app.module.ts` or controllers**. Schema is migrations-only.

## Manual commands

```bash
cd backend
npm run migration:generate -- src/migrations/MyMigration   # diff entity vs DB
npm run migration:run                                     # apply pending
npm run migration:revert                                  # rollback last applied
```

All three read `backend/src/data-source.ts`, which sources `DATABASE_URL`
from the repo-root `.env`.

## Troubleshooting

- **`relation already exists`** on boot: two Nest instances are running
  migrations. Confirm only `nest-1` has `RUN_MIGRATIONS=true`.
- **Generator diffs against empty schema** when adding an entity: you
  forgot to add it to `backend/src/database/entities.ts`. Fix and re-run.
- **`migrations: [join(__dirname, 'migrations', '*.js')]`** works in the
  compiled Docker image because `npm run build` emits `.js` next to
  `tsconfig.build.json`'s `outDir`. Locally, `ts-node` resolves the `.ts`
  source via `data-source.ts`'s `*.{ts,js}` glob.
