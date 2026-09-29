import { readFileSync } from 'fs';
import { join } from 'path';
import RedisMock from 'ioredis-mock';

// MatchmakingService pulls the BullMQ worker chain (ESM-only under ts-jest);
// specs inject their own fakes, so stub the module like runtime-actions.spec.
jest.mock('../matchmaking/matchmaking.service', () => ({
  MatchmakingService: class MatchmakingService {},
}));
import { RoomService } from './room.service';
import { ROOM_TTL_SECONDS, roomCodeKey, roomHandoffKey, roomKey, userRoomKey } from './room.types';

const load = (name: string): string =>
  readFileSync(join(__dirname, '..', 'redis', 'scripts', `${name}.lua`), 'utf8');

const SOURCES: Record<string, string> = {
  room_join: load('room_join'),
  room_leave: load('room_leave'),
  room_start_match: load('room_start_match'),
  room_match_done: load('room_match_done'),
  room_match_abort: load('room_match_abort'),
};

type Mock = InstanceType<typeof RedisMock>;

class FakeMatches {
  active: unknown = null;
  async findActiveByUserId(userId: string): Promise<unknown> {
    const active = this.active as any;
    if (!active) return null;
    return active.player1Id === userId || active.player2Id === userId ? active : null;
  }
}

class FakePairing {
  calls: Array<[string, string]> = [];
  failNext: Error | null = null;
  nextMatchId = 'match-1';
  async createMatchForPlayers(player1Id: string, player2Id: string) {
    this.calls.push([player1Id, player2Id]);
    if (this.failNext) {
      const err = this.failNext;
      this.failNext = null;
      throw err;
    }
    return { matchId: this.nextMatchId, player1Id, player2Id };
  }
}

const makeService = () => {
  const mock: Mock = new RedisMock();
  const matches = new FakeMatches();
  const pairing = new FakePairing();
  const published: Array<{ roomId: string; type: string; payload: unknown; targets: string[] }> = [];
  const redis = {
    client: mock,
    eval: (name: string, keys: string[], args: (string | number)[]) =>
      mock.eval(SOURCES[name], keys.length, ...keys, ...args.map(String)),
  };
  const pubsub = {
    publishToRoom: async (roomId: string, type: string, payload: unknown, targets: string[]) => {
      published.push({ roomId, type, payload, targets });
    },
  };
  const service = new RoomService(redis as any, matches as any, pubsub as any, pairing as any);
  return { mock, matches, pairing, published, service };
};

beforeEach(async () => {
  await new RedisMock().flushall();
});

const seedFullRoom = async (mock: Mock) => {
  await mock.hset(roomKey('r1'), {
    roomId: 'r1',
    code: 'ABC234',
    ownerId: 'owner-1',
    guestId: 'guest-1',
    status: 'full',
    expiresAt: new Date(Date.now() + ROOM_TTL_SECONDS * 1000).toISOString(),
    matchId: '',
  });
  await mock.expire(roomKey('r1'), ROOM_TTL_SECONDS);
  await mock.set(roomCodeKey('ABC234'), 'r1', 'EX', ROOM_TTL_SECONDS);
  await mock.set(userRoomKey('owner-1'), 'r1', 'EX', ROOM_TTL_SECONDS);
  await mock.set(userRoomKey('guest-1'), 'r1', 'EX', ROOM_TTL_SECONDS);
};

describe('RoomService.startRoomMatch exactly-once (#259)', () => {
  it('concurrent triggers create exactly one match with one matchId', async () => {
    const { mock, pairing, published, service } = makeService();
    await seedFullRoom(mock);

    const [a, b] = await Promise.allSettled([
      service.startRoomMatch('r1'),
      service.startRoomMatch('r1'),
    ]);

    expect(pairing.calls).toHaveLength(1);
    expect(pairing.calls[0]).toEqual(['owner-1', 'guest-1']);
    // The loser either arrived after completion (same matchId) or while the
    // winner was still creating (retryable 409) — never a second match.
    for (const r of [a, b]) {
      if (r.status === 'fulfilled') {
        expect(r.value).toMatchObject({ status: 'matched', matchId: 'match-1', guestId: 'guest-1' });
      } else {
        expect(r.reason.response).toMatchObject({ code: 'room.match_starting' });
      }
    }
    expect([a, b].some((r) => r.status === 'fulfilled')).toBe(true);
    // Tombstone converges retries; live mappings are gone.
    expect(await mock.hget(roomKey('r1'), 'matchId')).toBe('match-1');
    expect(published.filter((p) => p.type === 'game:room:state')).toHaveLength(
      [a, b].filter((r) => r.status === 'fulfilled').length,
    );
  });

  it('PG failure releases the claim and the retry succeeds without loss', async () => {
    const { mock, pairing, service } = makeService();
    await seedFullRoom(mock);
    pairing.failNext = new Error('PG down');

    await expect(service.startRoomMatch('r1')).rejects.toThrow('PG down');
    // Room intact and retryable: still full, mappings present, no matchId.
    expect(await mock.hget(roomKey('r1'), 'status')).toBe('full');
    expect(await mock.get(userRoomKey('guest-1'))).toBe('r1');
    expect(await mock.hget(roomKey('r1'), 'matchId')).toBe('');
    expect(await mock.exists(roomHandoffKey('r1'))).toBe(0);

    const res = await service.startRoomMatch('r1');
    expect(res).toMatchObject({ status: 'matched', matchId: 'match-1' });
    expect(pairing.calls).toHaveLength(2);
  });

  it('a crashed attempt with an orphan row is adopted, not duplicated', async () => {
    const { mock, matches, pairing, service } = makeService();
    await seedFullRoom(mock);
    // Simulates: first attempt wrote the PG row then died before recording.
    matches.active = { id: 'm-orphan', player1Id: 'owner-1', player2Id: 'guest-1' };

    const res = await service.startRoomMatch('r1');

    expect(res).toMatchObject({ status: 'matched', matchId: 'm-orphan' });
    expect(pairing.calls).toHaveLength(0);
    expect(await mock.hget(roomKey('r1'), 'matchId')).toBe('m-orphan');
    expect(await mock.get(userRoomKey('owner-1'))).toBeNull();
    expect(await mock.get(userRoomKey('guest-1'))).toBeNull();
  });

  it('retry after completion converges on the recorded matchId', async () => {
    const { mock, pairing, service } = makeService();
    await seedFullRoom(mock);
    await service.startRoomMatch('r1');
    // Tombstone survives briefly so the duplicate trigger converges instead
    // of duplicating or reporting not_found.
    const retry = await service.startRoomMatch('r1');
    expect(retry).toMatchObject({ status: 'matched', matchId: 'match-1' });
    expect(pairing.calls).toHaveLength(1);
  });
});

describe('room handoff Lua scripts (#259)', () => {
  it('room_match_done is idempotent and never harms foreign mappings', async () => {
    const mock: Mock = new RedisMock();
    await mock.hset(roomKey('r1'), {
      roomId: 'r1',
      code: 'ABC234',
      ownerId: 'owner-1',
      guestId: 'guest-1',
      status: 'full',
      expiresAt: 'x',
      matchId: '',
    });
    await mock.set(roomCodeKey('ABC234'), 'r1');
    await mock.set(userRoomKey('owner-1'), 'r1');
    await mock.set(userRoomKey('guest-1'), 'r1');
    // Foreign mapping that must survive.
    await mock.set(userRoomKey('other'), 'r-other');

    const keys = [
      roomKey('r1'),
      roomCodeKey('ABC234'),
      userRoomKey('owner-1'),
      userRoomKey('guest-1'),
      roomHandoffKey('r1'),
    ];
    const first = await mock.eval(
      SOURCES.room_match_done,
      keys.length,
      ...keys,
      'r1',
      'match-9',
      'owner-1',
      'guest-1',
    );
    expect(String(first)).toBe('match-9');
    const second = await mock.eval(
      SOURCES.room_match_done,
      keys.length,
      ...keys,
      'r1',
      'match-other',
      'owner-1',
      'guest-1',
    );
    // Second run returns the recorded id — no duplicate result possible.
    expect(String(second)).toBe('match-9');
    expect(await mock.get(userRoomKey('other'))).toBe('r-other');
  });

  it('room_match_abort releases only the owning claim', async () => {
    const mock: Mock = new RedisMock();
    await mock.set(roomHandoffKey('r1'), 'token-a', 'EX', 120);
    expect(
      await mock.eval(SOURCES.room_match_abort, 1, roomHandoffKey('r1'), 'token-b'),
    ).toBe(0);
    expect(await mock.get(roomHandoffKey('r1'))).toBe('token-a');
    expect(
      await mock.eval(SOURCES.room_match_abort, 1, roomHandoffKey('r1'), 'token-a'),
    ).toBe(1);
    expect(await mock.get(roomHandoffKey('r1'))).toBeNull();
  });
});
