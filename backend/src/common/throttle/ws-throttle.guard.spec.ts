import { ExecutionContext } from '@nestjs/common';
import { WsException } from '@nestjs/websockets';
import { WsThrottleGuard } from './ws-throttle.guard';

function wsContext(userId: string): ExecutionContext {
  const client = { id: 'sock-' + userId, data: { user: { sub: userId } } };
  return {
    getType: () => 'ws',
    switchToWs: () => ({ getClient: () => client }),
  } as unknown as ExecutionContext;
}

function httpContext(): ExecutionContext {
  return { getType: () => 'http' } as unknown as ExecutionContext;
}

describe('WsThrottleGuard (P1-BE-01)', () => {
  const OLD_ENV = process.env.WS_MSG_PER_SEC;
  afterEach(() => {
    if (OLD_ENV === undefined) delete process.env.WS_MSG_PER_SEC;
    else process.env.WS_MSG_PER_SEC = OLD_ENV;
    jest.useRealTimers();
  });

  it('ignores non-ws contexts', () => {
    const guard = new WsThrottleGuard();
    expect(guard.canActivate(httpContext())).toBe(true);
  });

  it('allows up to the limit within a 1s window, then throws rate.limited', () => {
    process.env.WS_MSG_PER_SEC = '5';
    const guard = new WsThrottleGuard();
    const ctx = wsContext('user-1');

    for (let i = 0; i < 5; i++) {
      expect(guard.canActivate(ctx)).toBe(true);
    }

    try {
      guard.canActivate(ctx);
      throw new Error('expected the 6th message to be throttled');
    } catch (e) {
      expect(e).toBeInstanceOf(WsException);
      expect((e as WsException).getError()).toEqual({
        code: 'rate.limited',
        message: 'slow down',
      });
    }
  });

  it('is per-user — one noisy client does not throttle another', () => {
    process.env.WS_MSG_PER_SEC = '2';
    const guard = new WsThrottleGuard();
    const a = wsContext('user-a');
    const b = wsContext('user-b');

    guard.canActivate(a);
    guard.canActivate(a);
    expect(() => guard.canActivate(a)).toThrow(WsException);

    // user-b still has a clean window.
    expect(guard.canActivate(b)).toBe(true);
    expect(guard.canActivate(b)).toBe(true);
  });

  it('lets the window slide — messages older than 1s no longer count', () => {
    jest.useFakeTimers();
    process.env.WS_MSG_PER_SEC = '3';
    const guard = new WsThrottleGuard();
    const ctx = wsContext('user-1');

    guard.canActivate(ctx);
    guard.canActivate(ctx);
    guard.canActivate(ctx);
    expect(() => guard.canActivate(ctx)).toThrow(WsException);

    jest.advanceTimersByTime(1100);
    expect(guard.canActivate(ctx)).toBe(true);
  });
});
