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
    forfeitDisconnectedPlayer: jest.fn(async () => true),
  };
  const queue = { schedulePhaseStart: jest.fn() };
  const pubsub = { publish: jest.fn(), publishToUser: jest.fn(), getCombatResult: jest.fn() };
  const combat = { runCombat: jest.fn(async () => undefined) };
  const shop = {
    buy: jest.fn(async () => ({ duplicate: false })),
    sell: jest.fn(async () => ({ duplicate: false })),
    refresh: jest.fn(async () => ({ duplicate: false })),
    fuse: jest.fn(async () => ({ duplicate: false })),
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

describe('MatchRuntimeAdapter WS action seam', () => {
  it('returns no scout data in round one', async () => {
    const h = await harness();
    const resumed = await h.adapter.statePayloadForUser(match.id, match.player1Id);

    expect(resumed.opponent.scoutRound).toBeNull();
    expect(resumed.opponent.boardSummary).toEqual(Array(9).fill(null));
    expect(resumed.opponent.battleBoardSummary).toBeNull();
    expect(resumed.roster.username).toBe('player1');
    expect(resumed.opponent.username).toBe('player2');
    expect(h.matches.usernamesForPlayers).toHaveBeenCalledWith(
      match.player1Id,
      match.player2Id,
    );
    await expect(
      h.client.hmget(runtimeKey(match.id), 'player1Name', 'player2Name'),
    ).resolves.toEqual(['player1', 'player2']);
  });

  it('keeps the completed-round scout snapshot stable and exposes live units only in battle',
    async () => {
      const h = await harness();
      const completedBoard = [
        { unitId: 'healer', star: 0 },
        ...Array(8).fill(null),
      ];
      const current = await h.adapter.getRuntime(match.id);
      current.p2State.board[0] = {
        instanceId: 'current-ranger',
        unitId: 'ranger',
        star: 1,
        hp: 60,
        maxHp: 60,
      };
      await h.client.hset(runtimeKey(match.id), {
        round: '2',
        p2State: JSON.stringify(current.p2State),
        scoutRound: '1',
        scoutP2Board: JSON.stringify(completedBoard),
      });

      const planning = await h.adapter.statePayloadForUser(match.id, match.player1Id);
      expect(planning.opponent.scoutRound).toBe(1);
      expect(planning.opponent.boardSummary[0]).toEqual({
        unitId: 'healer',
        star: 0,
      });
      expect(planning.opponent.battleBoardSummary).toBeNull();

      await h.client.hset(runtimeKey(match.id), 'phase', 'battle');
      const battle = await h.adapter.statePayloadForUser(match.id, match.player1Id);
      expect(battle.opponent.boardSummary).toEqual(
        planning.opponent.boardSummary,
      );
      expect(battle.opponent.battleBoardSummary?.[0]).toEqual({
        unitId: 'ranger',
        star: 1,
      });
    });

  it('resolves the active match and routes shop actions', async () => {
    const h = await harness();
    await h.adapter.handleAction('player-1', 'shop:buy', {
      round: 1,
      offerIndex: 2,
      clientActionId: 'action-1',
    });
    expect(h.shop.buy).toHaveBeenCalledWith(
      'player-1',
      'match-1',
      1,
      2,
      'action-1',
    );
  });

  it('moves an owned unit, publishes state, persists it, and dedupes retries', async () => {
    const h = await harness();
    const runtime = await h.adapter.getRuntime(match.id);
    runtime.p1State.bench[0] = {
      instanceId: 'unit-1',
      unitId: 'fighter',
      star: 0,
      hp: 100,
      maxHp: 100,
    };
    await h.client.hset(runtimeKey(match.id), 'p1State', JSON.stringify(runtime.p1State));
    const payload = {
      round: 1,
      unitInstanceId: 'unit-1',
      target: 'board' as const,
      slot: 4,
      clientActionId: 'place-1',
    };

    expect(await h.adapter.handleAction('player-1', 'match:place', payload))
      .toEqual({ duplicate: false });
    expect(await h.adapter.handleAction('player-1', 'match:place', payload))
      .toEqual({ duplicate: true });
    const moved = await h.adapter.getRuntime(match.id);
    expect(moved.p1State.bench[0]).toBeNull();
    expect(moved.p1State.board[4]?.instanceId).toBe('unit-1');
    expect(h.matches.updateState).toHaveBeenCalledTimes(1);
    expect(h.pubsub.publishToUser).toHaveBeenCalledTimes(2);
  });

  it('rejects bench slot 8 and a unit the caller does not own', async () => {
    const h = await harness();
    await expect(h.adapter.handleAction('player-1', 'match:place', {
      round: 1,
      unitInstanceId: 'missing',
      target: 'bench',
      slot: 8,
      clientActionId: 'place-bad-slot',
    })).rejects.toMatchObject({
      response: { code: 'place.slot_out_of_range' },
    });
    await expect(h.adapter.handleAction('player-1', 'match:place', {
      round: 1,
      unitInstanceId: 'missing',
      target: 'board',
      slot: 0,
      clientActionId: 'place-not-owned',
    })).rejects.toMatchObject({
      response: { code: 'place.unit_not_owned' },
    });
  });

  it('dedupes ready actions and starts combat after two distinct players ready', async () => {
    const h = await harness();
    const p1 = { round: 1, clientActionId: 'ready-1' };
    expect(await h.adapter.handleAction('player-1', 'match:ready', p1))
      .toEqual({ duplicate: false, readyCount: 1 });
    expect(await h.adapter.handleAction('player-1', 'match:ready', p1))
      .toEqual({ duplicate: true, readyCount: 1 });
    expect(await h.adapter.handleAction('player-2', 'match:ready', {
      round: 1,
      clientActionId: 'ready-2',
    })).toEqual({ duplicate: false, readyCount: 2 });
    expect((await h.adapter.getRuntime(match.id)).phase).toBe('battle');
    expect(h.combat.runCombat).toHaveBeenCalledWith(match.id, 1);
  });

  it('lets a player cancel ready before the second player starts combat', async () => {
    const h = await harness();
    expect(await h.adapter.handleAction('player-1', 'match:ready', {
      round: 1,
      ready: true,
      clientActionId: 'ready-on',
    })).toEqual({ duplicate: false, readyCount: 1 });
    expect(await h.adapter.handleAction('player-1', 'match:ready', {
      round: 1,
      ready: false,
      clientActionId: 'ready-off',
    })).toEqual({ duplicate: false, readyCount: 0 });
    expect((await h.adapter.getRuntime(match.id)).readyP1).toBe(false);
    expect(h.combat.runCombat).not.toHaveBeenCalled();
  });

  it('resolves the active match for a one-argument disconnect', async () => {
    const h = await harness();
    expect(await h.adapter.handleDisconnect('player-1')).toBe(true);
    expect(h.matches.forfeitDisconnectedPlayer).toHaveBeenCalledWith('match-1', 'player-1');
  });
});
