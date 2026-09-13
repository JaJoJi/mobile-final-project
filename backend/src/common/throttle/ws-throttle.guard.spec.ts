import { ExecutionContext } from '@nestjs/common';
import { WsException } from '@nestjs/websockets';
import { WsThrottleGuard } from './ws-throttle.guard';

class FakeRedis {
  now = 0;
  readonly calls: Array<{ script: string; keys: string[]; args: (string | number)[] }> = [];
  private readonly hits = new Map<string, number[]>();

  async eval<T>(script: string, keys: string[], args: (string | number)[]): Promise<T> {
    this.calls.push({ script, keys, args });
    const windowMs = Number(args[0]);
    const recent = (this.hits.get(keys[0]) ?? []).filter(
      (timestamp) => timestamp > this.now - windowMs,
    );
    recent.push(this.now);
    this.hits.set(keys[0], recent);
    return recent.length as T;
  }

  advance(ms: number): void {
    this.now += ms;
  }
}

function wsContext(userId: string): ExecutionContext {
  const client = { id: `sock-${userId}`, data: { user: { sub: userId } } };
  return {
    getType: () => 'ws',
    switchToWs: () => ({ getClient: () => client }),
  } as unknown as ExecutionContext;
}

function httpContext(): ExecutionContext {
  return { getType: () => 'http' } as unknown as ExecutionContext;
}

describe('WsThrottleGuard (P1-BE-01)', () => {
  const oldEnv = process.env.WS_MSG_PER_SEC;

  afterEach(() => {
    if (oldEnv === undefined) delete process.env.WS_MSG_PER_SEC;
    else process.env.WS_MSG_PER_SEC = oldEnv;
  });

  it('ignores non-ws contexts without touching Redis', async () => {
    const redis = new FakeRedis();
    const guard = new WsThrottleGuard(redis as any);

    await expect(guard.canActivate(httpContext())).resolves.toBe(true);
    expect(redis.calls).toHaveLength(0);
  });

  it('allows up to the limit within 1s, then throws rate.limited', async () => {
    process.env.WS_MSG_PER_SEC = '5';
    const redis = new FakeRedis();
    const guard = new WsThrottleGuard(redis as any);
    const ctx = wsContext('user-1');

    for (let i = 0; i < 5; i++) {
      await expect(guard.canActivate(ctx)).resolves.toBe(true);
    }

    await expect(guard.canActivate(ctx)).rejects.toBeInstanceOf(WsException);
    try {
      await guard.canActivate(ctx);
    } catch (error) {
      expect((error as WsException).getError()).toEqual({
        code: 'rate.limited',
        message: 'slow down',
      });
    }
  });

  it('is per-user and shared by separate Nest guard instances', async () => {
    process.env.WS_MSG_PER_SEC = '2';
    const redis = new FakeRedis();
    const replicaA = new WsThrottleGuard(redis as any);
    const replicaB = new WsThrottleGuard(redis as any);
    const a = wsContext('user-a');
    const b = wsContext('user-b');

    await replicaA.canActivate(a);
    await replicaB.canActivate(a);
    await expect(replicaA.canActivate(a)).rejects.toBeInstanceOf(WsException);

    await expect(replicaB.canActivate(b)).resolves.toBe(true);
    expect(redis.calls[0]).toEqual({
      script: 'ws_rate_limit',
      keys: ['rate:ws:{user-a}:hits', 'rate:ws:{user-a}:seq'],
      args: [1000],
    });
  });

  it('lets the window slide after messages become older than 1s', async () => {
    process.env.WS_MSG_PER_SEC = '3';
    const redis = new FakeRedis();
    const guard = new WsThrottleGuard(redis as any);
    const ctx = wsContext('user-1');

    await guard.canActivate(ctx);
    await guard.canActivate(ctx);
    await guard.canActivate(ctx);
    await expect(guard.canActivate(ctx)).rejects.toBeInstanceOf(WsException);

    redis.advance(1100);
    await expect(guard.canActivate(ctx)).resolves.toBe(true);
  });

  it('falls back to 30 when WS_MSG_PER_SEC is invalid', async () => {
    process.env.WS_MSG_PER_SEC = 'not-a-number';
    const redis = new FakeRedis();
    const guard = new WsThrottleGuard(redis as any);
    const ctx = wsContext('user-1');

    for (let i = 0; i < 30; i++) await guard.canActivate(ctx);
    await expect(guard.canActivate(ctx)).rejects.toBeInstanceOf(WsException);
  });
});
