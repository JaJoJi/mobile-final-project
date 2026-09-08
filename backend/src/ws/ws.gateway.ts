import { Logger } from '@nestjs/common';
import {
  ConnectedSocket,
  MessageBody,
  OnGatewayConnection,
  OnGatewayDisconnect,
  OnGatewayInit,
  SubscribeMessage,
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
 * Responsibilities:
 *   - Accept the socket, verify the JWT via `WsAuthGuard`, and register
 *     the connection in a per-user index so we can dedup reconnects.
 *   - Per-user socket dedup: a single user opening a second connection
 *     (e.g. switching devices, or a flaky network that reconnected) will
 *     have their old socket disconnected cleanly.
 *   - Surface auth failures to the client as `game:error { code }` and
 *     immediately `disconnect()` — clients must not stay on the
 *     namespace without a valid token.
 *   - Per-socket match-subscription bookkeeping so `handleDisconnect`
 *     can unregister every `(matchId, socketId)` pair from
 *     `PubsubBridge.localSubscribers` — see {@link subscribeToMatch}.
 *
 * Multi-instance note: every Nest replica boots its own `WsGateway` and
 * its own `PubsubBridge` instance. The bridge subscribes to
 * `match:*:events` on the shared Redis bus, so a `pubsubBridge.publish`
 * on any replica reaches every other replica (P0-BE-05). Combined with
 * the per-user dedup here, a client can move between replicas mid-match
 * without missing events.
 *
 * Out of scope here, lands in later tickets:
 *   - `@SubscribeMessage` handlers → P0-BE-10 (game:matchmaking:join,
 *     game:shop:buy, game:match:place, …). When those handlers exist,
 *     they call `subscribeToMatch(client, matchId)` so the client starts
 *     receiving that match's events.
 */
@WebSocketGateway({
  namespace: '/game',
  cors: { origin: '*' },
  transports: ['websocket', 'polling'],
})
export class WsGateway implements OnGatewayConnection, OnGatewayDisconnect, OnGatewayInit {
  private readonly logger = new Logger(WsGateway.name);

  /** userId → set of currently-connected sockets (per-replica, in-memory). */
  private readonly connectedSockets = new Map<string, Set<Socket>>();

  /** socketId → set of matchIds the socket is subscribed to (inverse index). */
  private readonly socketMatches = new Map<string, Set<string>>();

  @WebSocketServer()
  server!: Server;

  constructor(
    private readonly pubsubBridge: PubsubBridge,
    private readonly wsAuthGuard: WsAuthGuard,
  ) {}

  /**
   * Fires after the socket.io `Server` is constructed and bound to the
   * `/game` namespace. Hand the server to `PubsubBridge` so its
   * `pmessage` handler can `io.of('/game').to(socketId).emit(...)`.
   */
  afterInit(server: Server): void {
    this.server = server;
    this.pubsubBridge.setServer(server);
    this.logger.log(`WsGateway ready on /game (instance=${process.env.HOSTNAME ?? 'local'})`);
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

    // Clean up per-user dedup bookkeeping.
    const bucket = this.connectedSockets.get(user.sub);
    if (bucket) {
      bucket.delete(client);
      if (bucket.size === 0) this.connectedSockets.delete(user.sub);
    }

    // Clean up per-match fan-out subscriptions so a closed socket can't
    // keep receiving events forever (race R14 — the 60 s cache covers
    // the gap between disconnect and reconnect, but a dead socket should
    // not stay in `localSubscribers` indefinitely).
    const matches = this.socketMatches.get(client.id);
    if (matches) {
      for (const matchId of matches) {
        this.pubsubBridge.unsubscribe(matchId, client.id);
      }
      this.socketMatches.delete(client.id);
    }

    this.logger.log(`WS disconnected: user=${user.sub} socket=${client.id}`);
  }

  /**
   * Register `client` to receive server→client events for `matchId`.
   * Called from P0-BE-10 message handlers (e.g. `game:matchmaking:join`
   * once a match is created) and from the P0-BE-05 smoke harness.
   *
   * Idempotent. The socket may be subscribed to many matches; this is
   * tracked in `socketMatches` so `handleDisconnect` can clean up.
   */
  subscribeToMatch(client: Socket, matchId: string): void {
    const userId = (client.data.user as SocketUser | undefined)?.sub;
    this.pubsubBridge.subscribe(matchId, client.id, userId);
    let set = this.socketMatches.get(client.id);
    if (!set) {
      set = new Set<string>();
      this.socketMatches.set(client.id, set);
    }
    set.add(matchId);
    this.logger.log(`subscribed: socket=${client.id} match=${matchId}`);
  }

  /**
   * Stop delivering `matchId` events to `client`. Idempotent; safe to
   * call when the socket was never subscribed.
   */
  unsubscribeFromMatch(client: Socket, matchId: string): void {
    this.pubsubBridge.unsubscribe(matchId, client.id);
    this.socketMatches.get(client.id)?.delete(matchId);
  }

  /**
   * TEST-ONLY — `debug:subscribe-match` lets the P0-BE-05 smoke harness
   * register a socket for a match without a real `game:matchmaking:join`
   * handler (those land in P0-BE-10). Removed in P0-BE-10 when the real
   * `@SubscribeMessage` handlers replace this entry point.
   *
   * Body: `{ matchId: string }` — empty/missing matchId is silently dropped.
   */
  @SubscribeMessage('debug:subscribe-match')
  debugSubscribeMatch(
    @MessageBody() body: { matchId?: string },
    @ConnectedSocket() client: Socket,
  ): { ok: true } | { ok: false; reason: string } {
    const matchId = body?.matchId;
    if (!matchId || typeof matchId !== 'string') {
      return { ok: false, reason: 'matchId required' };
    }
    this.subscribeToMatch(client, matchId);
    return { ok: true };
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
