import { readFileSync } from 'fs';
import { join } from 'path';
import RedisMock from 'ioredis-mock';

// See room.handoff.spec.ts — stub the BullMQ-chained module.
jest.mock('../matchmaking/matchmaking.service', () => ({
  MatchmakingService: class MatchmakingService {},
}));
import { MATCHMAKING_QUEUE_KEY } from '../matchmaking/matchmaking.keys';
import { RoomService } from './room.service';
import { ROOM_TTL_SECONDS, roomCodeKey, roomKey, userRoomKey } from './room.types';

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

// ioredis-mock instances share one global store — flush before every test
// so seeded keys never leak across cases (mirrors lua.spec.ts).
beforeEach(async () => {
  await new RedisMock().flushall();
});

const seedRoom = async (
  mock: Mock,
  opts: { roomId: string; code: string; owner: string; guest?: string; status?: string },
) => {
  await mock.hset(roomKey(opts.roomId), {
    roomId: opts.roomId,
    code: opts.code,
    ownerId: opts.owner,
    guestId: opts.guest ?? '',
    status: opts.status ?? 'waiting',
    expiresAt: new Date(Date.now() + ROOM_TTL_SECONDS * 1000).toISOString(),
  });
  await mock.expire(roomKey(opts.roomId), ROOM_TTL_SECONDS);
  await mock.set(roomCodeKey(opts.code), opts.roomId, 'EX', ROOM_TTL_SECONDS);
  await mock.set(userRoomKey(opts.owner), opts.roomId, 'EX', ROOM_TTL_SECONDS);
};

describe('RoomService.joinRoom (#258)', () => {
  it('joins the lobby and waits for the owner to start', async () => {
    const { mock, pairing, published, service } = makeService();
    await seedRoom(mock, { roomId: 'r1', code: 'ABC234', owner: 'owner-1' });

    const room = await service.joinRoom('guest-1', 'abc234');

    expect(room).toMatchObject({
      roomId: 'r1',
      code: 'ABC234',
      ownerId: 'owner-1',
      guestId: 'guest-1',
      status: 'full',
      matchId: null,
    });
    expect(pairing.calls).toEqual([]);
    expect(await mock.hget(roomKey('r1'), 'status')).toBe('full');
    expect(await mock.hget(roomKey('r1'), 'matchId')).toBeNull();
    expect(await mock.get(roomCodeKey('ABC234'))).toBe('r1');
    expect(await mock.get(userRoomKey('owner-1'))).toBe('r1');
    expect(await mock.get(userRoomKey('guest-1'))).toBe('r1');
    expect(published).toEqual([
      {
        roomId: 'r1',
        type: 'game:room:state',
        payload: room,
        targets: ['owner-1', 'guest-1'],
      },
    ]);
  });

  it('rejects the owner joining their own room', async () => {
    const { mock, service } = makeService();
    await seedRoom(mock, { roomId: 'r1', code: 'ABC234', owner: 'owner-1' });
    // Drop the owner mapping to reach the Lua owner guard (with a mapping
    // the service rejects earlier with already_in_room, also correct).
    await mock.del(userRoomKey('owner-1'));
    await expect(service.joinRoom('owner-1', 'ABC234')).rejects.toMatchObject({
      response: { code: 'room.owner_cannot_join' },
    });
  });

  it.each([[''], ['abc'], ['TOOLONG1'], ['ABC23!'], ['ABC 34']])(
    'rejects invalid code format %p',
    async (code) => {
      const { service } = makeService();
      await expect(service.joinRoom('guest-1', code)).rejects.toMatchObject({
        response: { code: 'room.invalid_code' },
      });
    },
  );

  it('rejects an unknown code', async () => {
    const { service } = makeService();
    await expect(service.joinRoom('guest-1', 'ZZZZ99')).rejects.toMatchObject({
      response: { code: 'room.not_found' },
    });
  });

  it('rejects an expired room (code mapping without room hash)', async () => {
    const { mock, service } = makeService();
    await mock.set(roomCodeKey('ABC234'), 'r-gone', 'EX', 60);
    await expect(service.joinRoom('guest-1', 'ABC234')).rejects.toMatchObject({
      response: { code: 'room.not_found' },
    });
    expect(await mock.get(userRoomKey('guest-1'))).toBeNull();
  });

  it('rejects a full room', async () => {
    const { mock, service } = makeService();
    await seedRoom(mock, {
      roomId: 'r1',
      code: 'ABC234',
      owner: 'owner-1',
      guest: 'guest-1',
      status: 'full',
    });
    await expect(service.joinRoom('guest-2', 'ABC234')).rejects.toMatchObject({
      response: { code: 'room.full' },
    });
    expect(await mock.get(userRoomKey('guest-2'))).toBeNull();
  });

  it('rejects a user already in another room', async () => {
    const { mock, service } = makeService();
    await seedRoom(mock, { roomId: 'r1', code: 'ABC234', owner: 'owner-1' });
    await mock.set(userRoomKey('guest-1'), 'r-other', 'EX', 60);
    await expect(service.joinRoom('guest-1', 'ABC234')).rejects.toMatchObject({
      response: { code: 'room.already_in_room' },
    });
  });

  it('rejects a user with an active match or queue entry', async () => {
    const { mock, matches, service } = makeService();
    await seedRoom(mock, { roomId: 'r1', code: 'ABC234', owner: 'owner-1' });
    matches.active = { id: 'm1', player1Id: 'guest-1', player2Id: 'other' } as any;
    await expect(service.joinRoom('guest-1', 'ABC234')).rejects.toMatchObject({
      response: { code: 'match.already_active' },
    });
    matches.active = null;
    await mock.zadd(MATCHMAKING_QUEUE_KEY, Date.now(), 'guest-1');
    await expect(service.joinRoom('guest-1', 'ABC234')).rejects.toMatchObject({
      response: { code: 'room.in_matchmaking_queue' },
    });
  });

  it('concurrent joins: exactly one guest wins the slot, loser stays clean', async () => {
    const { mock, pairing, service } = makeService();
    await seedRoom(mock, { roomId: 'r1', code: 'ABC234', owner: 'owner-1' });

    const [a, b] = await Promise.allSettled([
      service.joinRoom('guest-B', 'ABC234'),
      service.joinRoom('guest-C', 'ABC234'),
    ]);
    const fulfilled = [a, b].filter((r) => r.status === 'fulfilled');
    const rejected = [a, b].filter((r) => r.status === 'rejected');
    expect(fulfilled).toHaveLength(1);
    expect(rejected).toHaveLength(1);
    expect((rejected[0] as PromiseRejectedResult).reason.response).toMatchObject({
      code: 'room.full',
    });

    const winner = (fulfilled[0] as PromiseFulfilledResult<any>).value;
    expect(winner.status).toBe('full');
    const winnerId = winner.guestId as string;
    const loserId = winnerId === 'guest-B' ? 'guest-C' : 'guest-B';
    expect(pairing.calls).toHaveLength(0);
    expect(winner.matchId).toBeNull();
    expect(await mock.get(userRoomKey(loserId))).toBeNull();
    expect(await mock.hget(roomKey('r1'), 'matchId')).toBeNull();
  });
});

describe('RoomService.leaveRoom (#258)', () => {
  it('guest leave: waiting, guest cleared, owner notified, owner kept', async () => {
    const { mock, published, service } = makeService();
    await seedRoom(mock, {
      roomId: 'r1',
      code: 'ABC234',
      owner: 'owner-1',
      guest: 'guest-1',
      status: 'full',
    });
    await mock.set(userRoomKey('guest-1'), 'r1', 'EX', ROOM_TTL_SECONDS);

    const res = await service.leaveRoom('guest-1');

    expect(res.closed).toBe(false);
    expect(res.room).toMatchObject({ roomId: 'r1', guestId: null, status: 'waiting' });
    expect(await mock.get(userRoomKey('guest-1'))).toBeNull();
    expect(await mock.get(userRoomKey('owner-1'))).toBe('r1');
    expect(published).toEqual([
      {
        roomId: 'r1',
        type: 'game:room:state',
        payload: res.room,
        targets: ['owner-1'],
      },
    ]);
  });

  it('a freed slot can be joined again', async () => {
    const { mock, service } = makeService();
    await seedRoom(mock, {
      roomId: 'r1',
      code: 'ABC234',
      owner: 'owner-1',
      guest: 'guest-1',
      status: 'full',
    });
    await mock.set(userRoomKey('guest-1'), 'r1', 'EX', ROOM_TTL_SECONDS);
    await service.leaveRoom('guest-1');
    const room = await service.joinRoom('guest-2', 'ABC234');
    expect(room).toMatchObject({ guestId: 'guest-2', status: 'full', matchId: null });
  });

  it('owner leave destroys everything and notifies the guest with closed', async () => {
    const { mock, published, service } = makeService();
    await seedRoom(mock, {
      roomId: 'r1',
      code: 'ABC234',
      owner: 'owner-1',
      guest: 'guest-1',
      status: 'full',
    });
    await mock.set(userRoomKey('guest-1'), 'r1', 'EX', ROOM_TTL_SECONDS);

    const res = await service.leaveRoom('owner-1');

    expect(res).toEqual({ room: null, closed: true });
    expect(await mock.exists(roomKey('r1'))).toBe(0);
    expect(await mock.get(roomCodeKey('ABC234'))).toBeNull();
    expect(await mock.get(userRoomKey('owner-1'))).toBeNull();
    expect(await mock.get(userRoomKey('guest-1'))).toBeNull();
    expect(published).toEqual([
      {
        roomId: 'r1',
        type: 'game:room:state',
        payload: expect.objectContaining({ status: 'closed', guestId: 'guest-1' }),
        targets: ['guest-1'],
      },
    ]);
  });

  it('owner leave without a guest notifies nobody and still destroys', async () => {
    const { mock, published, service } = makeService();
    await seedRoom(mock, { roomId: 'r1', code: 'ABC234', owner: 'owner-1' });
    const res = await service.leaveRoom('owner-1');
    expect(res).toEqual({ room: null, closed: true });
    expect(await mock.exists(roomKey('r1'))).toBe(0);
    expect(published).toHaveLength(0);
  });

  it('leave without a room is a 404', async () => {
    const { service } = makeService();
    await expect(service.leaveRoom('ghost')).rejects.toMatchObject({
      response: { code: 'room.not_in_room' },
    });
  });

  it('a stale mapping cannot delete another mapping or room', async () => {
    const { mock, service } = makeService();
    await seedRoom(mock, { roomId: 'r1', code: 'ABC234', owner: 'owner-1' });
    // Intruder mapping points at someone else's room without membership.
    await mock.set(userRoomKey('intruder'), 'r1', 'EX', ROOM_TTL_SECONDS);
    await expect(service.leaveRoom('intruder')).rejects.toMatchObject({
      response: { code: 'room.not_in_room' },
    });
    // Victim state untouched; only the intruder's own bogus mapping is gone.
    expect(await mock.get(userRoomKey('owner-1'))).toBe('r1');
    expect(await mock.hget(roomKey('r1'), 'status')).toBe('waiting');
    expect(await mock.get(userRoomKey('intruder'))).toBeNull();
  });
});
