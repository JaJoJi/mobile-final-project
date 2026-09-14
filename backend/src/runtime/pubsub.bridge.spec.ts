import { PubsubBridge } from './pubsub.bridge';

describe('PubsubBridge targeted delivery', () => {
  it('auto-subscribes queued user sockets from the first match phase event', async () => {
    const deliveries: Array<{ socketId: string; type: string }> = [];
    const bridge = new PubsubBridge({} as any);
    bridge.setServer({
      to: (socketId: string) => ({
        emit: (type: string) => deliveries.push({ socketId, type }),
      }),
    } as any);
    bridge.registerUserSocket('player-a', 'socket-a');

    await (bridge as any).handleMessage(
      'match:new-match:events',
      JSON.stringify({
        type: 'game:match:phase',
        payload: { players: [{ id: 'player-a' }, { id: 'player-b' }] },
      }),
    );
    await (bridge as any).handleMessage(
      'match:new-match:events',
      JSON.stringify({
        type: 'game:shop:offer',
        payload: { offers: [] },
        targetUserId: 'player-a',
      }),
    );

    expect(deliveries).toEqual([
      { socketId: 'socket-a', type: 'game:match:phase' },
      { socketId: 'socket-a', type: 'game:shop:offer' },
    ]);
  });

  it('broadcasts public events but keeps private shop offers player-scoped', async () => {
    const deliveries: Array<{ socketId: string; type: string; payload: unknown }> = [];
    const server = {
      to: (socketId: string) => ({
        emit: (type: string, payload: unknown) => deliveries.push({ socketId, type, payload }),
      }),
    };
    const bridge = new PubsubBridge({} as any);
    bridge.setServer(server as any);
    bridge.subscribe('match-1', 'socket-a', 'player-a');
    bridge.subscribe('match-1', 'socket-b', 'player-b');

    await (bridge as any).handleMessage(
      'match:match-1:events',
      JSON.stringify({ type: 'game:match:phase', payload: { round: 1 } }),
    );
    expect(deliveries.map((entry) => entry.socketId)).toEqual(['socket-a', 'socket-b']);

    deliveries.length = 0;
    await (bridge as any).handleMessage(
      'match:match-1:events',
      JSON.stringify({
        type: 'game:shop:offer',
        payload: { offers: [] },
        targetUserId: 'player-b',
      }),
    );
    expect(deliveries).toEqual([
      { socketId: 'socket-b', type: 'game:shop:offer', payload: { offers: [] } },
    ]);
  });
});
