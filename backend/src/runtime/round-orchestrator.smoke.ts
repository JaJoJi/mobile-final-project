import 'reflect-metadata';
import { randomUUID } from 'crypto';
import type { Match } from '../match/match.entity';
import { MatchRuntimeAdapter } from './match.runtime.adapter';
import { runtimeKey } from './match.runtime-state';

interface Result { name: string; passed: boolean; detail: string }

class FakeRedis {
  readonly hashes = new Map<string, Record<string, string>>();

  readonly client = {
    hset: async (key: string, fieldOrMap: string | Record<string, string>, value?: string) => {
      const hash = this.hashes.get(key) ?? {};
      if (typeof fieldOrMap === 'string') hash[fieldOrMap] = String(value);
      else Object.assign(hash, fieldOrMap);
      this.hashes.set(key, hash);
      return 1;
    },
    hgetall: async (key: string) => ({ ...(this.hashes.get(key) ?? {}) }),
    expire: async () => 1,
  };

  async eval<T>(name: string, keys: string[], args: Array<string | number>): Promise<T> {
    const hash = this.hashes.get(keys[0]) ?? {};
    if (name === 'phase_flip') {
      const [expected, next, instanceId, expectedRound] = args.map(String);
      if (hash.phase !== expected || (expectedRound && hash.round !== expectedRound)) return 0 as T;
      hash.phase = next;
      if (next === 'battle') hash.combatLockInstance = instanceId;
      this.hashes.set(keys[0], hash);
      return 1 as T;
    }
    if (name === 'combat_done') {
      if (!hash[String(args[0])]) hash[String(args[0])] = String(args[1]);
      this.hashes.set(keys[0], hash);
      return Object.keys(hash).length as T;
    }
    throw new Error(`unknown fake script ${name}`);
  }
}

class FakeQueue {
  readonly phases: Array<{ matchId: string; round: number; delay: number }> = [];
  readonly timeouts: Array<{ matchId: string; round: number; delay: number }> = [];
  async schedulePhaseStart(matchId: string, round: number, delay: number) {
    this.phases.push({ matchId, round, delay });
  }
  async scheduleCombatDoneTimeout(matchId: string, round: number, delay: number) {
    this.timeouts.push({ matchId, round, delay });
  }
}

class FakePubsub {
  readonly events: Array<{ matchId: string; type: string; payload: any }> = [];
  readonly combat = new Map<string, any[]>();
  async publish(matchId: string, type: string, payload: unknown) {
    this.events.push({ matchId, type, payload });
  }
  async getCombatResult(matchId: string) {
    return this.combat.get(matchId) ?? null;
  }
}

class FakeMatches {
  readonly snapshots: any[] = [];
  readonly finalized: any[] = [];
  async updateRuntimeSnapshot(matchId: string, input: unknown) {
    this.snapshots.push({ matchId, input });
  }
  async finalize(matchId: string, winnerId: string | null, reason: string) {
    this.finalized.push({ matchId, winnerId, reason });
    return true;
  }
  async forfeitDisconnectedPlayer(matchId: string, userId: string) {
    this.finalized.push({ matchId, userId, reason: 'disconnect' });
    return true;
  }
}

class FakeCombat {
  calls = 0;
  constructor(
    private readonly redis: FakeRedis,
    private readonly pubsub: FakePubsub,
    private readonly winner: 'p1' | 'p2' | null = 'p1',
  ) {}
  async runCombat(matchId: string, round: number) {
    this.calls++;
    await this.redis.client.hset(runtimeKey(matchId), 'combatRound', String(round));
    this.pubsub.combat.set(matchId, [
      { type: 'cycle_end', cycle: 1 },
      { type: 'battle_end', cycle: 1, winner: this.winner },
    ]);
    return true;
  }
}

function match(p2Hp = 100): Match {
  return {
    id: randomUUID(),
    player1Id: randomUUID(),
    player2Id: randomUUID(),
    matchSeed: randomUUID(),
    p1State: { hp: 100, gold: 5, ready: false, board: Array(9).fill(null), bench: Array(8).fill(null) },
    p2State: { hp: p2Hp, gold: 5, ready: false, board: Array(9).fill(null), bench: Array(8).fill(null) },
    wipeIndexP1: 0,
    wipeIndexP2: 0,
    winnerId: null,
    status: 'in_progress',
    createdAt: new Date(),
    finishedAt: null,
  };
}

function makeHarness(winner: 'p1' | 'p2' | null = 'p1') {
  const redis = new FakeRedis();
  const queue = new FakeQueue();
  const pubsub = new FakePubsub();
  const matches = new FakeMatches();
  const combat = new FakeCombat(redis, pubsub, winner);
  const runtime = new MatchRuntimeAdapter(
    redis as any,
    matches as any,
    queue as any,
    pubsub as any,
    combat as any,
  );
  return { redis, queue, pubsub, matches, combat, runtime };
}

function add(results: Result[], name: string, passed: boolean, detail: string) {
  results.push({ name, passed, detail });
}

async function run() {
  const results: Result[] = [];
  const h = makeHarness('p1');
  const game = match();
  await h.runtime.initializeMatch(game);
  const initial = await h.runtime.getRuntime(game.id);
  add(
    results,
    'match initialization persists shared runtime and schedules 40 s timer',
    initial.phase === 'shop_place' && initial.round === 1 && h.queue.phases[0]?.delay === 40_000,
    `phase=${initial.phase} round=${initial.round} delay=${h.queue.phases[0]?.delay}`,
  );

  await Promise.all([
    h.runtime.markReady(game.player1Id, game.id, 1),
    h.runtime.markReady(game.player2Id, game.id, 1),
  ]);
  const battle = await h.runtime.getRuntime(game.id);
  add(
    results,
    'both Ready flips to battle and invokes combat exactly once',
    battle.phase === 'battle' && h.combat.calls === 1,
    `phase=${battle.phase} combatCalls=${h.combat.calls}`,
  );

  const firstAck = await h.runtime.handleCombatDone(game.player1Id, game.id, 1);
  const duplicateAck = await h.runtime.handleCombatDone(game.player1Id, game.id, 1);
  const secondAck = await h.runtime.handleCombatDone(game.player2Id, game.id, 1);
  const round2 = await h.runtime.getRuntime(game.id);
  add(
    results,
    'acks are idempotent and the second player advances the round',
    firstAck === 1 && duplicateAck === 1 && secondAck === 2 && round2.round === 2,
    `acks=${firstAck},${duplicateAck},${secondAck} round=${round2.round}`,
  );
  add(
    results,
    'wipe damage, +5 gold and ready reset follow the game design',
    round2.p2State.hp === 95 && round2.p2State.gold === 10 &&
      round2.wipeIndexP2 === 1 && !round2.readyP1 && !round2.readyP2,
    `p2Hp=${round2.p2State.hp} gold=${round2.p2State.gold} wipe=${round2.wipeIndexP2}`,
  );
  add(
    results,
    'damage event is followed by the next shop phase and timer',
    h.pubsub.events.some((event) => event.type === 'game:match:damage') &&
      h.pubsub.events.at(-1)?.payload.phase === 'shop_place' && h.queue.phases.length === 2,
    `events=${h.pubsub.events.map((event) => event.type).join(',')} timers=${h.queue.phases.length}`,
  );

  const staleStarts = await Promise.all(
    Array.from({ length: 100 }, () => h.runtime.tryStartCombat(game.id, 1)),
  );
  add(
    results,
    '100 stale timers cannot flip a newer round',
    staleStarts.every((started) => !started) && h.combat.calls === 1,
    `started=${staleStarts.filter(Boolean).length} combatCalls=${h.combat.calls}`,
  );

  const tie = makeHarness(null);
  const tieGame = match();
  await tie.runtime.initializeMatch(tieGame);
  await tie.runtime.tryStartCombat(tieGame.id, 1);
  await tie.runtime.applyDamageAndAdvance(tieGame.id, 1);
  const tieRound2 = await tie.runtime.getRuntime(tieGame.id);
  add(
    results,
    'tie deals 5 to both players without advancing wipe counters',
    tieRound2.p1State.hp === 95 && tieRound2.p2State.hp === 95 &&
      tieRound2.wipeIndexP1 === 0 && tieRound2.wipeIndexP2 === 0,
    `hp=${tieRound2.p1State.hp}/${tieRound2.p2State.hp} wipes=${tieRound2.wipeIndexP1}/${tieRound2.wipeIndexP2}`,
  );

  const lethal = makeHarness('p1');
  const lethalGame = match(5);
  await lethal.runtime.initializeMatch(lethalGame);
  await lethal.runtime.tryStartCombat(lethalGame.id, 1);
  await lethal.runtime.applyDamageAndAdvance(lethalGame.id, 1);
  const ended = await lethal.runtime.getRuntime(lethalGame.id);
  add(
    results,
    'HP zero finalizes the match with the opposing player as winner',
    ended.phase === 'finished' && lethal.matches.finalized[0]?.winnerId === lethalGame.player1Id,
    `phase=${ended.phase} winner=${lethal.matches.finalized[0]?.winnerId}`,
  );

  const disconnected = makeHarness('p1');
  const disconnectedGame = match();
  await disconnected.runtime.initializeMatch(disconnectedGame);
  const disconnectResult = await disconnected.runtime.handleDisconnect(
    disconnectedGame.id,
    disconnectedGame.player2Id,
  );
  const disconnectedRuntime = await disconnected.runtime.getRuntime(disconnectedGame.id);
  const lateTimer = await disconnected.runtime.tryStartCombat(disconnectedGame.id, 1);
  add(
    results,
    'disconnect closes Redis runtime and prevents a late timer from starting combat',
    disconnectResult && disconnectedRuntime.phase === 'finished' && !lateTimer && disconnected.combat.calls === 0,
    `phase=${disconnectedRuntime.phase} lateTimer=${lateTimer} combatCalls=${disconnected.combat.calls}`,
  );

  console.log('\n[round orchestrator smoke results]');
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
