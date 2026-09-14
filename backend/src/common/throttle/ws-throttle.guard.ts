import { CanActivate, ExecutionContext, Injectable } from '@nestjs/common';
import { WsException } from '@nestjs/websockets';
import type { Socket } from 'socket.io';
import { RedisService } from '../../redis/redis.service';

/**
 * Per-user WS message rate limit — P1-BE-01 (#113).
 *
 * A client sending more than `WS_MSG_PER_SEC` (default 30) messages in a
 * rolling 1-second window gets `game:error { code: 'rate.limited' }` and
 * the message is dropped (the guard throws before the handler runs; the
 * throw is turned into `game:error` by `WsGameExceptionFilter`).
 *
 * The sliding window lives in Redis and is mutated by one Lua script, so the
 * limit remains per-user when sockets for that user reach different Nest
 * replicas. Redis TIME avoids host-clock skew and short TTLs clean up idle
 * users without process-local maps or disconnect bookkeeping.
 */
@Injectable()
export class WsThrottleGuard implements CanActivate {
  private readonly windowMs = 1000;
  private readonly limit = positiveInt(process.env.WS_MSG_PER_SEC, 30);

  constructor(private readonly redis: RedisService) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    if (context.getType() !== 'ws') return true;

    const client = context.switchToWs().getClient<Socket>();
    const userId =
      (client.data?.user?.sub as string | undefined) ?? client.id;

    // Hash tags keep both keys in one Redis Cluster slot if the deployment is
    // upgraded from the current single Redis instance later.
    const tag = `{${userId}}`;
    const recent = await this.redis.eval<number>(
      'ws_rate_limit',
      [`rate:ws:${tag}:hits`, `rate:ws:${tag}:seq`],
      [this.windowMs],
    );

    if (recent > this.limit) {
      throw new WsException({ code: 'rate.limited', message: 'slow down' });
    }
    return true;
  }
}

function positiveInt(raw: string | undefined, fallback: number): number {
  const parsed = Number(raw);
  return Number.isInteger(parsed) && parsed > 0 ? parsed : fallback;
}
