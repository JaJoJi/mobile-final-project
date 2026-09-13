import { UseFilters, UseGuards } from '@nestjs/common';
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
import { PinoLogger } from 'nestjs-pino';
import type { Server, Socket } from 'socket.io';
import { MatchService } from '../match/match.service';
import { MatchmakingService } from '../matchmaking/matchmaking.service';
import { MatchRuntimeAdapter, RuntimeActionType } from '../runtime/match.runtime.adapter';
import { PubsubBridge } from '../runtime/pubsub.bridge';
import { WsAuthGuard } from './guards/ws-auth.guard';
import {
  MatchCombatDoneDto,
  MatchPlaceDto,
  MatchReadyDto,
  MatchmakingJoinDto,
  MatchmakingLeaveDto,
  ShopBuyDto,
  ShopFuseDto,
  ShopRefreshDto,
  ShopSellDto,
} from './ws.dto';
import { toGameError, WsGameExceptionFilter } from './ws-exception.filter';
import { WsValidationPipe } from './ws.pipes';
import { WsThrottleGuard } from '../common/throttle/ws-throttle.guard';

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
 * P0-BE-10 wires every incoming `game:*` event below. The bridge observes the
 * first phase event from matchmaking and attaches both players' sockets to the
 * new match before fan-out, including when they are on different replicas.
 */
@WebSocketGateway({
  namespace: '/game',
  cors: { origin: '*' },
  transports: ['websocket', 'polling'],
})
@UseFilters(WsGameExceptionFilter)
// Per-user > WS_MSG_PER_SEC (default 30) msg/s -> game:error{code:'rate.limited'}
// on the message handlers (P1-BE-01 / #113). Not on handleConnection —
// socket.io doesn't run @UseGuards for the lifecycle hooks.
@UseGuards(WsThrottleGuard)
export class WsGateway implements OnGatewayConnection, OnGatewayDisconnect, OnGatewayInit {
  /** userId → set of currently-connected sockets (per-replica, in-memory). */
  private readonly connectedSockets = new Map<string, Set<Socket>>();

  /** socketId → set of matchIds the socket is subscribed to (inverse index). */
  private readonly socketMatches = new Map<string, Set<string>>();

  @WebSocketServer()
  server!: Server;

  constructor(
    private readonly pubsubBridge: PubsubBridge,
    private readonly wsAuthGuard: WsAuthGuard,
    private readonly matchmaking: MatchmakingService,
    private readonly runtime: MatchRuntimeAdapter,
    private readonly matches: MatchService,
    private readonly logger: PinoLogger,
  ) {
    this.logger.setContext(WsGateway.name);
  }

  /**
   * Fires after the socket.io `Server` is constructed and bound to the
   * `/game` namespace. Hand the server to `PubsubBridge` so its
   * `pmessage` handler can `io.of('/game').to(socketId).emit(...)`.
   */
  afterInit(server: Server): void {
    this.server = server;
    this.pubsubBridge.setServer(server);
    this.logger.info(
      { namespace: '/game' },
      'WS gateway ready',
    );
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
    this.pubsubBridge.registerUserSocket(userId, client.id);
    void this.resumeActiveMatch(client, userId);

    this.logger.info(
      { userId, socketId: client.id },
      'WS connected',
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
    this.pubsubBridge.unregisterUserSocket(user.sub, client.id);

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

    this.logger.info(
      { userId: user.sub, socketId: client.id },
      'WS disconnected',
    );
    if (client.data.superseded !== true) {
      void this.handleClientDisconnect(user.sub).catch((error: unknown) => {
        this.logger.error(
          { err: error, userId: user.sub, socketId: client.id },
          'WS disconnect handling failed',
        );
      });
    }
  }

  /**
   * Register `client` to receive server→client events for `matchId`.
   * Called when an existing match is resumed. New matches are subscribed by
   * PubsubBridge when their first phase event identifies both players.
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
    this.logger.debug(
      { userId, socketId: client.id, matchId },
      'WS subscribed to match',
    );
  }

  /**
   * Stop delivering `matchId` events to `client`. Idempotent; safe to
   * call when the socket was never subscribed.
   */
  unsubscribeFromMatch(client: Socket, matchId: string): void {
    this.pubsubBridge.unsubscribe(matchId, client.id);
    this.socketMatches.get(client.id)?.delete(matchId);
  }

  @SubscribeMessage('game:matchmaking:join')
  onMatchmakingJoin(
    @MessageBody(WsValidationPipe) _dto: MatchmakingJoinDto,
    @ConnectedSocket() client: Socket,
  ) {
    return this.runHandler(client, undefined, 'matchmaking.join_failed', () =>
      this.matchmaking.joinQueue(this.userId(client)));
  }

  @SubscribeMessage('game:matchmaking:leave')
  onMatchmakingLeave(
    @MessageBody(WsValidationPipe) _dto: MatchmakingLeaveDto,
    @ConnectedSocket() client: Socket,
  ) {
    return this.runHandler(client, undefined, 'matchmaking.leave_failed', () =>
      this.matchmaking.leaveQueue(this.userId(client)));
  }

  @SubscribeMessage('game:shop:buy')
  onShopBuy(@MessageBody(WsValidationPipe) dto: ShopBuyDto, @ConnectedSocket() client: Socket) {
    return this.runRuntimeAction(client, 'shop:buy', dto);
  }

  @SubscribeMessage('game:shop:sell')
  onShopSell(@MessageBody(WsValidationPipe) dto: ShopSellDto, @ConnectedSocket() client: Socket) {
    return this.runRuntimeAction(client, 'shop:sell', dto);
  }

  @SubscribeMessage('game:shop:refresh')
  onShopRefresh(@MessageBody(WsValidationPipe) dto: ShopRefreshDto, @ConnectedSocket() client: Socket) {
    return this.runRuntimeAction(client, 'shop:refresh', dto);
  }

  @SubscribeMessage('game:shop:fuse')
  onShopFuse(@MessageBody(WsValidationPipe) dto: ShopFuseDto, @ConnectedSocket() client: Socket) {
    return this.runRuntimeAction(client, 'shop:fuse', dto);
  }

  @SubscribeMessage('game:match:place')
  onMatchPlace(@MessageBody(WsValidationPipe) dto: MatchPlaceDto, @ConnectedSocket() client: Socket) {
    return this.runRuntimeAction(client, 'match:place', dto);
  }

  @SubscribeMessage('game:match:ready')
  onMatchReady(@MessageBody(WsValidationPipe) dto: MatchReadyDto, @ConnectedSocket() client: Socket) {
    return this.runRuntimeAction(client, 'match:ready', dto);
  }

  @SubscribeMessage('game:match:combat_done')
  onMatchCombatDone(
    @MessageBody(WsValidationPipe) dto: MatchCombatDoneDto,
    @ConnectedSocket() client: Socket,
  ) {
    return this.runRuntimeAction(client, 'match:combat_done', dto);
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
      this.logger.warn({ socketId: client.id, code }, 'WS auth rejected');
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
      this.logger.info(
        { userId, oldSocketId: old.id, socketId: current.id },
        'WS connection superseded',
      );
      old.data.superseded = true;
      old.disconnect(true);
    }
  }

  private userId(client: Socket): string {
    return (client.data.user as SocketUser).sub;
  }

  private runRuntimeAction(
    client: Socket,
    action: RuntimeActionType,
    dto: { clientActionId: string; round: number },
  ) {
    return this.runHandler(client, dto.clientActionId, `${action}.failed`, () =>
      this.runtime.handleAction(this.userId(client), action, dto));
  }

  private async runHandler<T>(
    client: Socket,
    clientActionId: string | undefined,
    fallbackCode: string,
    operation: () => Promise<T>,
  ): Promise<T | undefined> {
    try {
      return await operation();
    } catch (error: unknown) {
      const envelope = toGameError(error, fallbackCode, clientActionId);
      const context = {
        code: envelope.code,
        clientActionId,
        socketId: client.id,
        userId: this.userId(client),
      };
      if (envelope.code === 'internal') {
        this.logger.error({ ...context, err: error }, 'WS handler failed');
      } else {
        this.logger.warn(context, 'WS game:error');
      }
      client.emit('game:error', envelope);
      return undefined;
    }
  }

  private async resumeActiveMatch(client: Socket, userId: string): Promise<void> {
    try {
      const match = await this.matches.findActiveByUserId(userId);
      if (match && client.connected) {
        this.subscribeToMatch(client, match.id);
        // If match is in battle phase, re-send cached combat events so the
        // reconnecting client doesn't get stuck waiting for a missed event.
        const cached = await this.runtime.getCombatResultForReconnect(match.id);
        if (cached) {
          const battleEnd = cached.events.at(-1) as Record<string, unknown> | undefined;
          const cycleCount = battleEnd?.type === 'battle_end' ? battleEnd.cycle : 0;
          client.emit('game:combat:events', {
            matchId: match.id,
            round: cached.round,
            cycleCount,
            endedAt: Date.now(),
            events: cached.events,
          });
          this.logger.log(`combat events resent to reconnecting client user=${userId} match=${match.id}`);
        }
      }
    } catch (error: unknown) {
      this.logger.error(
        { err: error, userId, socketId: client.id },
        'active-match resume failed',
      );
    }
  }

  private async handleClientDisconnect(userId: string): Promise<void> {
    await this.matchmaking.leaveQueue(userId);
    await this.runtime.handleDisconnect(userId);
  }
}
