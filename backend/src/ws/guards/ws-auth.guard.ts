import { CanActivate, ExecutionContext, Injectable, Logger } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { WsException } from '@nestjs/websockets';
import type { Socket } from 'socket.io';

export interface JwtPayload {
  sub: string;
  type: 'access' | 'refresh';
}

/**
 * WS JWT guard. Reads the access token from `socket.handshake.auth.token`
 * (the convention socket.io clients use to pass per-connection auth without
 * leaking it into query strings / logs), verifies the signature with the
 * shared `JWT_SECRET`, and attaches the decoded payload to `socket.data.user`
 * so downstream handlers (P0-BE-10) can read `client.data.user.sub`.
 *
 * Throws `WsException` with a stable error code:
 *   - `auth.invalid` — no token, wrong type, or malformed payload
 *   - `auth.expired` — signature / `exp` check failed
 *
 * `WsException` is caught by the gateway's `handleConnection`, which
 * forwards the code as `game:error { code }` and disconnects the socket.
 *
 * Mirrors `JwtAccessGuard` (REST) so the two stay in lockstep — any
 * change to the JWT shape (new claim, algorithm swap) must touch both.
 *
 * Note on CanActivate vs direct call: `@UseGuards` does not fire on
 * `handleConnection` (it's a Nest lifecycle hook, not a message route).
 * The gateway calls `authenticate()` directly, which is the same code
 * path `canActivate` runs. `canActivate` is kept so future
 * `@SubscribeMessage` handlers (P0-BE-10) can `@UseGuards(WsAuthGuard)`
 * on individual events without duplicating logic.
 */
@Injectable()
export class WsAuthGuard implements CanActivate {
  private readonly logger = new Logger(WsAuthGuard.name);

  constructor(private readonly jwt: JwtService) {}

  /**
   * Direct verification entry point — used by `WsGateway.handleConnection`.
   * Returns the verified userId, or throws a `WsException` with a stable
   * error code on any failure. On success, `client.data.user` is populated.
   */
  authenticate(client: Socket): string {
    const token = client.handshake.auth?.token as string | undefined;

    if (!token || typeof token !== 'string') {
      throw new WsException('auth.invalid');
    }

    let payload: JwtPayload;
    try {
      payload = this.jwt.verify<JwtPayload>(token);
    } catch (e: unknown) {
      const msg = e instanceof Error ? e.message : 'unknown';
      this.logger.warn(`WS auth verify failed: ${msg}`);
      throw new WsException('auth.expired');
    }

    if (payload.type !== 'access' || !payload.sub) {
      throw new WsException('auth.invalid');
    }

    client.data.user = payload;
    return payload.sub;
  }

  canActivate(context: ExecutionContext): boolean {
    const client = context.switchToWs().getClient<Socket>();
    this.authenticate(client);
    return true;
  }
}
