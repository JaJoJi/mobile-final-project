import { DataSource, EntityManager } from 'typeorm';

/**
 * PostgreSQL primary/replica routing for Issue: read/write splitting.
 *
 * Topology (async WAL streaming, primary → replica):
 *
 *   NestJS ── WRITE (master) ──→ postgres-primary
 *   NestJS ── READ  (slave)  ──→ postgres-replica
 *
 * TypeORM 0.3.x behavior this file relies on:
 *   - `replication.master` serves all writes and every `DataSource.transaction()`
 *     (transactions create a `"master"` query runner).
 *   - Repository / QueryBuilder SELECTs without an explicit runner use
 *     `defaultReplicationModeForReads()` → `"slave"` when replication is on.
 *   - Raw `dataSource.query()` uses a `"master"` runner, so replica reads for
 *     raw SQL must go through an explicit `"slave"` runner (see `queryOnSlave`).
 *   - Without `replication` configured, `"slave"` runners fall back to the
 *     single connection — every helper below is a no-op routing-wise.
 *
 * Env contract (no secrets committed; see `.env.example`):
 *   - `DATABASE_PRIMARY_URL` — primary (preferred).
 *   - `DATABASE_URL` — legacy fallback for the primary (dev/CI/test compat).
 *   - `DATABASE_REPLICA_URL` — replica. When absent, reads fall back to the
 *     primary so single-database environments keep working unchanged.
 */

export interface ResolvedPostgresUrls {
  /** Write target. `undefined` when no URL is configured at all. */
  primaryUrl: string | undefined;
  /** Read target. Equals `primaryUrl` when no replica is configured. */
  replicaUrl: string | undefined;
}

export function resolvePostgresUrls(
  env: NodeJS.ProcessEnv = process.env,
): ResolvedPostgresUrls {
  const primaryUrl = env.DATABASE_PRIMARY_URL ?? env.DATABASE_URL ?? undefined;
  const replicaUrl = env.DATABASE_REPLICA_URL ?? primaryUrl;
  return { primaryUrl, replicaUrl };
}

export interface PostgresReplicationFragment {
  url?: string;
  replication?: {
    master: { url: string };
    slaves: Array<{ url: string }>;
  };
}

/**
 * Returns the TypeORM connection fragment for `TypeOrmModule.forRootAsync`.
 * Single-URL environments get the legacy `{ url }` shape (zero behavior
 * change); primary+replica environments get `{ replication: { master, slaves } }`.
 */
export function buildPostgresConnectionFragment(
  env: NodeJS.ProcessEnv = process.env,
): PostgresReplicationFragment {
  const { primaryUrl, replicaUrl } = resolvePostgresUrls(env);
  if (primaryUrl && replicaUrl && replicaUrl !== primaryUrl) {
    return {
      replication: {
        master: { url: primaryUrl },
        slaves: [{ url: replicaUrl }],
      },
    };
  }
  return { url: primaryUrl };
}

/**
 * Run `fn` with an `EntityManager` pinned to the PRIMARY (`"master"` runner).
 * Use for correctness-critical reads that must observe the latest writes:
 * auth lookups, active-match guards, and any read-after-write re-read.
 */
export async function runOnMaster<T>(
  dataSource: DataSource,
  fn: (manager: EntityManager) => Promise<T>,
): Promise<T> {
  const runner = dataSource.createQueryRunner('master');
  try {
    return await fn(runner.manager);
  } finally {
    await runner.release();
  }
}

/**
 * Run raw SQL against the REPLICA (`"slave"` runner). Use only for reads
 * where eventual consistency is acceptable (leaderboard, stats). Falls back
 * to the single connection when replication is not configured.
 */
export async function queryOnSlave<T>(
  dataSource: DataSource,
  sql: string,
  parameters?: unknown[],
): Promise<T> {
  const runner = dataSource.createQueryRunner('slave');
  try {
    return (await runner.query(sql, parameters)) as T;
  } finally {
    await runner.release();
  }
}
