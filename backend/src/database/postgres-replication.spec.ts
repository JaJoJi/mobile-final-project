import { DataSource } from 'typeorm';
import {
  buildPostgresConnectionFragment,
  queryOnSlave,
  resolvePostgresUrls,
  runOnMaster,
} from './postgres-replication';

describe('resolvePostgresUrls', () => {
  it('prefers DATABASE_PRIMARY_URL over legacy DATABASE_URL', () => {
    expect(
      resolvePostgresUrls({
        DATABASE_PRIMARY_URL: 'postgres://primary/db',
        DATABASE_URL: 'postgres://legacy/db',
      } as NodeJS.ProcessEnv),
    ).toEqual({
      primaryUrl: 'postgres://primary/db',
      replicaUrl: 'postgres://primary/db',
    });
  });

  it('falls back to DATABASE_URL when no primary/replica vars exist', () => {
    expect(
      resolvePostgresUrls({ DATABASE_URL: 'postgres://legacy/db' } as NodeJS.ProcessEnv),
    ).toEqual({
      primaryUrl: 'postgres://legacy/db',
      replicaUrl: 'postgres://legacy/db',
    });
  });

  it('resolves an explicit replica independently of the primary', () => {
    expect(
      resolvePostgresUrls({
        DATABASE_URL: 'postgres://primary/db',
        DATABASE_REPLICA_URL: 'postgres://replica/db',
      } as NodeJS.ProcessEnv),
    ).toEqual({
      primaryUrl: 'postgres://primary/db',
      replicaUrl: 'postgres://replica/db',
    });
  });
});

describe('buildPostgresConnectionFragment', () => {
  it('returns the legacy single-url shape without a replica (zero behavior change)', () => {
    expect(
      buildPostgresConnectionFragment({
        DATABASE_URL: 'postgres://only/db',
      } as NodeJS.ProcessEnv),
    ).toEqual({ url: 'postgres://only/db' });
  });

  it('returns TypeORM replication config with master=primary, slaves=[replica]', () => {
    expect(
      buildPostgresConnectionFragment({
        DATABASE_PRIMARY_URL: 'postgres://primary/db',
        DATABASE_REPLICA_URL: 'postgres://replica/db',
      } as NodeJS.ProcessEnv),
    ).toEqual({
      replication: {
        master: { url: 'postgres://primary/db' },
        slaves: [{ url: 'postgres://replica/db' }],
      },
    });
  });

  it('does not configure replication when replica equals primary', () => {
    expect(
      buildPostgresConnectionFragment({
        DATABASE_URL: 'postgres://same/db',
        DATABASE_REPLICA_URL: 'postgres://same/db',
      } as NodeJS.ProcessEnv),
    ).toEqual({ url: 'postgres://same/db' });
  });
});

describe('query runners', () => {  const makeDataSource = () => {
    const released: string[] = [];
    const createdModes: string[] = [];
    const queries: Array<{ mode: string; sql: string }> = [];
    const dataSource = {
      createQueryRunner: (mode: string) => {
        createdModes.push(mode);
        const runner = {
          mode,
          manager: { mode },
          query: async (sql: string) => {
            queries.push({ mode, sql });
            return [{ ok: mode }];
          },
          release: async () => {
            released.push(mode);
          },
        };
        return runner;
      },
    } as any;
    return { dataSource, released, createdModes, queries };
  };

  it('runOnMaster uses a "master" runner and always releases it', async () => {
    const { dataSource, released, createdModes } = makeDataSource();
    const manager = await runOnMaster(dataSource, async (m) => m);
    expect(manager).toEqual({ mode: 'master' });
    expect(createdModes).toEqual(['master']);
    expect(released).toEqual(['master']);
  });

  it('runOnMaster releases the runner even when the callback throws', async () => {
    const { dataSource, released } = makeDataSource();
    await expect(
      runOnMaster(dataSource, async () => {
        throw new Error('boom');
      }),
    ).rejects.toThrow('boom');
    expect(released).toEqual(['master']);
  });

  it('queryOnSlave issues raw SQL on a "slave" runner and releases it', async () => {
    const { dataSource, released, queries } = makeDataSource();
    const rows = await queryOnSlave(dataSource, 'SELECT 1', []);
    expect(rows).toEqual([{ ok: 'slave' }]);
    expect(queries).toEqual([{ mode: 'slave', sql: 'SELECT 1' }]);
    expect(released).toEqual(['slave']);
  });
});

describe('installed TypeORM driver compatibility', () => {
  it('accepts the generated replication fragment (no connection attempted)', () => {
    const fragment = buildPostgresConnectionFragment({
      DATABASE_PRIMARY_URL: 'postgres://u:p@postgres-primary:5432/db',
      DATABASE_REPLICA_URL: 'postgres://u:p@postgres-replica:5432/db',
    } as NodeJS.ProcessEnv);
    // Throws at construction time if the installed TypeORM version rejects
    // the `replication.master/slaves` URL shape.
    const dataSource = new DataSource({
      type: 'postgres',
      ...fragment,
      entities: [],
    });
    expect(dataSource.driver.isReplicated).toBe(true);
    expect(dataSource.defaultReplicationModeForReads()).toBe('slave');
    const masterMode = (
      dataSource.createQueryRunner('master') as unknown as { mode: string }
    ).mode;
    const slaveMode = (
      dataSource.createQueryRunner('slave') as unknown as { mode: string }
    ).mode;
    expect(masterMode).toBe('master');
    expect(slaveMode).toBe('slave');
  });
});
