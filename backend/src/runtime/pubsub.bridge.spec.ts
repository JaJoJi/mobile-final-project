import { PubsubBridge } from './pubsub.bridge';

describe('PubsubBridge targeted delivery', () => {
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
