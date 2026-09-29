import { ConflictException, NotFoundException } from '@nestjs/common';
import { MATCHMAKING_QUEUE_KEY } from '../matchmaking/matchmaking.keys';
import { RoomService } from './room.service';
import { randomRoomCode, roomCodeKey, roomKey, userRoomKey } from './room.types';

/** Minimal ioredis-shaped fake covering the room commands. */
class FakeRedisClient {
  readonly strings = new Map<string, string>();
  readonly hashes = new Map<string, Record<string, string>>();
  readonly expirations = new Map<string, number>();
  readonly zsets = new Map<string, Map<string, number>>();
  failNext: Error | null = null;

  private maybeFail(): void {
    if (this.failNext) {
      const err = this.failNext;
      this.failNext = null;
      throw err;
    }
  }

  async get(key: string): Promise<string | null> {
    this.maybeFail();
    return this.strings.get(key) ?? null;
  }

  async set(key: string, value: string, ...opts: (string | number)[]): Promise<string | null> {
    this.maybeFail();
    const nx = opts.includes('NX');
    if (nx && this.strings.has(key)) return null;
    this.strings.set(key, value);
    const exAt = opts.indexOf('EX');
    if (exAt >= 0) this.expirations.set(key, Number(opts[exAt + 1]));
    return 'OK';
  }

  async hset(key: string, obj: Record<string, string>): Promise<number> {
    this.maybeFail();
    this.hashes.set(key, { ...obj });
    return Object.keys(obj).length;
  }

  async hgetall(key: string): Promise<Record<string, string>> {
    this.maybeFail();
    return this.hashes.get(key) ?? {};
  }

  async expire(key: string, seconds: number): Promise<number> {
    this.maybeFail();
    this.expirations.set(key, seconds);
    return 1;
  }

  async del(...keys: string[]): Promise<number> {
    this.maybeFail();
    let n = 0;
    for (const key of keys) {
      if (this.strings.delete(key)) n += 1;
      if (this.hashes.delete(key)) n += 1;
    }
    return n;
  }

  async zscore(key: string, member: string): Promise<string | null> {
    this.maybeFail();
    const score = this.zsets.get(key)?.get(member);
    return score === undefined ? null : String(score);
  }
}

class FakeMatches {
  active: unknown = null;
  async findActiveByUserId(_userId: string): Promise<unknown> {
    return this.active as any;
  }
}

/** Deterministic code sequence for collision tests. */
class ScriptedRoomService extends RoomService {
  constructor(
    redis: unknown,
    matches: unknown,
    private readonly codes: string[],
  ) {
    super(redis as any, matches as any);
  }

  protected override randomCode(): string {
    const next = this.codes.shift();
    if (!next) throw new Error('no more scripted codes');
    return next;
  }
}

const makeService = () => {
  const client = new FakeRedisClient();
  const matches = new FakeMatches();
  const service = new RoomService({ client } as any, matches as any);
  return { client, matches, service };
};

describe('randomRoomCode (#255)', () => {
  it('generates 6-char codes from the allowed alphabet', () => {
    for (let i = 0; i < 500; i += 1) {
      expect(randomRoomCode()).toMatch(/^[A-Z2-9]{6}$/);
    }
  });

  it('excludes ambiguous characters 0/O/1/I', () => {
    for (let i = 0; i < 500; i += 1) {
      expect(randomRoomCode()).not.toMatch(/[01OI]/);
    }
  });
});

describe('RoomService.createRoom (#255)', () => {
  it('creates a waiting room with mapping, state, and TTLs', async () => {
    const { client, service } = makeService();
    const room = await service.createRoom('owner-1');

    expect(room.code).toMatch(/^[A-Z2-9]{6}$/);
    expect(room).toMatchObject({
      ownerId: 'owner-1',
      guestId: null,
      status: 'waiting',
    });
    expect(typeof room.roomId).toBe('string');
    expect(new Date(room.expiresAt).getTime()).toBeGreaterThan(Date.now());

    // Owner mapping stored.
    expect(client.strings.get(userRoomKey('owner-1'))).toBe(room.roomId);
    // Room hash stored.
    expect(client.hashes.get(roomKey(room.roomId))).toMatchObject({
      code: room.code,
      ownerId: 'owner-1',
      status: 'waiting',
    });
    // Code claim stored.
    expect(client.strings.get(roomCodeKey(room.code))).toBe(room.roomId);
    // TTLs applied (45 min = 2700 s).
    expect(client.expirations.get(userRoomKey('owner-1'))).toBe(45 * 60);
    expect(client.expirations.get(roomCodeKey(room.code))).toBe(45 * 60);
    expect(client.expirations.get(roomKey(room.roomId))).toBe(45 * 60);
  });

  it('retries on code collision and claims the free code', async () => {
    const client = new FakeRedisClient();
    client.strings.set(roomCodeKey('AAAAAA'), 'other-room');
    const service = new ScriptedRoomService({ client } as any, new FakeMatches(), [
      'AAAAAA',
      'BBBBBB',
    ]);

    const room = await service.createRoom('owner-1');
    expect(room.code).toBe('BBBBBB');
    expect(client.strings.get(roomCodeKey('BBBBBB'))).toBe(room.roomId);
  });

  it('rejects a user already in a room', async () => {
    const { client, service } = makeService();
    client.strings.set(userRoomKey('owner-1'), 'room-old');
    await expect(service.createRoom('owner-1')).rejects.toMatchObject({
      status: 409,
      response: { code: 'room.already_in_room' },
    });
    expect(client.hashes.size).toBe(0);
  });

  it('rejects a user with an active match and releases the claim', async () => {
    const { client, matches, service } = makeService();
    matches.active = { id: 'match-1' } as any;
    const err = await service.createRoom('owner-1').catch((e) => e);
    expect(err).toBeInstanceOf(ConflictException);
    expect(err.response).toMatchObject({ code: 'match.already_active' });
    await expect(client.get(userRoomKey('owner-1'))).resolves.toBeNull();
  });

  it('rejects a user currently in the matchmaking queue', async () => {
    const { client, service } = makeService();
    client.zsets.set(MATCHMAKING_QUEUE_KEY, new Map([['owner-1', Date.now()]]));
    const err = await service.createRoom('owner-1').catch((e) => e);
    expect(err).toBeInstanceOf(ConflictException);
    expect(err.response).toMatchObject({ code: 'room.in_matchmaking_queue' });
    await expect(client.get(userRoomKey('owner-1'))).resolves.toBeNull();
  });

  it('propagates Redis failures (Redis is the store, no fallback)', async () => {
    const { client, service } = makeService();
    client.failNext = new Error('Redis down');
    await expect(service.createRoom('owner-1')).rejects.toThrow('Redis down');
  });
});

describe('RoomService.getMyRoom (#255)', () => {
  it('returns the user room', async () => {
    const { service } = makeService();
    const created = await service.createRoom('owner-1');
    await expect(service.getMyRoom('owner-1')).resolves.toEqual(created);
  });

  it('reports not-in-room when no mapping exists', async () => {
    const { service } = makeService();
    const err = await service.getMyRoom('ghost').catch((e) => e);
    expect(err).toBeInstanceOf(NotFoundException);
    expect(err.response).toMatchObject({ code: 'room.not_in_room' });
  });

  it('cleans a stale mapping when the room hash expired', async () => {
    const { client, service } = makeService();
    client.strings.set(userRoomKey('owner-1'), 'room-gone');
    const err = await service.getMyRoom('owner-1').catch((e) => e);
    expect(err).toBeInstanceOf(NotFoundException);
    expect(err.response).toMatchObject({ code: 'room.not_found' });
    await expect(client.get(userRoomKey('owner-1'))).resolves.toBeNull();
  });
});
