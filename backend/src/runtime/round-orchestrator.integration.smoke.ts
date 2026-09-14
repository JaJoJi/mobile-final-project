/**
 * Real Redis + Postgres integration smoke for P0-BE-13.
 * Run inside the Docker network while postgres-primary and redis are up:
 *   docker compose exec -T nest-1 npm run smoke:round-orchestrator:integration
 */
import 'reflect-metadata';
import { randomUUID } from 'crypto';
import { Queue } from 'bullmq';
import { DataSource } from 'typeorm';
import { ENTITIES } from '../database/entities';
import { runBattle } from '../game';
import { MatchRound } from '../match/match-round.entity';
import { Match } from '../match/match.entity';
import { MatchRepository } from '../match/match.repository';
import { MatchService } from '../match/match.service';
import { JOB_NAMES, QUEUE_NAMES } from '../queue/queue.constants';
import { RedisService } from '../redis/redis.service';
import { User } from '../user/user.entity';
import { UserService } from '../user/user.service';
import { CombatCoordinator } from './combat.coordinator';
import { MatchRuntimeAdapter } from './match.runtime.adapter';
import { initialRuntimeHash, runtimeKey } from './match.runtime-state';

interface Result { name: string; passed: boolean; detail: string }

class CaptureQueue {
  readonly phases: any[] = [];
  readonly timeouts: any[] = [];
  async schedulePhaseStart(matchId: string, round: number, delay: number) {
    this.phases.push({ matchId, round, delay });
  }
  async scheduleCombatDoneTimeout(matchId: string, round: number, delay: number) {
    this.timeouts.push({ matchId, round, delay });
  }
}

class RedisPubsub {
  readonly events: Array<{
    matchId: string;
    type: string;
    payload: any;
    targetUserId?: string;
  }> = [];
  constructor(private readonly redis: RedisService) {}
  async publish(matchId: string, type: string, payload: unknown) {
    this.events.push({ matchId, type, payload });
  }
  async publishToUser(
    matchId: string,
    targetUserId: string,
    type: string,
    payload: unknown,
  ) {
    this.events.push({ matchId, type, payload, targetUserId });
  }
  async writeCombatResult(matchId: string, events: any[]) {
    await this.redis.client.set(
      `match:${matchId}:combat-result`,
      JSON.stringify(events),
      'EX',
      60,
    );
  }
  async getCombatResult(matchId: string) {
    const raw = await this.redis.client.get(`match:${matchId}:combat-result`);
    return raw ? JSON.parse(raw) : null;
  }
}

class CountingMatches {
  readonly perMatch = new Map<string, number>();
  async appendRoundEvents(matchId: string) {
    this.perMatch.set(matchId, (this.perMatch.get(matchId) ?? 0) + 1);
  }
}

function makeMatch(
  player1Id: string = randomUUID(),
  player2Id: string = randomUUID(),
): Match {
  return {
    id: randomUUID(),
    player1Id,
    player2Id,
    matchSeed: randomUUID(),
    p1State: {
      hp: 100,
      gold: 5,
      ready: false,
      board: [{ instanceId: randomUUID(), unitId: 'fighter', star: 0, hp: 100, maxHp: 100 }, ...Array(8).fill(null)],
      bench: Array(8).fill(null),
    },
    p2State: {
      hp: 100,
      gold: 5,
      ready: false,
      board: Array(9).fill(null),
      bench: Array(8).fill(null),
    },
    wipeIndexP1: 0,
    wipeIndexP2: 0,
    winnerId: null,
    status: 'in_progress',
    createdAt: new Date(),
    finishedAt: null,
  };
}

function add(results: Result[], name: string, passed: boolean, detail: string) {
  results.push({ name, passed, detail });
}

async function run() {
  const databaseUrl = process.env.DATABASE_URL ??
    'postgres://postgres:postgres@postgres-primary:5432/auto_chess';
  const ds = new DataSource({
    type: 'postgres',
    url: databaseUrl,
    entities: ENTITIES,
    synchronize: false,
    logging: ['error'],
  });
  const redis = new RedisService();
  await Promise.all([ds.initialize(), redis.onModuleInit()]);

  const results: Result[] = [];
  const redisKeys = new Set<string>();
  const createdUserIds: string[] = [];
  const persistedMatchIds: string[] = [];

  try {
    // 100 rounds × 3 coordinator instances sharing one Redis.
    const countingMatches = new CountingMatches();
    const stressQueue = new CaptureQueue();
    const stressPubsub = new RedisPubsub(redis);
    const coordinators = Array.from({ length: 3 }, () => new CombatCoordinator(
      redis,
      stressPubsub as any,
      countingMatches as any,
      stressQueue as any,
      runBattle,
    ));
    const stressMatches = Array.from({ length: 100 }, () => makeMatch());
    for (const match of stressMatches) {
      const key = runtimeKey(match.id);
      redisKeys.add(key);
      redisKeys.add(`match:${match.id}:combat-result`);
      redisKeys.add(`match:${match.id}:combat-done`);
      redisKeys.add(`combat-lock:${match.id}`);
      await redis.client.hset(key, { ...initialRuntimeHash(match), phase: 'battle' });
    }
    const starts = await Promise.all(stressMatches.flatMap((match) =>
      coordinators.map((coordinator) => coordinator.runCombat(match.id, 1)),
    ));
    const exactlyOnce = stressMatches.every(
      (match) => countingMatches.perMatch.get(match.id) === 1,
    );
    add(
      results,
      '100 rounds across 3 coordinators have exactly one combat runner',
      exactlyOnce && starts.filter(Boolean).length === 100 && stressQueue.timeouts.length === 100,
      `lockWinners=${starts.filter(Boolean).length} persisted=${countingMatches.perMatch.size} timeouts=${stressQueue.timeouts.length}`,
    );

    // One full round with real Postgres persistence and real Redis Lua scripts.
    const userRepo = ds.getRepository(User);
    const suffix = randomUUID().replaceAll('-', '').slice(0, 12);
    const users = await userRepo.save([
      userRepo.create({ email: `rounda-${suffix}@test.local`, username: `rounda${suffix}`, passwordHash: 'x'.repeat(60), rating: 1000 }),
      userRepo.create({ email: `roundb-${suffix}@test.local`, username: `roundb${suffix}`, passwordHash: 'x'.repeat(60), rating: 1000 }),
    ]);
    createdUserIds.push(...users.map((user) => user.id));
    const repository = new MatchRepository(ds.getRepository(Match), ds.getRepository(MatchRound));
    const pubsub = new RedisPubsub(redis);
    const userService = new UserService(userRepo);
    const matchService = new MatchService(ds, repository, pubsub as any, userService);
    const queue = new CaptureQueue();
    const coordinator = new CombatCoordinator(
      redis,
      pubsub as any,
      matchService,
      queue as any,
      runBattle,
    );
    const shop = { rollOffersForMatch: async () => undefined };
    const adapter = new MatchRuntimeAdapter(
      redis,
      matchService,
      queue as any,
      pubsub as any,
      coordinator,
      shop as any,
    );
    const input = makeMatch(users[0].id, users[1].id);
    const persisted = await repository.create({
      player1Id: input.player1Id,
      player2Id: input.player2Id,
      matchSeed: input.matchSeed,
      p1State: input.p1State,
      p2State: input.p2State,
    });
    persistedMatchIds.push(persisted.id);
    redisKeys.add(runtimeKey(persisted.id));
    redisKeys.add(`match:${persisted.id}:combat-result`);
    redisKeys.add(`match:${persisted.id}:combat-done`);
    redisKeys.add(`combat-lock:${persisted.id}`);

    await adapter.initializeMatch(persisted);
    await Promise.all([
      adapter.markReady(persisted.player1Id, persisted.id, 1),
      adapter.markReady(persisted.player2Id, persisted.id, 1),
    ]);
    await adapter.handleCombatDone(persisted.player1Id, persisted.id, 1);
    await adapter.handleCombatDone(persisted.player2Id, persisted.id, 1);
    const [runtime, dbMatch, rounds] = await Promise.all([
      adapter.getRuntime(persisted.id),
      repository.findById(persisted.id),
      repository.findRounds(persisted.id),
    ]);
    add(
      results,
      'real Redis/Postgres flow persists events, damage and next round',
      runtime.phase === 'shop_place' && runtime.round === 2 &&
        runtime.p2State.hp === 95 && runtime.p2State.gold === 10 &&
        dbMatch?.p2State.hp === 95 && rounds.length === 1,
      `phase=${runtime.phase} round=${runtime.round} hp=${runtime.p2State.hp} gold=${runtime.p2State.gold} dbRounds=${rounds.length}`,
    );

    const forfeited = await adapter.handleDisconnect(
      persisted.id,
      persisted.player2Id,
    );
    const [ended, endedRuntime] = await Promise.all([
      repository.findById(persisted.id),
      adapter.getRuntime(persisted.id),
    ]);
    add(
      results,
      'disconnect finalizes only the specified active match',
      forfeited && ended?.status === 'forfeited' && ended.winnerId === persisted.player1Id &&
        endedRuntime.phase === 'finished',
      `forfeited=${forfeited} status=${ended?.status} runtime=${endedRuntime.phase} winner=${ended?.winnerId}`,
    );

    // Put a real delayed job on BullMQ; one of the three running Nest workers
    // must win the queue job and the combat lock, then persist exactly one row.
    const workerInput = makeMatch(users[0].id, users[1].id);
    const workerMatch = await repository.create({
      player1Id: workerInput.player1Id,
      player2Id: workerInput.player2Id,
      matchSeed: workerInput.matchSeed,
      p1State: workerInput.p1State,
      p2State: workerInput.p2State,
    });
    persistedMatchIds.push(workerMatch.id);
    redisKeys.add(runtimeKey(workerMatch.id));
    redisKeys.add(`match:${workerMatch.id}:combat-result`);
    redisKeys.add(`match:${workerMatch.id}:combat-done`);
    redisKeys.add(`combat-lock:${workerMatch.id}`);
    await adapter.initializeMatch(workerMatch);
    const phaseQueue = new Queue(QUEUE_NAMES.PHASE_TIMER, {
      connection: redis.bullClient,
    });
    await phaseQueue.add(
      JOB_NAMES.PHASE_START,
      { matchId: workerMatch.id, round: 1 },
      { delay: 100, jobId: `integration-phase-${workerMatch.id}` },
    );
    const deadline = Date.now() + 5000;
    let workerRuntime = await adapter.getRuntime(workerMatch.id);
    while (workerRuntime.combatRound !== 1 && Date.now() < deadline) {
      await new Promise((resolve) => setTimeout(resolve, 100));
      workerRuntime = await adapter.getRuntime(workerMatch.id);
    }
    const workerRounds = await repository.findRounds(workerMatch.id);
    await phaseQueue.close();
    add(
      results,
      'a real BullMQ phase job is consumed by one of 3 Nest workers',
      workerRuntime.phase === 'battle' && workerRuntime.combatRound === 1 && workerRounds.length === 1,
      `phase=${workerRuntime.phase} combatRound=${workerRuntime.combatRound} dbRounds=${workerRounds.length}`,
    );
  } finally {
    if (redisKeys.size) await redis.client.del(...redisKeys);
    for (const matchId of persistedMatchIds) {
      await ds.getRepository(MatchRound).delete({ matchId });
      await ds.getRepository(Match).delete({ id: matchId });
    }
    if (createdUserIds.length) await ds.getRepository(User).delete(createdUserIds);
    await Promise.allSettled([redis.onModuleDestroy(), ds.destroy()]);
  }

  console.log('\n[round orchestrator integration results]');
  for (const result of results) {
    console.log(`  ${result.passed ? 'PASS' : 'FAIL'}  ${result.name} — ${result.detail}`);
  }
  const passed = results.filter((result) => result.passed).length;
  console.log(`\n[summary] ${passed}/${results.length} passed`);
  if (passed !== results.length) process.exitCode = 1;
}

run().catch((error) => {
  console.error('[FAIL]', error);
  process.exitCode = 1;
});
