import { MatchController } from './match.controller';

describe('MatchController read paths (#308)', () => {
  it('delegates history to the caller id', async () => {
    const matches = { getHistory: jest.fn(async () => [{ matchId: 'm1' }]) };
    const controller = new MatchController(matches as any);
    await expect(controller.history({ sub: 'user-1' })).resolves.toEqual([
      { matchId: 'm1' },
    ]);
    expect(matches.getHistory).toHaveBeenCalledWith('user-1');
  });

  it('delegates detail with path id plus caller id', async () => {
    const matches = { getDetail: jest.fn(async () => ({ matchId: 'm1' })) };
    const controller = new MatchController(matches as any);
    await controller.detail('match-1', { sub: 'user-1' });
    expect(matches.getDetail).toHaveBeenCalledWith('match-1', 'user-1');
  });
});
