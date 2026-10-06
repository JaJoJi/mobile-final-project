import { DataSource } from 'typeorm';
import { MatchRetentionService } from './match-retention.service';

describe('MatchRetentionService (#388)', () => {
  const originalEnv = {
    eventDays: process.env.MATCH_EVENT_RETENTION_DAYS,
    historyDays: process.env.MATCH_HISTORY_RETENTION_DAYS,
    batchSize: process.env.MATCH_RETENTION_BATCH_SIZE,
  };

  afterEach(() => {
    for (const [name, value] of [
      ['MATCH_EVENT_RETENTION_DAYS', originalEnv.eventDays],
      ['MATCH_HISTORY_RETENTION_DAYS', originalEnv.historyDays],
      ['MATCH_RETENTION_BATCH_SIZE', originalEnv.batchSize],
    ] as const) {
      if (value === undefined) delete process.env[name];
      else process.env[name] = value;
    }
  });

  function makeService() {
    const query = jest.fn();
    const service = new MatchRetentionService({ query } as unknown as DataSource);
    return { query, service };
  }

  it('reports eligible rows and bytes without changing data in dry-run mode', async () => {
    const { query, service } = makeService();
    query
      .mockResolvedValueOnce([{ rows: '3', bytes: '2048' }])
      .mockResolvedValueOnce([{ rows: '1' }]);

    await expect(service.run(true)).resolves.toMatchObject({
      eventRowsEligible: 3,
      eventBytesEligible: 2048,
      matchesEligible: 1,
      dryRun: true,
      eventsCleared: 0,
      matchesDeleted: 0,
    });
    expect(query).toHaveBeenCalledTimes(2);
    expect(query.mock.calls[0][1]).toEqual([90, 365]);
    expect(query.mock.calls[1][1]).toEqual([365]);
  });

  it('clears event payloads and deletes finished matches in bounded batches; rerun is safe', async () => {
    process.env.MATCH_RETENTION_BATCH_SIZE = '2';
    const { query, service } = makeService();
    query
      .mockResolvedValueOnce([{ rows: '3', bytes: '1500' }])
      .mockResolvedValueOnce([{ rows: '1' }])
      .mockResolvedValueOnce([{ id: 'round-a' }, { id: 'round-b' }])
      .mockResolvedValueOnce([{ id: 'round-c' }])
      .mockResolvedValueOnce([{ id: 'match-old' }])
      .mockResolvedValueOnce([{ rows: '0', bytes: '0' }])
      .mockResolvedValueOnce([{ rows: '0' }])
      .mockResolvedValueOnce([])
      .mockResolvedValueOnce([]);

    const first = await service.run();
    const second = await service.run();

    expect(first).toMatchObject({ eventsCleared: 3, matchesDeleted: 1, batchSize: 2 });
    expect(second).toMatchObject({ eventsCleared: 0, matchesDeleted: 0 });
    expect(query).toHaveBeenCalledTimes(9);
    const clearSql = query.mock.calls[2][0] as string;
    const deleteSql = query.mock.calls[4][0] as string;
    expect(clearSql).toContain('SET "events" = NULL');
    expect(clearSql).toContain("m.\"status\" IN ('finished', 'forfeited')");
    expect(clearSql).toContain('SKIP LOCKED');
    expect(query.mock.calls[2][1]).toEqual([90, 2, 365]);
    expect(deleteSql).toContain('DELETE FROM "matches"');
    expect(deleteSql).toContain('SKIP LOCKED');
    expect(query.mock.calls[4][1]).toEqual([365, 2]);
  });

  it('rejects an invalid policy before touching the database', async () => {
    process.env.MATCH_EVENT_RETENTION_DAYS = '100';
    process.env.MATCH_HISTORY_RETENTION_DAYS = '90';
    const { query, service } = makeService();

    await expect(service.run()).rejects.toThrow('MATCH_HISTORY_RETENTION_DAYS');
    expect(query).not.toHaveBeenCalled();
  });
});
