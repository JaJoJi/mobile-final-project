import { MatchService } from './match.service';

const makeMatch = () => ({
  id: 'match-1',
  player1Id: 'p1',
  player2Id: 'p2',
  winnerId: null,
  status: 'in_progress',
  p1State: { hp: 0 },
  p2State: { hp: 40 },
});

const makeService = (overrides: {
  status?: string;
  stats?: { invalidateUsers: jest.Mock };
  leaderboard?: { bumpVersion: jest.Mock };
  published?: unknown[];
}) => {
  const stats = overrides.stats ?? {
    invalidateUsers: jest.fn(async () => undefined),
  };
  const leaderboard = overrides.leaderboard ?? {
    bumpVersion: jest.fn(async () => undefined),
  };
  const published = overrides.published ?? [];
  const service = new MatchService(
    { transaction: async (cb: any) => cb({}) } as any,
    {
      findByIdForUpdate: async () => ({
        ...makeMatch(),
        status: overrides.status ?? 'in_progress',
      }),
      finalize: async () => undefined,
    } as any,
    { publish: async (...args: unknown[]) => published.push(args) } as any,
    {
      findByIdsForUpdate: async () => [
        { id: 'p1', rating: 1000 },
        { id: 'p2', rating: 1000 },
      ],
      updateRating: async () => undefined,
    } as any,
    stats as any,
    leaderboard as any,
  );
  return { service, stats, leaderboard, published };
};

describe('MatchService.finalize stats invalidation (#254)', () => {
  it('deletes both players stats keys after a terminal finalize', async () => {
    const { service, stats, published } = makeService({});
    await expect(service.finalize('match-1', 'p2', 'hp_zero')).resolves.toBe(true);
    expect(stats.invalidateUsers).toHaveBeenCalledWith(['p1', 'p2']);
    expect(published).toHaveLength(1);
  });

  it('does not invalidate when the match was already terminal', async () => {
    const { service, stats } = makeService({ status: 'finished' });
    await expect(service.finalize('match-1', 'p2', 'hp_zero')).resolves.toBe(false);
    expect(stats.invalidateUsers).not.toHaveBeenCalled();
  });
});

describe('MatchService.finalize leaderboard invalidation (#256)', () => {
  it('bumps the leaderboard version after a terminal finalize', async () => {
    const { service, leaderboard } = makeService({});
    await expect(service.finalize('match-1', 'p2', 'hp_zero')).resolves.toBe(true);
    expect(leaderboard.bumpVersion).toHaveBeenCalledTimes(1);
  });

  it('does not bump when the match was already terminal', async () => {
    const { service, leaderboard } = makeService({ status: 'finished' });
    await expect(service.finalize('match-1', 'p2', 'hp_zero')).resolves.toBe(false);
    expect(leaderboard.bumpVersion).not.toHaveBeenCalled();
  });

  it('still publishes match:end after both cache invalidations', async () => {
    const { service, stats, leaderboard, published } = makeService({});
    await expect(service.finalize('match-1', 'p2', 'hp_zero')).resolves.toBe(true);
    // Fail-open lives inside the services (covered in their specs);
    // here the invalidations must not prevent the match:end publish.
    expect(stats.invalidateUsers).toHaveBeenCalledTimes(1);
    expect(leaderboard.bumpVersion).toHaveBeenCalledTimes(1);
    expect(published).toHaveLength(1);
  });
});
