import { CanActivate, ExecutionContext, Injectable } from '@nestjs/common';
import { WsException } from '@nestjs/websockets';
import type { Socket } from 'socket.io';

/**
 * Per-user WS message rate limit — P1-BE-01 (#113).
 *
 * A client sending more than `WS_MSG_PER_SEC` (default 30) messages in a
 * rolling 1-second window gets `game:error { code: 'rate.limited' }` and
 * the message is dropped (the guard throws before the handler runs; the
 * throw is turned into `game:error` by `WsGameExceptionFilter`).
 *
 * State is a per-process in-memory map keyed by userId. That's enough:
 * a single user's socket is pinned to one instance for the life of the
 * connection (per-user dedup in the gateway), so their messages all land
 * on the same process. Entries are pruned lazily on the user's next
 * message and on disconnect via `forget()`.
 */
@Injectable()
export class WsThrottleGuard implements CanActivate {
  private readonly windowMs = 1000;
  private readonly limit = Number(process.env.WS_MSG_PER_SEC ?? 30);
  private readonly hits = new Map<string, number[]>();
  private lastSweep = 0;

  canActivate(context: ExecutionContext): boolean {
    if (context.getType() !== 'ws') return true;

    const client = context.switchToWs().getClient<Socket>();
    const userId =
      (client.data?.user?.sub as string | undefined) ?? client.id;

    const now = Date.now();
    this.sweep(now);

    const cutoff = now - this.windowMs;
    const recent = (this.hits.get(userId) ?? []).filter((t) => t > cutoff);
    recent.push(now);
    this.hits.set(userId, recent);

    if (recent.length > this.limit) {
      throw new WsException({ code: 'rate.limited', message: 'slow down' });
    }
    return true;
  }

  /** Drop a user's window explicitly (e.g. on disconnect). */
  forget(userId: string): void {
    this.hits.delete(userId);
  }

  /**
   * Every ~10s, drop users whose most recent message is older than the
   * window — covers clients that disconnect and never come back, so the
   * map can't grow without bound.
   */
  private sweep(now: number): void {
    if (now - this.lastSweep < 10_000) return;
    this.lastSweep = now;
    const cutoff = now - this.windowMs;
    for (const [userId, times] of this.hits) {
      if (times.length === 0 || times[times.length - 1] <= cutoff) {
        this.hits.delete(userId);
      }
    }
  }
}
