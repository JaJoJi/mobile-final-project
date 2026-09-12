import { BadRequestException } from '@nestjs/common';
import { randomUUID } from 'crypto';
import type { Match } from '../match/match.entity';
import { initialRuntimeHash, runtimeKey } from '../runtime/match.runtime-state';
import { ShopOffer, ShopService } from './shop.service';

class FakeRedis {
  readonly hashes = new Map<string, Record<string, string>>();
  readonly strings = new Map<string, string>();
  beforeActionCommit?: () => void;

  readonly client = {
    hset: async (key: string, fieldOrMap: string | Record<string, string>, value?: string) => {
      const hash = this.hashes.get(key) ?? {};
      if (typeof fieldOrMap === 'string') hash[fieldOrMap] = String(value);
      else Object.assign(hash, fieldOrMap);
      this.hashes.set(key, hash);
      return 1;
    },
    hgetall: async (key: string) => ({ ...(this.hashes.get(key) ?? {}) }),
    hexists: async (key: string, field: string) => Number(Boolean(this.hashes.get(key)?.[field])),
    get: async (key: string) => this.strings.get(key) ?? null,
    set: async (key: string, value: string, ...args: Array<string | number>) => {
      if (args.includes('NX') && this.strings.has(key)) return null;
      this.strings.set(key, value);
      return 'OK';
    },
    eval: async (_source: string, _keyCount: number, key: string, owner: string) => {
      if (this.strings.get(key) !== owner) return 0;
      this.strings.delete(key);
      return 1;
    },
  };

  async eval<T>(name: string, keys: string[], args: Array<string | number>): Promise<T> {
    if (name !== 'action_log') throw new Error(`unknown script ${name}`);
    const [logKey, matchRuntimeKey, playerShopKey] = keys;
    const [actionId, timestamp, stateField, stateJson, shopJson] = args.map(String);
    const log = this.hashes.get(logKey) ?? {};
    if (log[actionId]) return 0 as T;
    this.beforeActionCommit?.();
    this.beforeActionCommit = undefined;
    const current = this.hashes.get(matchRuntimeKey) ?? {};
    if (current.round !== String(args[7])) return -2 as T;
    if (current.phase !== String(args[6])) return -1 as T;
    log[actionId] = timestamp;
    this.hashes.set(logKey, log);
    const runtime = this.hashes.get(matchRuntimeKey) ?? {};
    runtime[stateField] = stateJson;
    this.hashes.set(matchRuntimeKey, runtime);
    this.strings.set(playerShopKey, shopJson);
    return 1 as T;
  }
}

class FakeMatches {
  readonly updates: Array<{ matchId: string; side: string; state: any }> = [];
  async updateState(matchId: string, side: string, state: unknown) {
    this.updates.push({ matchId, side, state: structuredClone(state) });
  }
}

class FakePubsub {
  readonly events: Array<{ matchId: string; userId: string; type: string; payload: any }> = [];
  async publishToUser(matchId: string, userId: string, type: string, payload: unknown) {
    this.events.push({ matchId, userId, type, payload: structuredClone(payload) });
  }
}

function makeMatch(gold = 20): Match {
  return {
    id: randomUUID(),
    player1Id: randomUUID(),
    player2Id: randomUUID(),
    matchSeed: randomUUID(),
    p1State: { hp: 100, gold, ready: false, board: Array(9).fill(null), bench: Array(8).fill(null) },
    p2State: { hp: 100, gold, ready: false, board: Array(9).fill(null), bench: Array(8).fill(null) },
    wipeIndexP1: 0,
    wipeIndexP2: 0,
    winnerId: null,
    status: 'in_progress',
    createdAt: new Date(),
    finishedAt: null,
  };
}

function harness(gold = 20) {
  const redis = new FakeRedis();
  const matches = new FakeMatches();
  const pubsub = new FakePubsub();
  const service = new ShopService(redis as any, matches as any, pubsub as any);
  const match = makeMatch(gold);
  redis.hashes.set(runtimeKey(match.id), initialRuntimeHash(match));
  return { redis, matches, pubsub, service, match };
}

function shopKey(matchId: string, userId: string) {
  return `match:${matchId}:shop:${userId}`;
}

function readPlayerState(h: ReturnType<typeof harness>) {
  return JSON.parse(h.redis.hashes.get(runtimeKey(h.match.id))!.p1State);
}

function setShop(h: ReturnType<typeof harness>, offers: ShopOffer[]) {
  h.redis.strings.set(shopKey(h.match.id, h.match.player1Id), JSON.stringify({
    round: 1,
    refreshCount: 0,
    refreshUsed: false,
    offers,
  }));
}

function offer(unitId: ShopOffer['unitId'], index = 0): ShopOffer {
  return { offerId: deterministicUuid(index), unitId, star: 0 };
}

function deterministicUuid(index: number) {
  return `00000000-0000-4000-a000-${String(index).padStart(12, '0')}`;
}

function errorCode(error: unknown): string | undefined {
  if (!(error instanceof BadRequestException)) return undefined;
  return (error.getResponse() as { code?: string }).code;
}

describe('ShopService — P0-BE-14', () => {
  it('returns identical offers for the same seed tuple', () => {
    const h = harness();
    const first = h.service.generateOffers('seed', 3, 'player', 0);
    expect(h.service.generateOffers('seed', 3, 'player', 0)).toEqual(first);
    expect(h.service.generateOffers('seed', 3, 'other-player', 0)).not.toEqual(first);
    expect(first).toHaveLength(5);
  });

  it('matches the 40/40/15/5 pool distribution over 10,000 rolls', () => {
    const h = harness();
    const counts = { fighter: 0, healer: 0, ranger: 0, tank: 0 };
    for (let index = 0; index < 2_000; index += 1) {
      for (const item of h.service.generateOffers(`seed-${index}`, 1, 'player')) {
        counts[item.unitId] += 1;
      }
    }
    expect(counts.fighter / 10_000).toBeGreaterThan(0.37);
    expect(counts.fighter / 10_000).toBeLessThan(0.43);
    expect(counts.healer / 10_000).toBeGreaterThan(0.37);
    expect(counts.healer / 10_000).toBeLessThan(0.43);
    expect(counts.ranger / 10_000).toBeGreaterThan(0.13);
    expect(counts.ranger / 10_000).toBeLessThan(0.17);
    expect(counts.tank / 10_000).toBeGreaterThan(0.04);
    expect(counts.tank / 10_000).toBeLessThan(0.06);
  });

  it('rolls exactly five private offers for each player', async () => {
    const h = harness();
    const runtime = { ...JSON.parse(JSON.stringify(h.match)), phase: 'shop_place', round: 1 } as any;
    runtime.matchId = h.match.id;
    await h.service.rollOffersForMatch(runtime);
    const offerEvents = h.pubsub.events.filter((event) => event.type === 'game:shop:offer');
    expect(offerEvents).toHaveLength(2);
    expect(new Set(offerEvents.map((event) => event.userId))).toEqual(
      new Set([h.match.player1Id, h.match.player2Id]),
    );
    expect(offerEvents.every((event) => event.payload.offers.length === 5)).toBe(true);
  });

  it('buy deducts gold, fills the bench and a retry is a no-op', async () => {
    const h = harness(5);
    setShop(h, [offer('tank')]);
    const actionId = randomUUID();
    expect(await h.service.buy(h.match.player1Id, h.match.id, 1, 0, actionId))
      .toEqual({ duplicate: false });
    expect(await h.service.buy(h.match.player1Id, h.match.id, 1, 0, actionId))
      .toEqual({ duplicate: true });
    const state = readPlayerState(h);
    expect(state.gold).toBe(3);
    expect(state.bench.filter(Boolean)).toHaveLength(1);
    expect(h.matches.updates).toHaveLength(1);
  });

  it('buy keeps a duplicate in the bench until the player fuses it', async () => {
    const h = harness(5);
    const hash = h.redis.hashes.get(runtimeKey(h.match.id))!;
    const state = JSON.parse(hash.p1State);
    state.bench[0] = { instanceId: randomUUID(), unitId: 'fighter', star: 0, hp: 100, maxHp: 100, investedGold: 1 };
    hash.p1State = JSON.stringify(state);
    setShop(h, [offer('fighter')]);
    await h.service.buy(h.match.player1Id, h.match.id, 1, 0, randomUUID());
    const updated = readPlayerState(h);
    expect(updated.bench.filter(Boolean)).toHaveLength(2);
    expect(updated.bench[0]).toMatchObject({ unitId: 'fighter', star: 0 });
    expect(updated.bench[1]).toMatchObject({ unitId: 'fighter', star: 0 });
  });

  it('sell refunds the full invested cost of a fused unit', async () => {
    const h = harness(5);
    const hash = h.redis.hashes.get(runtimeKey(h.match.id))!;
    const state = JSON.parse(hash.p1State);
    state.board[0] = { instanceId: randomUUID(), unitId: 'tank', star: 1, hp: 150, maxHp: 150, investedGold: 4 };
    hash.p1State = JSON.stringify(state);
    setShop(h, [offer('fighter')]);
    await h.service.sell(h.match.player1Id, h.match.id, 1, 'board', 0, randomUUID());
    const updated = readPlayerState(h);
    expect(updated.gold).toBe(9);
    expect(updated.board[0]).toBeNull();
  });

  it('allows one deterministic refresh then rejects shop.refresh_used', async () => {
    const h = harness();
    await h.service.rollOffersForMatch({
      matchId: h.match.id,
      player1Id: h.match.player1Id,
      player2Id: h.match.player2Id,
      matchSeed: h.match.matchSeed,
      phase: 'shop_place',
      round: 1,
      p1State: h.match.p1State,
      p2State: h.match.p2State,
      readyP1: false,
      readyP2: false,
      wipeIndexP1: 0,
      wipeIndexP2: 0,
      combatRound: null,
    } as any);
    await h.service.refresh(h.match.player1Id, h.match.id, 1, randomUUID());
    const refreshed = h.pubsub.events.filter((event) =>
      event.userId === h.match.player1Id && event.type === 'game:shop:offer',
    ).at(-1)!.payload.offers;
    expect(refreshed).toEqual(
      h.service.generateOffers(h.match.matchSeed, 1, h.match.player1Id, 1),
    );
    await expect(
      h.service.refresh(h.match.player1Id, h.match.id, 1, randomUUID()),
    ).rejects.toMatchObject({ response: { code: 'shop.refresh_used' } });
  });

  it('manually fuses two same-star copies and rejects an invalid fuse', async () => {
    const h = harness();
    const hash = h.redis.hashes.get(runtimeKey(h.match.id))!;
    const state = JSON.parse(hash.p1State);
    state.board[0] = { instanceId: randomUUID(), unitId: 'ranger', star: 0, hp: 60, maxHp: 60 };
    state.bench[0] = { instanceId: randomUUID(), unitId: 'ranger', star: 0, hp: 60, maxHp: 60 };
    hash.p1State = JSON.stringify(state);
    setShop(h, [offer('fighter')]);
    await h.service.fuse(h.match.player1Id, h.match.id, 1, 'ranger', randomUUID());
    const updated = readPlayerState(h);
    expect(updated.board[0]).toMatchObject({ unitId: 'ranger', star: 1, investedGold: 4 });
    expect(updated.bench[0]).toBeNull();
    await expect(
      h.service.fuse(h.match.player1Id, h.match.id, 1, 'ranger', randomUUID()),
    ).rejects.toMatchObject({ response: { code: 'shop.cannot_fuse' } });
  });

  it('fuses the dragged source into the exact target instance', async () => {
    const h = harness();
    const hash = h.redis.hashes.get(runtimeKey(h.match.id))!;
    const state = JSON.parse(hash.p1State);
    const sourceId = randomUUID();
    const targetId = randomUUID();
    state.board[2] = { instanceId: sourceId, unitId: 'healer', star: 0, hp: 80, maxHp: 80 };
    state.bench[5] = { instanceId: targetId, unitId: 'healer', star: 0, hp: 80, maxHp: 80 };
    hash.p1State = JSON.stringify(state);
    setShop(h, [offer('fighter')]);

    await h.service.fuse(
      h.match.player1Id,
      h.match.id,
      1,
      'healer',
      randomUUID(),
      sourceId,
      targetId,
    );

    const updated = readPlayerState(h);
    expect(updated.board[2]).toBeNull();
    expect(updated.bench[5]).toMatchObject({
      instanceId: targetId,
      unitId: 'healer',
      star: 1,
    });
  });

  it('never lets gold go negative', async () => {
    const h = harness(0);
    setShop(h, [offer('tank')]);
    try {
      await h.service.buy(h.match.player1Id, h.match.id, 1, 0, randomUUID());
      throw new Error('expected insufficient gold');
    } catch (error) {
      expect(errorCode(error)).toBe('shop.insufficient_gold');
    }
    expect(readPlayerState(h).gold).toBe(0);
  });

  it('atomically rejects an action when the phase flips before commit', async () => {
    const h = harness(5);
    setShop(h, [offer('fighter')]);
    h.redis.beforeActionCommit = () => {
      h.redis.hashes.get(runtimeKey(h.match.id))!.phase = 'battle';
    };
    await expect(
      h.service.buy(h.match.player1Id, h.match.id, 1, 0, randomUUID()),
    ).rejects.toMatchObject({ response: { code: 'match.not_your_turn' } });
    expect(readPlayerState(h).gold).toBe(5);
  });
});
