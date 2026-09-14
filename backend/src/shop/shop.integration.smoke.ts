/** Real Redis + Postgres integration smoke for P0-BE-14. */
import 'reflect-metadata';
import { BadRequestException } from '@nestjs/common';
import { randomUUID } from 'crypto';
import { DataSource } from 'typeorm';
import { ENTITIES } from '../database/entities';
import { MatchRound } from '../match/match-round.entity';
import { Match } from '../match/match.entity';
import { MatchRepository } from '../match/match.repository';
import { MatchService } from '../match/match.service';
import { RedisService } from '../redis/redis.service';
import { initialRuntimeHash, parseRuntimeHash, runtimeKey } from '../runtime/match.runtime-state';
import { User } from '../user/user.entity';
import { UserService } from '../user/user.service';
import { ShopOffer, ShopService } from './shop.service';

interface Result { name: string; passed: boolean; detail: string }

class CapturePubsub {
  readonly events: Array<{ matchId: string; userId: string; type: string; payload: any }> = [];
  async publish() {}
  async publishToUser(matchId: string, userId: string, type: string, payload: unknown) {
    this.events.push({ matchId, userId, type, payload });
  }
}

function add(results: Result[], name: string, passed: boolean, detail: string) {
  results.push({ name, passed, detail });
}

function codeOf(error: unknown): string | undefined {
  if (!(error instanceof BadRequestException)) return undefined;
  return (error.getResponse() as { code?: string }).code;
}

function shopKey(matchId: string, userId: string) {
  return `match:${matchId}:shop:${userId}`;
}

function actionKey(matchId: string, userId: string) {
  return `match:${matchId}:actionLog:${userId}`;
}

function oneOffer(unitId: ShopOffer['unitId']): string {
  return JSON.stringify({
    round: 1,
    refreshCount: 0,
    refreshUsed: false,
    offers: [{ offerId: randomUUID(), unitId, star: 0 }],
  });
}

async function run() {
  const ds = new DataSource({
    type: 'postgres',
    url: process.env.DATABASE_URL ?? 'postgres://postgres:postgres@postgres-primary:5432/auto_chess',
    entities: ENTITIES,
    synchronize: false,
    logging: ['error'],
  });
  const redis = new RedisService();
  await Promise.all([ds.initialize(), redis.onModuleInit()]);
  const results: Result[] = [];
  const createdUsers: string[] = [];
  let matchId: string | null = null;

  try {
    const suffix = randomUUID().replaceAll('-', '').slice(0, 12);
    const userRepo = ds.getRepository(User);
    const users = await userRepo.save([
      userRepo.create({ email: `shopa-${suffix}@test.local`, username: `shopa${suffix}`, passwordHash: 'x'.repeat(60), rating: 1000 }),
      userRepo.create({ email: `shopb-${suffix}@test.local`, username: `shopb${suffix}`, passwordHash: 'x'.repeat(60), rating: 1000 }),
    ]);
    createdUsers.push(...users.map((user) => user.id));
    const repository = new MatchRepository(ds.getRepository(Match), ds.getRepository(MatchRound));
    const pubsub = new CapturePubsub();
    const matchService = new MatchService(ds, repository, pubsub as any, new UserService(userRepo));
    const match = await repository.create({
      player1Id: users[0].id,
      player2Id: users[1].id,
      matchSeed: randomUUID(),
      p1State: { hp: 100, gold: 5, ready: false, board: Array(9).fill(null), bench: Array(8).fill(null) },
      p2State: { hp: 100, gold: 5, ready: false, board: Array(9).fill(null), bench: Array(8).fill(null) },
    });
    matchId = match.id;
    await redis.client.hset(runtimeKey(match.id), initialRuntimeHash(match));

    const shops = Array.from({ length: 3 }, () =>
      new ShopService(redis, matchService, pubsub as any),
    );
    const runtime = parseRuntimeHash(match.id, await redis.client.hgetall(runtimeKey(match.id)))!;
    await shops[0].rollOffersForMatch(runtime);
    const firstOffers = pubsub.events.filter((event) => event.type === 'game:shop:offer');
    add(
      results,
      'each player receives five private deterministic offers',
      firstOffers.length === 2 && firstOffers.every((event) => event.payload.offers.length === 5),
      `events=${firstOffers.length} sizes=${firstOffers.map((event) => event.payload.offers.length).join(',')}`,
    );

    // Three Nest-equivalent service instances race to buy the same offer.
    await redis.client.set(shopKey(match.id, users[0].id), oneOffer('fighter'), 'EX', 1800);
    const actionIds = [randomUUID(), randomUUID(), randomUUID()];
    const buys = await Promise.allSettled(shops.map((shop, index) =>
      shop.buy(users[0].id, match.id, 1, 0, actionIds[index]),
    ));
    const afterBuy = parseRuntimeHash(match.id, await redis.client.hgetall(runtimeKey(match.id)))!;
    const buyWinners = buys.filter((result) => result.status === 'fulfilled').length;
    const retry = await shops[0].buy(users[0].id, match.id, 1, 0, actionIds[buys.findIndex((result) => result.status === 'fulfilled')]);
    add(
      results,
      'concurrent buy is serialized and retry is an idempotent no-op',
      buyWinners === 1 && afterBuy.p1State.gold === 4 &&
        afterBuy.p1State.bench.filter(Boolean).length === 1 && retry.duplicate,
      `winners=${buyWinners} gold=${afterBuy.p1State.gold} units=${afterBuy.p1State.bench.filter(Boolean).length}`,
    );

    // A second copy stays separate until drag-to-fuse; selling then returns
    // both copies' full investment.
    await redis.client.set(shopKey(match.id, users[0].id), oneOffer('fighter'), 'EX', 1800);
    await shops[0].buy(users[0].id, match.id, 1, 0, randomUUID());
    let state = parseRuntimeHash(match.id, await redis.client.hgetall(runtimeKey(match.id)))!.p1State;
    const copies = state.bench.filter((unit) => unit !== null);
    await shops[0].fuse(
      users[0].id,
      match.id,
      1,
      'fighter',
      randomUUID(),
      copies[0]!.instanceId,
      copies[1]!.instanceId,
    );
    state = parseRuntimeHash(match.id, await redis.client.hgetall(runtimeKey(match.id)))!.p1State;
    const fused = state.bench.find(Boolean)!;
    await shops[0].sell(users[0].id, match.id, 1, 'bench', state.bench.indexOf(fused), randomUUID());
    state = parseRuntimeHash(match.id, await redis.client.hgetall(runtimeKey(match.id)))!.p1State;
    add(
      results,
      'drag-to-fuse upgrades the target and sell refunds the full investment',
      fused.star === 1 && fused.investedGold === 2 && state.gold === 5 && state.bench.every((unit) => !unit),
      `star=${fused.star} invested=${fused.investedGold} goldAfterSell=${state.gold}`,
    );

    await redis.client.set(shopKey(match.id, users[0].id), oneOffer('tank'), 'EX', 1800);
    await shops[0].refresh(users[0].id, match.id, 1, randomUUID());
    let secondRefreshCode: string | undefined;
    try {
      await shops[1].refresh(users[0].id, match.id, 1, randomUUID());
    } catch (error) {
      secondRefreshCode = codeOf(error);
    }
    add(
      results,
      'refresh is free once per phase and the second call is rejected',
      secondRefreshCode === 'shop.refresh_used',
      `second=${secondRefreshCode}`,
    );

    const persisted = await repository.findById(match.id);
    add(
      results,
      'Redis shop mutations are mirrored to the Postgres match snapshot',
      Number((persisted!.p1State as any).gold) === 5,
      `dbGold=${(persisted!.p1State as any).gold}`,
    );
  } finally {
    if (matchId) {
      await ds.getRepository(MatchRound).delete({ matchId });
      await ds.getRepository(Match).delete({ id: matchId });
      await redis.client.del(
        runtimeKey(matchId),
        ...createdUsers.flatMap((userId) => [
          shopKey(matchId!, userId),
          actionKey(matchId!, userId),
          `match:${matchId}:shop-lock:${userId}`,
        ]),
      );
    }
    if (createdUsers.length) await ds.getRepository(User).delete(createdUsers);
    await Promise.allSettled([redis.onModuleDestroy(), ds.destroy()]);
  }

  console.log('\n[shop integration results]');
  for (const result of results) {
    console.log(`  ${result.passed ? 'PASS' : 'FAIL'}  ${result.name} — ${result.detail}`);
  }
  const passed = results.filter((result) => result.passed).length;
  console.log(`\n[summary] ${passed}/${results.length} passed`);
  if (passed !== results.length) process.exitCode = 1;
}

run().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
