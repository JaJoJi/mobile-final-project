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

describe('MatchService.finalize stats invalidation (#254)', () => {
  it('deletes both players stats keys after a terminal finalize', async () => {
    const match = makeMatch();
    const finalizedArgs: unknown[] = [];
    const published: unknown[] = [];
    const matches = {
      findByIdForUpdate: async () => ({ ...match }),
      finalize: async (...args: unknown[]) => {
        finalizedArgs.push(args);
      },
    };
    const users = {
      findByIdsForUpdate: async () => [
        { id: 'p1', rating: 1000 },
        { id: 'p2', rating: 1000 },
      ],
      updateRating: async () => undefined,
    };
    const stats = { invalidateUsers: jest.fn(async () => undefined) };
    const service = new MatchService(
      { transaction: async (cb: any) => cb({}) } as any,
      matches as any,
      { publish: async (...args: unknown[]) => published.push(args) } as any,
      users as any,
      stats as any,
    );

    await expect(service.finalize('match-1', 'p2', 'hp_zero')).resolves.toBe(true);
    expect(stats.invalidateUsers).toHaveBeenCalledWith(['p1', 'p2']);
    expect(published).toHaveLength(1);
  });

  it('does not invalidate when the match was already terminal', async () => {
    const stats = { invalidateUsers: jest.fn(async () => undefined) };
    const service = new MatchService(
      { transaction: async (cb: any) => cb({}) } as any,
      {
        findByIdForUpdate: async () => ({ ...makeMatch(), status: 'finished' }),
        finalize: async () => undefined,
      } as any,
      { publish: async () => undefined } as any,
      {} as any,
      stats as any,
    );

    await expect(service.finalize('match-1', 'p2', 'hp_zero')).resolves.toBe(false);
    expect(stats.invalidateUsers).not.toHaveBeenCalled();
  });
});
