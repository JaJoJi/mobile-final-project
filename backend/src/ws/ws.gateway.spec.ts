import { BadRequestException } from '@nestjs/common';

jest.mock('../match/match.service', () => ({ MatchService: class MatchService {} }));
jest.mock('../matchmaking/matchmaking.service', () => ({
  MatchmakingService: class MatchmakingService {},
}));
jest.mock('../runtime/match.runtime.adapter', () => ({
  MatchRuntimeAdapter: class MatchRuntimeAdapter {},
}));
jest.mock('../runtime/pubsub.bridge', () => ({ PubsubBridge: class PubsubBridge {} }));

import { WsGateway } from './ws.gateway';
import { toGameError } from './ws-exception.filter';

function harness() {
  const pubsub = {
    setServer: jest.fn(),
    registerUserSocket: jest.fn(),
    unregisterUserSocket: jest.fn(),
    subscribe: jest.fn(),
    unsubscribe: jest.fn(),
  };
  const auth = { authenticate: jest.fn(() => 'user-1') };
  const matchmaking = {
    joinQueue: jest.fn(async () => ({ queued: true })),
    leaveQueue: jest.fn(async () => true),
  };
  const runtime = {
    handleAction: jest.fn(async () => ({ duplicate: false })),
    handleDisconnect: jest.fn(async () => true),
  };
  const matches = { findActiveByUserId: jest.fn(async () => null) };
  const gateway = new WsGateway(
    pubsub as any,
    auth as any,
    matchmaking as any,
    runtime as any,
    matches as any,
  );
  const socket = {
    id: 'socket-1',
    connected: true,
    data: { user: { sub: 'user-1', type: 'access' } },
    emit: jest.fn(),
    disconnect: jest.fn(),
  };
  return { gateway, pubsub, matchmaking, runtime, matches, socket };
}

describe('WsGateway P0-BE-10 handlers', () => {
  it('routes matchmaking join and leave with the authenticated user id', async () => {
    const h = harness();
    await h.gateway.onMatchmakingJoin({}, h.socket as any);
    await h.gateway.onMatchmakingLeave({}, h.socket as any);
    expect(h.matchmaking.joinQueue).toHaveBeenCalledWith('user-1');
    expect(h.matchmaking.leaveQueue).toHaveBeenCalledWith('user-1');
  });

  it.each([
    ['onShopBuy', 'shop:buy', { round: 1, offerIndex: 0, clientActionId: 'action-1' }],
    ['onShopSell', 'shop:sell', { round: 1, source: 'bench', slot: 0, clientActionId: 'action-2' }],
    ['onShopRefresh', 'shop:refresh', { round: 1, clientActionId: 'action-3' }],
    ['onShopFuse', 'shop:fuse', { round: 1, unitId: 'fighter', clientActionId: 'action-4' }],
    ['onMatchPlace', 'match:place', { round: 1, unitInstanceId: 'unit-1', target: 'board', slot: 0, clientActionId: 'action-5' }],
    ['onMatchReady', 'match:ready', { round: 1, clientActionId: 'action-6' }],
    ['onMatchCombatDone', 'match:combat_done', { matchId: 'match-1', round: 1, clientActionId: 'action-7' }],
  ])('routes %s to runtime action %s', async (method, action, dto) => {
    const h = harness();
    await (h.gateway as any)[method](dto, h.socket);
    expect(h.runtime.handleAction).toHaveBeenCalledWith('user-1', action, dto);
  });

  it('emits domain errors with the matching clientActionId', async () => {
    const h = harness();
    h.runtime.handleAction.mockRejectedValueOnce(new BadRequestException({
      code: 'place.slot_occupied',
      message: 'occupied',
    }));
    await h.gateway.onMatchPlace({
      round: 1,
      unitInstanceId: 'unit-1',
      target: 'board',
      slot: 0,
      clientActionId: 'action-5',
    }, h.socket as any);
    expect(h.socket.emit).toHaveBeenCalledWith('game:error', {
      code: 'place.slot_occupied',
      message: 'occupied',
      clientActionId: 'action-5',
    });
  });

  it('masks unexpected service errors', async () => {
    const h = harness();
    h.matchmaking.joinQueue.mockRejectedValueOnce(new Error('database connection detail'));
    await h.gateway.onMatchmakingJoin({}, h.socket as any);
    expect(h.socket.emit).toHaveBeenCalledWith('game:error', {
      code: 'internal',
      message: 'unexpected error',
    });
  });

  it('registers sockets and notifies runtime on a real disconnect', async () => {
    const h = harness();
    h.gateway.handleConnection(h.socket as any);
    h.gateway.handleDisconnect(h.socket as any);
    await new Promise((resolve) => setImmediate(resolve));
    expect(h.pubsub.registerUserSocket).toHaveBeenCalledWith('user-1', 'socket-1');
    expect(h.pubsub.unregisterUserSocket).toHaveBeenCalledWith('user-1', 'socket-1');
    expect(h.matchmaking.leaveQueue).toHaveBeenCalledWith('user-1');
    expect(h.runtime.handleDisconnect).toHaveBeenCalledWith('user-1');
  });

  it('does not forfeit when an older duplicate socket is intentionally replaced', async () => {
    const h = harness();
    (h.socket.data as any).superseded = true;
    h.gateway.handleDisconnect(h.socket as any);
    await new Promise((resolve) => setImmediate(resolve));
    expect(h.runtime.handleDisconnect).not.toHaveBeenCalled();
  });
});

describe('WS error envelope', () => {
  it('maps validation exceptions and masks unexpected errors', () => {
    expect(toGameError(
      new BadRequestException({ code: 'invalid_payload', message: 'round must be an integer' }),
      'internal',
      'action-1',
    )).toEqual({
      code: 'invalid_payload',
      message: 'round must be an integer',
      clientActionId: 'action-1',
    });
    expect(toGameError(new Error('database password leaked'), 'internal')).toEqual({
      code: 'internal',
      message: 'unexpected error',
    });
  });
});
