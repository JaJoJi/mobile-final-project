/**
 * Dependency-light smoke test for P0-BE-11.
 *
 * It exercises MatchmakingService with in-memory fakes, so it does not need
 * Docker, Postgres or Redis. The existing Redis Lua smoke separately proves
 * that `match_pair.lua` is atomic against a real Redis instance.
 *
 * Run after building:
 *   node dist/matchmaking/matchmaking.smoke.js
 */
import { randomUUID } from 'crypto';
import { Match } from '../match/match.entity';
import { JOB_NAMES } from '../queue/queue.constants';
import { QueueService } from '../queue/queue.service';
import { MatchmakingService, MATCHMAKING_QUEUE_KEY, MatchmakingError } from './matchmaking.service';

interface TestResult {
  name: string;
  passed: boolean;
  detail: string;
}

class FakeRedisClient {
  readonly queue = new Map<string, number>();

  async zadd(_key: string, ...args: Array<string | number>): Promise<number> {
    const nx = args[0] === 'NX';
    const pairs = nx ? args.slice(1) : args;
    let added = 0;
    for (let index = 0; index < pairs.length; index += 2) {
      const score = Number(pairs[index]);
      const member = String(pairs[index + 1]);
      if (nx && this.queue.has(member)) continue;
      if (!this.queue.has(member)) added++;
      this.queue.set(member, score);
    }
    return added;
  }

  async zrem(_key: string, ...members: string[]): Promise<number> {
    let removed = 0;
    for (const member of members) {
      if (this.queue.delete(member)) removed++;
    }
    return removed;
  }

  orderedMembers(): string[] {
    return [...this.queue.entries()]
      .sort((a, b) => a[1] - b[1] || a[0].localeCompare(b[0]))
      .map(([member]) => member);
  }
}

class FakeRedisService {
  readonly client = new FakeRedisClient();

  async eval<T>(scriptName: string, keys: string[], _args: Array<string | number>): Promise<T> {
    if (scriptName !== 'match_pair' || keys[0] !== MATCHMAKING_QUEUE_KEY) {
      throw new Error(`unexpected eval ${scriptName}`);
    }
    const members = this.client.orderedMembers().slice(0, 2);
    if (members.length === 2) await this.client.zrem(keys[0], ...members);
    return (members.length === 2 ? members : []) as T;
  }
}

class FakeMatchRepository {
  readonly active = new Map<string, Match>();
  readonly created: Match[] = [];
  failNextCreate = false;

  async findActiveByUserId(userId: string): Promise<Match | null> {
    return this.active.get(userId) ?? null;
  }

  async create(input: {
    player1Id: string;
    player2Id: string;
    matchSeed: string;
    p1State: Record<string, unknown>;
    p2State: Record<string, unknown>;
  }): Promise<Match> {
    if (this.failNextCreate) {
      this.failNextCreate = false;
      throw new Error('simulated database outage');
    }
    const match = {
      id: randomUUID(),
      ...input,
      winnerId: null,
      status: 'in_progress',
      wipeIndexP1: 0,
      wipeIndexP2: 0,
      createdAt: new Date(),
      finishedAt: null,
    } as Match;
    this.created.push(match);
    this.active.set(match.player1Id, match);
    this.active.set(match.player2Id, match);
    return match;
  }
}

class FakePubsubBridge {
  readonly events: Array<{ matchId: string; type: string; payload: any }> = [];

  async publish(matchId: string, type: string, payload: unknown): Promise<void> {
    this.events.push({ matchId, type, payload });
  }
}

class FakeRuntimeAdapter {
  constructor(private readonly pubsub: FakePubsubBridge) {}

  async initializeMatch(match: Match): Promise<void> {
    await this.pubsub.publish(match.id, 'game:match:phase', {
      matchId: match.id,
      phase: 'shop_place',
      round: 1,
      timer: 40,
      players: [
        { id: match.player1Id, hp: 100, gold: 5, ready: false },
        { id: match.player2Id, hp: 100, gold: 5, ready: false },
      ],
    });
  }
}

class FakeRepeatQueue {
  readonly jobs: Array<{ name: string; every: string }> = [];
  addCalls = 0;
  lastOptions: { removeOnComplete?: boolean; removeOnFail?: number } | null = null;

  async getRepeatableJobs(): Promise<Array<{ name: string; every: string }>> {
    return [...this.jobs];
  }

  async add(
    name: string,
    _data: unknown,
    options: { repeat: { every: number }; removeOnComplete?: boolean; removeOnFail?: number },
  ): Promise<void> {
    this.addCalls++;
    this.lastOptions = options;
    this.jobs.push({ name, every: String(options.repeat.every) });
  }
}

function record(results: TestResult[], name: string, passed: boolean, detail: string): void {
  results.push({ name, passed, detail });
}

async function run(): Promise<void> {
  const redis = new FakeRedisService();
  const matches = new FakeMatchRepository();
  const pubsub = new FakePubsubBridge();
  const runtime = new FakeRuntimeAdapter(pubsub);
  const service = new MatchmakingService(redis as any, matches as any, runtime as any);
  const results: TestResult[] = [];

  const activeUser = randomUUID();
  const existing = { id: randomUUID() } as Match;
  matches.active.set(activeUser, existing);
  let activeError: unknown;
  try {
    await service.joinQueue(activeUser, 1);
  } catch (error: unknown) {
    activeError = error;
  }
  record(
    results,
    'active player is rejected before queueing',
    activeError instanceof MatchmakingError && redis.client.queue.size === 0,
    `code=${(activeError as MatchmakingError | undefined)?.code ?? 'none'}`,
  );

  const a = randomUUID();
  const b = randomUUID();
  const c = randomUUID();
  const firstJoin = await service.joinQueue(a, 100);
  const duplicateJoin = await service.joinQueue(a, 999);
  await service.joinQueue(b, 200);
  await service.joinQueue(c, 300);
  record(
    results,
    'join is idempotent and preserves FIFO timestamp',
    firstJoin.queued && !duplicateJoin.queued && redis.client.queue.get(a) === 100,
    `score=${redis.client.queue.get(a)} order=${redis.client.orderedMembers().join(',')}`,
  );

  const left = await service.leaveQueue(c);
  const leftAgain = await service.leaveQueue(c);
  await service.joinQueue(c, 300);
  record(
    results,
    'leave removes only a waiting player',
    left && !leftAgain && redis.client.queue.has(c),
    `first=${left} retry=${leftAgain}`,
  );

  const pair = await service.tryPair();
  const created = matches.created[0];
  const phase = pubsub.events[0];
  record(
    results,
    'oldest two players create one initialized match',
    pair?.player1Id === a &&
      pair?.player2Id === b &&
      created?.p1State.hp === 100 &&
      created?.p1State.gold === 5 &&
      Array.isArray(created?.p1State.board) &&
      created.p1State.board.length === 9 &&
      Array.isArray(created?.p1State.bench) &&
      created.p1State.bench.length === 8,
    `pair=${pair?.player1Id},${pair?.player2Id} remaining=${redis.client.orderedMembers().join(',')}`,
  );
  record(
    results,
    'match start publishes the API-contract phase payload',
    phase?.type === 'game:match:phase' &&
      phase.payload.matchId === pair?.matchId &&
      phase.payload.phase === 'shop_place' &&
      phase.payload.round === 1 &&
      phase.payload.timer === 40 &&
      phase.payload.players.length === 2,
    JSON.stringify(phase?.payload),
  );

  const noSecondPair = await service.tryPair();
  record(
    results,
    'third player stays queued when no opponent exists',
    noSecondPair === null && redis.client.orderedMembers()[0] === c,
    `result=${String(noSecondPair)} remaining=${redis.client.orderedMembers().join(',')}`,
  );

  redis.client.queue.clear();
  const d = randomUUID();
  const e = randomUUID();
  const f = randomUUID();
  await service.joinQueue(d, 1);
  await service.joinQueue(e, 2);
  await service.joinQueue(f, 3);
  const createdBeforeRace = matches.created.length;
  const race = await Promise.all([service.tryPair(), service.tryPair()]);
  record(
    results,
    'concurrent pollers cannot double-pair a queue entry',
    race.filter(Boolean).length === 1 &&
      matches.created.length === createdBeforeRace + 1 &&
      redis.client.orderedMembers().length === 1,
    `pairs=${race.filter(Boolean).length} remaining=${redis.client.orderedMembers().length}`,
  );

  redis.client.queue.clear();
  const g = randomUUID();
  const h = randomUUID();
  await service.joinQueue(g, 1);
  await service.joinQueue(h, 2);
  matches.failNextCreate = true;
  let createFailed = false;
  try {
    await service.tryPair();
  } catch {
    createFailed = true;
  }
  record(
    results,
    'database failure puts both players back in queue',
    createFailed && redis.client.queue.has(g) && redis.client.queue.has(h),
    `failed=${createFailed} remaining=${redis.client.orderedMembers().length}`,
  );

  const repeatQueue = new FakeRepeatQueue();
  const queueService = new QueueService(
    {} as any,
    {} as any,
    {} as any,
    repeatQueue as any,
    {} as any,
  );
  await queueService.ensureMatchPairRepeating(1000);
  await queueService.ensureMatchPairRepeating(1000);
  record(
    results,
    'scheduler registration remains a single one-second repeatable job',
    repeatQueue.addCalls === 1 &&
      repeatQueue.jobs[0]?.name === JOB_NAMES.MATCH_PAIR &&
      repeatQueue.jobs[0]?.every === '1000' &&
      repeatQueue.lastOptions?.removeOnComplete === true &&
      repeatQueue.lastOptions?.removeOnFail === 100,
    `addCalls=${repeatQueue.addCalls} every=${repeatQueue.jobs[0]?.every} ` +
      `removeOnComplete=${repeatQueue.lastOptions?.removeOnComplete}`,
  );

  console.log('\n[matchmaking smoke results]');
  let passed = 0;
  for (const result of results) {
    const tag = result.passed ? 'PASS' : 'FAIL';
    if (result.passed) passed++;
    console.log(`  ${tag}  ${result.name} — ${result.detail}`);
  }
  console.log(`\n[summary] ${passed}/${results.length} passed`);
  if (passed !== results.length) process.exitCode = 1;
}

run().catch((error: unknown) => {
  console.error('[FAIL]', error);
  process.exitCode = 1;
});
