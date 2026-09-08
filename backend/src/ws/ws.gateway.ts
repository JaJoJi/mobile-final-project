import { Logger } from '@nestjs/common';
import {
  OnGatewayConnection,
  OnGatewayDisconnect,
  WebSocketGateway,
  WebSocketServer,
  WsException,
} from '@nestjs/websockets';
import type { Server, Socket } from 'socket.io';
import { PubsubBridge } from '../runtime/pubsub.bridge';
import { WsAuthGuard } from './guards/ws-auth.guard';

interface SocketUser {
  sub: string;
  type: 'access' | 'refresh';
}

/**
 * Real-time WS gateway for the `/game` namespace.
 *
 * This is the SKELETON only (P0-BE-04). Responsibilities that land here:
 *   - Accept the socket, verify the JWT via `WsAuthGuard`, and register
 *     the connection in a per-user index so we can fan out later.
 *   - Per-user socket dedup: a single user opening a second connection
 *     (e.g. switching devices, or a flaky network that reconnected) will
 *     have their old socket disconnected cleanly.
 *   - Surface auth failures to the client as `game:error { code }` and
 *     immediately `disconnect()` — clients must not stay on the
 *     namespace without a valid token.
 *
 * Out of scope here, lands in later tickets:
 *   - `@SubscribeMessage` handlers → P0-BE-10 (game:matchmaking:join,
 *     game:shop:buy, game:match:place, …).
 *   - Cross-instance fan-out via Redis Pub/Sub → P0-BE-05
 *     (replaces the no-op `PubsubBridge` stub).
 *
 * Multi-instance note: every Nest replica boots its own `WsGateway`
 * and registers its OWN copy of a user's socket. The dedup map is
 * intentionally local to a single instance — when P0-BE-05 lands, it
 * will subscribe to a per-user key on the Redis bus so a reconnect
 * arriving at a different replica can still kick the old socket off.
 */
@WebSocketGateway({
  namespace: '/game',
  cors: { origin: '*' },
  transports: ['websocket', 'polling'],
})
export class WsGateway implements OnGatewayConnection, OnGatewayDisconnect {
  private readonly logger = new Logger(WsGateway.name);

  /** userId → set of currently-connected sockets (per-replica, in-memory). */
  private readonly connectedSockets = new Map<string, Set<Socket>>();

  @WebSocketServer()
  server!: Server;

  constructor(
    private readonly pubsubBridge: PubsubBridge,
    private readonly wsAuthGuard: WsAuthGuard,
  ) {
    // Touch pubsubBridge so the constructor's stub-warning is logged on
    // boot even before any WS connection happens — makes it obvious in
    // every replica's log that we're on the stub.
    void this.pubsubBridge;
  }

  handleConnection(client: Socket): void {
    const userId = this.authenticateOrDisconnect(client);
    if (!userId) return;

    this.dedupePreviousSockets(userId, client);

    let bucket = this.connectedSockets.get(userId);
    if (!bucket) {
      bucket = new Set<Socket>();
      this.connectedSockets.set(userId, bucket);
    }
    bucket.add(client);

    this.logger.log(
      `WS connected: user=${userId} socket=${client.id} ` +
        `(instance=${process.env.HOSTNAME ?? 'local'})`,
    );
  }

  handleDisconnect(client: Socket): void {
    const user = client.data.user as SocketUser | undefined;
    if (!user?.sub) return;

    const bucket = this.connectedSockets.get(user.sub);
    if (bucket) {
      bucket.delete(client);
      if (bucket.size === 0) this.connectedSockets.delete(user.sub);
    }
    this.logger.log(`WS disconnected: user=${user.sub} socket=${client.id}`);
  }

  /**
   * Run the auth guard inline. Socket.IO does not call `@UseGuards` for
   * `handleConnection`, so we call `WsAuthGuard.authenticate()` directly.
   * Any `WsException` → emit `game:error { code }` and disconnect.
   *
   * Returns the verified userId, or `null` if the connection was rejected.
   */
  private authenticateOrDisconnect(client: Socket): string | null {
    try {
      return this.wsAuthGuard.authenticate(client);
    } catch (e: unknown) {
      const code = e instanceof WsException ? String(e.getError()) : 'auth.invalid';
      this.logger.warn(`WS auth rejected: socket=${client.id} code=${code}`);
      client.emit('game:error', { code });
      client.disconnect(true);
      return null;
    }
  }

  /**
   * If this user already has sockets on this replica, kick them all so
   * the new one is the only live one. The closing sockets will go
   * through `handleDisconnect` and clean themselves out of the index.
   */
  private dedupePreviousSockets(userId: string, current: Socket): void {
    const existing = this.connectedSockets.get(userId);
    if (!existing || existing.size === 0) return;
    for (const old of existing) {
      if (old.id === current.id) continue;
      this.logger.log(`dedup: kicking old socket=${old.id} for user=${userId}`);
      old.disconnect(true);
    }
  }
}
