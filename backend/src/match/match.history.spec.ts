jest.mock('../queue/queue.service', () => ({ QueueService: class QueueService {} }));

import { MatchService } from './match.service';

const hoursAgo = (h: number) => new Date(Date.now() - h * 3600_000);

function harness() {
  const matches = {
    findById: jest.fn(),
    findHistoryByUserId: jest.fn(),
    findRounds: jest.fn(),
    countRoundsByMatchIds: jest.fn(),
  };
  const users = { findByIds: jest.fn(async () => []) };
  const service = new MatchService(
    {} as any,
    matches as any,
    { publish: jest.fn() } as any,
    users as any,
    {} as any,
    {} as any,
    {} as any,
  );
  return { matches, users, service };
}

const row = (overrides: Record<string, unknown> = {}) => ({
  id: 'match-1',
  player1Id: 'user-1',
  player2Id: 'user-2',
  winnerId: 'user-1',
  status: 'finished',
  createdAt: hoursAgo(3),
  finishedAt: hoursAgo(2),
  ...overrides,
});

describe('MatchService.getHistory (#308)', () => {
  it('maps wins, losses, and draws with opponent names and durations', async () => {
    const { matches, users, service } = harness();
    matches.findHistoryByUserId.mockResolvedValue([
      row({ id: 'm1', winnerId: 'user-1' }),
      row({ id: 'm2', player1Id: 'user-9', player2Id: 'user-1', winnerId: 'user-9' }),
      row({ id: 'm3', winnerId: null, finishedAt: null }),
    ]);
    matches.countRoundsByMatchIds.mockResolvedValue(
      new Map([['m1', 7], ['m2', 5], ['m3', 0]]),
    );
    users.findByIds.mockResolvedValue([
      { id: 'user-2', username: 'bob' },
      { id: 'user-9', username: 'carol' },
    ]);

    const history = await service.getHistory('user-1');
    expect(history.map((h) => [h.matchId, h.winner])).toEqual([
      ['m1', 'self'],
      ['m2', 'opponent'],
      ['m3', null],
    ]);
    expect(history[0]).toMatchObject({
      opponent: { id: 'user-2', username: 'bob' },
      status: 'finished',
      rounds: 7,
      duration: 3600,
    });
    expect(history[2].duration).toBeNull();
  });

  it('falls back to null usernames for deleted opponents', async () => {
    const { matches, service } = harness();
    matches.findHistoryByUserId.mockResolvedValue([row()]);
    matches.countRoundsByMatchIds.mockResolvedValue(new Map());
    const history = await service.getHistory('user-1');
    expect(history[0].opponent).toEqual({ id: 'user-2', username: null });
    expect(history[0].rounds).toBe(0);
  });
});

describe('MatchService.getDetail (#308)', () => {
  it('returns participants, rounds, and winner names for members', async () => {
    const { matches, users, service } = harness();
    matches.findById.mockResolvedValue(row());
    users.findByIds.mockResolvedValue([
      { id: 'user-1', username: 'alice' },
      { id: 'user-2', username: 'bob' },
    ]);
    matches.findRounds.mockResolvedValue([
      { roundNumber: 1, events: [{ type: 'battle_end' }] },
    ]);

    const detail = await service.getDetail('match-1', 'user-2');
    expect(detail).toMatchObject({
      matchId: 'match-1',
      players: [
        { id: 'user-1', username: 'alice' },
        { id: 'user-2', username: 'bob' },
      ],
      winnerId: 'user-1',
      winner: 'alice',
      status: 'finished',
      rounds: [{ roundNumber: 1, events: [{ type: 'battle_end' }] }],
    });
    expect(detail.finishedAt).toEqual(expect.any(String));
  });

  it('rejects non-participants with match.not_your_match (403)', async () => {
    const { matches, service } = harness();
    matches.findById.mockResolvedValue(row());
    const err = await service.getDetail('match-1', 'intruder').catch((e) => e);
    expect(err.status).toBe(403);
    expect(err.response).toMatchObject({ code: 'match.not_your_match' });
  });

  it('reports unknown matches as 404', async () => {
    const { matches, service } = harness();
    matches.findById.mockResolvedValue(null);
    await expect(service.getDetail('missing', 'user-1')).rejects.toMatchObject({
      status: 404,
    });
  });
});
