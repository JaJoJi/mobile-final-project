import RedisMock from 'ioredis-mock';

jest.mock('../queue/queue.service', () => ({ QueueService: class QueueService {} }));
jest.mock('../match/match.service', () => ({ MatchService: class MatchService {} }));
jest.mock('../shop/shop.service', () => ({ ShopService: class ShopService {} }));
jest.mock('./combat.coordinator', () => ({ CombatCoordinator: class CombatCoordinator {} }));
jest.mock('./pubsub.bridge', () => ({ PubsubBridge: class PubsubBridge {} }));

import { LUA_SCRIPTS } from '../redis/scripts';
import { MatchRuntimeAdapter } from './match.runtime.adapter';
import { initialRuntimeHash, runtimeKey } from './match.runtime-state';

const match = {
  id: 'match-1',
  player1Id: 'player-1',
  player2Id: 'player-2',
  matchSeed: 'seed-1',
  p1State: {
    hp: 100,
    gold: 5,
    ready: false,
    board: Array(9).fill(null),
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
};

const BATTLE_WIN_P1 = [{ type: 'battle_end', cycle: 3, winner: 'p1' }];

async function harness() {
  const client = new RedisMock();
  const redis = {
    client,
    eval: (name: string, keys: string[], args: Array<string | number>) =>
      client.eval(LUA_SCRIPTS[name], keys.length, ...keys, ...args.map(String)),
  };
  const matches = {
    usernamesForPlayers: jest.fn(async () => ({
      player1Name: 'player1',
      player2Name: 'player2',
    })),
    findActiveByUserId: jest.fn(async (userId: string) =>
      userId === match.player1Id || userId === match.player2Id ? match : null),
    updateState: jest.fn(async () => undefined),
    updateRuntimeSnapshot: jest.fn(async () => undefined),
    finalize: jest.fn(async () => true),
    forfeitDisconnectedPlayer: jest.fn(async () => true),
  };
  const queue = { schedulePhaseStart: jest.fn() };
  const pubsub = {
    publish: jest.fn(),
    publishToUser: jest.fn(),
    getCombatResult: jest.fn(async () => null),
  };
  const combat = { runCombat: jest.fn(async () => true) };
  const shop = {
    buy: jest.fn(),
    sell: jest.fn(),
    refresh: jest.fn(),
    fuse: jest.fn(),
    rollOffersForMatch: jest.fn(async () => undefined),
  };
  const adapter = new MatchRuntimeAdapter(
    redis as any,
    matches as any,
    queue as any,
    pubsub as any,
    combat as any,
    shop as any,
  );
  await client.hset(runtimeKey(match.id), initialRuntimeHash(match as any));
  return { adapter, client, matches, queue, pubsub, combat, shop };
}

async function seedBattle(
  h: Awaited<ReturnType<typeof harness>>,
  opts: { round?: number; combatRound?: number | null; p1Hp?: number; p2Hp?: number },
) {
  const runtime = await h.adapter.getRuntime(match.id);
  runtime.phase = 'battle';
  runtime.round = opts.round ?? 1;
  runtime.combatRound = opts.combatRound ?? opts.round ?? 1;
  runtime.p1State.hp = opts.p1Hp ?? 100;
  runtime.p2State.hp = opts.p2Hp ?? 100;
  await h.client.hset(runtimeKey(match.id), {
    phase: 'battle',
    round: String(runtime.round),
    combatRound: runtime.combatRound === null ? '' : String(runtime.combatRound),
    p1State: JSON.stringify(runtime.p1State),
    p2State: JSON.stringify(runtime.p2State),
  });
}

describe('MatchRuntimeAdapter.initializeMatch (#307)', () => {
  it('seeds runtime, schedules the phase timer, and publishes phase + state + shops', async () => {
    const h = await harness();
    await h.client.del(runtimeKey(match.id));
    await h.adapter.initializeMatch(match as any);

    const runtime = await h.adapter.getRuntime(match.id);
    expect(runtime.phase).toBe('shop_place');
    expect(runtime.round).toBe(1);
    expect(h.queue.schedulePhaseStart).toHaveBeenCalledWith(match.id, 1, 40000);
    expect(h.pubsub.publish).toHaveBeenCalledWith(
      match.id,
      'game:match:phase',
      expect.objectContaining({ matchId: match.id, phase: 'shop_place', round: 1 }),
    );
    // One authoritative snapshot per player.
    expect(h.pubsub.publishToUser).toHaveBeenCalledTimes(2);
    expect(h.shop.rollOffersForMatch).toHaveBeenCalledTimes(1);
  });
});

describe('MatchRuntimeAdapter.handleAction dispatch (#307)', () => {
  it('throws match.not_found when the caller has no active match', async () => {
    const h = await harness();
    await expect(
      h.adapter.handleAction('ghost', 'shop:buy', {
        round: 1,
        offerIndex: 0,
        clientActionId: 'a1',
      }),
    ).rejects.toMatchObject({ response: { code: 'match.not_found' } });
  });

  it('routes combat_done by explicit matchId and returns the ack count', async () => {
    const h = await harness();
    await seedBattle(h, {});
    const res = await h.adapter.handleAction('player-1', 'match:combat_done', {
      matchId: match.id,
      round: 1,
      clientActionId: 'done-1',
    });
    expect(res).toEqual({ ackCount: 1 });
  });

  it('throws match.runtime_not_found for unknown matches', async () => {
    const h = await harness();
    await expect(h.adapter.getRuntime('missing')).rejects.toMatchObject({
      response: { code: 'match.runtime_not_found' },
    });
  });
});

describe('MatchRuntimeAdapter legacy markReady + tryStartCombat (#307)', () => {
  it('counts ready players and starts combat once both are ready', async () => {
    const h = await harness();
    await expect(h.adapter.markReady('player-1', match.id, 1)).resolves.toBe(1);
    await expect(h.adapter.markReady('player-2', match.id, 1)).resolves.toBe(2);
    expect((await h.adapter.getRuntime(match.id)).phase).toBe('battle');
    expect(h.combat.runCombat).toHaveBeenCalledTimes(1);
    expect(h.combat.runCombat).toHaveBeenCalledWith(match.id, 1);
  });

  it('tryStartCombat ignores missing runtimes and stale phase/round', async () => {
    const h = await harness();
    await expect(h.adapter.tryStartCombat('missing', 1)).resolves.toBe(false);
    await h.client.hset(runtimeKey(match.id), 'round', '2');
    await expect(h.adapter.tryStartCombat(match.id, 1)).resolves.toBe(false);
    expect(h.combat.runCombat).not.toHaveBeenCalled();
  });

  it('tryStartCombat loses cleanly when another worker wins the CAS', async () => {
    const h = await harness();
    // The Lua CAS itself is covered in lua.spec.ts; here we pin the loser
    // outcome to verify no publish/combat follows a lost flip.
    const evalSpy = jest.spyOn((h.adapter as any).redis, 'eval');
    evalSpy.mockResolvedValueOnce(0);
    await expect(h.adapter.tryStartCombat(match.id, 1)).resolves.toBe(false);
    expect(h.combat.runCombat).not.toHaveBeenCalled();
    evalSpy.mockRestore();
  });
});

describe('MatchRuntimeAdapter.handleCombatDone (#307)', () => {
  it('first ack returns 1 without advancing; duplicate ack stays at 1', async () => {
    const h = await harness();
    await seedBattle(h, {});
    await expect(h.adapter.handleCombatDone('player-1', match.id, 1)).resolves.toBe(1);
    await expect(h.adapter.handleCombatDone('player-1', match.id, 1)).resolves.toBe(1);
    expect((await h.adapter.getRuntime(match.id)).phase).toBe('battle');
  });

  it('second distinct ack advances the round', async () => {
    const h = await harness();
    await seedBattle(h, {});
    (h.pubsub.getCombatResult as jest.Mock).mockResolvedValue(BATTLE_WIN_P1);
    await h.adapter.handleCombatDone('player-1', match.id, 1);
    await expect(h.adapter.handleCombatDone('player-2', match.id, 1)).resolves.toBe(2);
    expect((await h.adapter.getRuntime(match.id)).phase).toBe('shop_place');
    expect((await h.adapter.getRuntime(match.id)).round).toBe(2);
  });

  it('rejects acks outside battle and from non-participants', async () => {
    const h = await harness();
    await expect(
      h.adapter.handleCombatDone('player-1', match.id, 1),
    ).rejects.toMatchObject({ response: { code: 'match.not_your_turn' } });
    await seedBattle(h, {});
    await expect(
      h.adapter.handleCombatDone('intruder', match.id, 1),
    ).rejects.toMatchObject({ response: { code: 'match.not_your_match' } });
  });
});

describe('MatchRuntimeAdapter.applyDamageAndAdvance (#307)', () => {
  it('applies wipe damage, awards gold, and advances exactly once', async () => {
    const h = await harness();
    await seedBattle(h, {});
    (h.pubsub.getCombatResult as jest.Mock).mockResolvedValue(BATTLE_WIN_P1);

    await expect(h.adapter.applyDamageAndAdvance(match.id, 1)).resolves.toBe(true);
    const runtime = await h.adapter.getRuntime(match.id);
    expect(runtime.phase).toBe('shop_place');
    expect(runtime.round).toBe(2);
    expect(runtime.p1State.hp).toBe(100);
    expect(runtime.p2State.hp).toBe(95);
    expect(runtime.p1State.gold).toBe(10);
    expect(runtime.wipeIndexP2).toBe(1);
    expect(runtime.combatRound).toBeNull();
    expect(h.matches.updateRuntimeSnapshot).toHaveBeenCalledTimes(1);
    expect(h.queue.schedulePhaseStart).toHaveBeenCalledWith(match.id, 2, 40000);
    expect(h.shop.rollOffersForMatch).toHaveBeenCalledTimes(1);
    // Second call is a no-op: the round already advanced.
    await expect(h.adapter.applyDamageAndAdvance(match.id, 1)).resolves.toBe(false);
  });

  it('escalates and caps wipe damage at 25', async () => {
    const h = await harness();
    await seedBattle(h, {});
    await h.client.hset(runtimeKey(match.id), 'wipeIndexP2', '4');
    (h.pubsub.getCombatResult as jest.Mock).mockResolvedValue(BATTLE_WIN_P1);
    await h.adapter.applyDamageAndAdvance(match.id, 1);
    const runtime = await h.adapter.getRuntime(match.id);
    expect(runtime.p2State.hp).toBe(75);
    expect(runtime.wipeIndexP2).toBe(5);
    // Cap holds on the next wipe too.
    await h.client.hset(runtimeKey(match.id), {
      phase: 'battle',
      combatRound: '2',
      p1State: JSON.stringify({ ...runtime.p1State, hp: 100 }),
      p2State: JSON.stringify({ ...runtime.p2State, hp: 100 }),
    });
    (h.pubsub.getCombatResult as jest.Mock).mockResolvedValue([
      { type: 'battle_end', cycle: 2, winner: 'p1' },
    ]);
    await h.adapter.applyDamageAndAdvance(match.id, 2);
    expect((await h.adapter.getRuntime(match.id)).p2State.hp).toBe(75);
    expect((await h.adapter.getRuntime(match.id)).wipeIndexP2).toBe(5);
  });

  it('applies tie damage to both sides without advancing wipe counters', async () => {
    const h = await harness();
    await seedBattle(h, {});
    (h.pubsub.getCombatResult as jest.Mock).mockResolvedValue([
      { type: 'battle_end', cycle: 30, winner: null },
    ]);
    await h.adapter.applyDamageAndAdvance(match.id, 1);
    const runtime = await h.adapter.getRuntime(match.id);
    expect(runtime.p1State.hp).toBe(95);
    expect(runtime.p2State.hp).toBe(95);
    expect(runtime.wipeIndexP1).toBe(0);
    expect(runtime.wipeIndexP2).toBe(0);
  });

  it('finalizes lethally damaged matches exactly once', async () => {
    const h = await harness();
    await seedBattle(h, { p2Hp: 5 });
    (h.pubsub.getCombatResult as jest.Mock).mockResolvedValue(BATTLE_WIN_P1);
    await expect(h.adapter.applyDamageAndAdvance(match.id, 1)).resolves.toBe(true);
    expect((await h.adapter.getRuntime(match.id)).phase).toBe('finished');
    expect(h.matches.finalize).toHaveBeenCalledWith(match.id, 'player-1', 'hp_zero');
    // Late duplicate (e.g. retried timeout) cannot finalize again.
    await expect(h.adapter.applyDamageAndAdvance(match.id, 1)).resolves.toBe(false);
    expect(h.matches.finalize).toHaveBeenCalledTimes(1);
  });

  it('treats double-zero HP as a draw with null winner', async () => {
    const h = await harness();
    await seedBattle(h, { p1Hp: 5, p2Hp: 5 });
    (h.pubsub.getCombatResult as jest.Mock).mockResolvedValue([
      { type: 'battle_end', cycle: 30, winner: null },
    ]);
    await h.adapter.applyDamageAndAdvance(match.id, 1);
    expect(h.matches.finalize).toHaveBeenCalledWith(match.id, null, 'hp_zero');
  });

  it('returns false for stale rounds, missing cache, and corrupt events', async () => {
    const h = await harness();
    await seedBattle(h, { round: 2 });
    // Stale round number.
    await expect(h.adapter.applyDamageAndAdvance(match.id, 1)).resolves.toBe(false);
    // Missing combat-result cache.
    (h.pubsub.getCombatResult as jest.Mock).mockResolvedValue(null);
    await expect(h.adapter.applyDamageAndAdvance(match.id, 2)).resolves.toBe(false);
    // CombatRound from another round (e.g. previous battle never cleared).
    await h.client.hset(runtimeKey(match.id), 'combatRound', '1');
    (h.pubsub.getCombatResult as jest.Mock).mockResolvedValue(BATTLE_WIN_P1);
    await expect(h.adapter.applyDamageAndAdvance(match.id, 2)).resolves.toBe(false);
    // Events without a valid battle_end are a bug, surfaced loudly.
    await h.client.hset(runtimeKey(match.id), 'combatRound', '2');
    (h.pubsub.getCombatResult as jest.Mock).mockResolvedValue([{ type: 'attack' }]);
    await expect(h.adapter.applyDamageAndAdvance(match.id, 2)).rejects.toThrow(
      'combat.internal',
    );
    expect(h.matches.finalize).not.toHaveBeenCalled();
  });

  it('concurrent second-ack and timeout advance exactly once', async () => {
    const h = await harness();
    await seedBattle(h, {});
    (h.pubsub.getCombatResult as jest.Mock).mockResolvedValue(BATTLE_WIN_P1);
    const results = await Promise.allSettled([
      h.adapter.applyDamageAndAdvance(match.id, 1),
      h.adapter.applyDamageAndAdvance(match.id, 1),
    ]);
    const wins = results.filter((r) => r.status === 'fulfilled' && r.value === true);
    expect(wins).toHaveLength(1);
    expect(h.matches.updateRuntimeSnapshot).toHaveBeenCalledTimes(1);
    expect((await h.adapter.getRuntime(match.id)).round).toBe(2);
  });
});

describe('MatchRuntimeAdapter.handleDisconnect (#307)', () => {
  it('forfeits mid-battle disconnects and ignores the second call', async () => {
    const h = await harness();
    await seedBattle(h, {});
    await expect(h.adapter.handleDisconnect('player-2')).resolves.toBe(true);
    expect(h.matches.forfeitDisconnectedPlayer).toHaveBeenCalledWith(
      match.id,
      'player-2',
    );
    expect((await h.adapter.getRuntime(match.id)).phase).toBe('finished');
    // Already finished: no duplicate finalization.
    await expect(h.adapter.handleDisconnect('player-2')).resolves.toBe(false);
    expect(h.matches.forfeitDisconnectedPlayer).toHaveBeenCalledTimes(1);
  });

  it('returns false with no active match and forfeits directly without runtime', async () => {
    const h = await harness();
    h.matches.findActiveByUserId.mockResolvedValueOnce(null);
    await expect(h.adapter.handleDisconnect('ghost')).resolves.toBe(false);
    await h.client.del(runtimeKey(match.id));
    await expect(h.adapter.handleDisconnect(match.id, 'player-1')).resolves.toBe(true);
    expect(h.matches.forfeitDisconnectedPlayer).toHaveBeenCalledWith(
      match.id,
      'player-1',
    );
  });

  it('ignores disconnects with no active match, rejects non-participants', async () => {
    const h = await harness();
    h.matches.findActiveByUserId.mockResolvedValueOnce(null);
    await expect(h.adapter.handleDisconnect('ghost')).resolves.toBe(false);
    h.matches.findActiveByUserId.mockResolvedValueOnce(match as any);
    await expect(h.adapter.handleDisconnect('intruder')).rejects.toMatchObject({
      response: { code: 'match.not_your_match' },
    });
  });
});

describe('MatchRuntimeAdapter reconnect/resume (#307)', () => {
  it('returns null combat replay outside battle or without cache', async () => {
    const h = await harness();
    await expect(h.adapter.getCombatResultForReconnect(match.id)).resolves.toBeNull();
    await seedBattle(h, {});
    await expect(h.adapter.getCombatResultForReconnect(match.id)).resolves.toBeNull();
  });

  it('replays cached combat events to a battle-phase reconnect', async () => {
    const h = await harness();
    await seedBattle(h, {});
    (h.pubsub.getCombatResult as jest.Mock).mockResolvedValue(BATTLE_WIN_P1);
    await expect(
      h.adapter.getCombatResultForReconnect(match.id),
    ).resolves.toEqual({ round: 1, events: BATTLE_WIN_P1 });
  });

  it('rejects resume payloads for non-participants', async () => {
    const h = await harness();
    await expect(
      h.adapter.statePayloadForUser(match.id, 'intruder'),
    ).rejects.toMatchObject({ response: { code: 'match.not_your_match' } });
  });
});

describe('MatchRuntimeAdapter action lock contention (#307)', () => {
  it('fails with match.action_busy when another owner holds the lock', async () => {
    const h = await harness();
    await h.client.set(
      `match:${match.id}:shop-lock:player-1`,
      'foreign-owner',
      'PX',
      60000,
    );
    await expect(
      h.adapter.handleAction('player-1', 'match:place', {
        round: 1,
        unitInstanceId: 'unit-1',
        target: 'board',
        slot: 0,
        clientActionId: 'place-busy',
      }),
    ).rejects.toMatchObject({ response: { code: 'match.action_busy' } });
  }, 10000);
});
