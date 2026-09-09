import { Injectable, Logger, OnModuleDestroy, OnModuleInit } from '@nestjs/common';
import Redis from 'ioredis';
import type { Server } from 'socket.io';
import type { CombatEvent } from '../game';
import { RedisService } from '../redis/redis.service';

interface PubSubEnvelope {
  type: string;
  payload: unknown;
  targetUserId?: string;
}

const CHANNEL_PATTERN = 'match:*:events';
const COMBAT_RESULT_TTL_SECONDS = 60;

/**
 * Cross-instance Pub/Sub bridge for real-time game events.
 *
 * This is the spine of multi-instance WS delivery (`docs/03-architecture.md §12`).
 * Any Nest instance can publish an event for a match via {@link publish}; the
 * pub/sub bus delivers it to every replica, which then fans it out to the
 * sockets on that replica that subscribed to the match. A client that
 * reconnects to a different replica mid-match still receives the next event
 * because Redis Pub/Sub is shared infrastructure, not per-instance.
 *
 * Why a manual PSUBSCRIBE pattern instead of `socket.io-redis-adapter`
 * (which is already installed from P0-BE-04):
 *   - Per-match fan-out. The adapter broadcasts every `io.emit(...)` to all
 *     sockets on all replicas. We only want the sockets interested in the
 *     publishing match to receive it, which is why we keep our own
 *     `localSubscribers` index.
 *   - 60 s late-subscriber cache for combat results lives here too, next
 *     to the fan-out path. Adapter would push that concern elsewhere.
 *
 * Lifecycle:
 *   - `onModuleInit` → duplicate the shared Redis connection (PSUBSCRIBE
 *     blocks the conn), PSUBSCRIBE `match:*:events`, bind `pmessage`.
 *   - `onModuleDestroy` → QUIT the dedicated subscriber so Redis releases
 *     the connection cleanly on Nest shutdown.
 *
 * Concurrency notes:
 *   - `localSubscribers` is per-replica, in-memory. Multiple replicas each
 *     maintain their own copy, indexed by the same `matchId`. The Redis
 *     bus is the source of truth for "this match had an event"; the index
 *     is purely a routing table from `matchId → sockets-on-this-replica`.
 *   - The bridge is the **only** place that touches Redis pub/sub. Future
 *     swaps to NATS / RabbitMQ change this file alone.
 */
@Injectable()
export class PubsubBridge implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(PubsubBridge.name);
  private subscriber: Redis | null = null;
  /** matchId → socketId/userId pairs on THIS replica that want its events */
  private readonly localSubscribers = new Map<string, Map<string, string | null>>();
  /** userId → live socketIds, used to attach newly-paired players to a match. */
  private readonly localUserSockets = new Map<string, Set<string>>();
  /** socket.io server for emitting, set by `WsGateway.afterInit` */
  private server: Server | null = null;

  constructor(private readonly redis: RedisService) {}

  async onModuleInit(): Promise<void> {
    // Dedicated subscriber connection. PSUBSCRIBE blocks the connection
    // (the wire stays quiet until a matching message arrives), so the
    // connection used for producer-side `publish()` and Lua `eval()` must
    // not be the one we hand to PSUBSCRIBE.
    this.subscriber = this.redis.client.duplicate();
    this.subscriber.on('error', (e: Error) =>
      this.logger.error(`pubsub subscriber error: ${e.message}`),
    );
    await this.subscriber.psubscribe(CHANNEL_PATTERN);
    this.subscriber.on('pmessage', (_pattern, channel, payload) => {
      this.handleMessage(channel, payload).catch((e: unknown) =>
        this.logger.error(`pmessage handler failed: ${(e as Error).message}`),
      );
    });
    this.logger.log(`PSUBSCRIBE ${CHANNEL_PATTERN} active`);
  }

  async onModuleDestroy(): Promise<void> {
    if (this.subscriber) {
      try {
        await this.subscriber.quit();
      } catch {
        /* connection may already be gone — that's fine */
      }
      this.subscriber = null;
    }
  }

  /**
   * Inject the socket.io `Server` once Nest finishes wiring it. The bridge
   * can't take this through DI because the server isn't a provider — it's
   * constructed by `@nestjs/platform-socket.io` after the gateway class is
   * instantiated. `OnGatewayInit.afterInit` is the documented hook for this.
   */
  setServer(server: Server): void {
    this.server = server;
  }

  registerUserSocket(userId: string, socketId: string): void {
    let sockets = this.localUserSockets.get(userId);
    if (!sockets) {
      sockets = new Set<string>();
      this.localUserSockets.set(userId, sockets);
    }
    sockets.add(socketId);
  }

  unregisterUserSocket(userId: string, socketId: string): void {
    const sockets = this.localUserSockets.get(userId);
    if (!sockets) return;
    sockets.delete(socketId);
    if (sockets.size === 0) this.localUserSockets.delete(userId);
  }

  // ─── Local fan-out registration ────────────────────────────────────────

  /**
   * Register a local socket as interested in a match's events. Idempotent
   * — adding the same `socketId` twice is a no-op.
   */
  subscribe(matchId: string, socketId: string, userId?: string): void {
    let bucket = this.localSubscribers.get(matchId);
    if (!bucket) {
      bucket = new Map<string, string | null>();
      this.localSubscribers.set(matchId, bucket);
    }
    bucket.set(socketId, userId ?? null);
  }

  /**
   * Stop delivering `matchId` events to a local socket. Safe to call when
   * the socket was never registered.
   */
  unsubscribe(matchId: string, socketId: string): void {
    const bucket = this.localSubscribers.get(matchId);
    if (!bucket) return;
    bucket.delete(socketId);
    if (bucket.size === 0) this.localSubscribers.delete(matchId);
  }

  // ─── Producer side ─────────────────────────────────────────────────────

  /**
   * Broadcast a server→client event for a match. Wraps the payload as
   * `{ type, payload }` and PUBLISHes on `match:<matchId>:events`. The
   * envelope shape is private to the bridge — handlers consume the
   * `eventType` directly.
   *
   * Returns once the publish is acked by Redis (fire-and-forget from
   * here; PSUBSCRIBE listeners may still miss it if the network blips —
   * race R15 in `docs/03-architecture.md §14` is covered by the 60 s
   * combat-result cache below).
   */
  async publish(matchId: string, eventType: string, payload: unknown): Promise<void> {
    const envelope: PubSubEnvelope = { type: eventType, payload };
    await this.redis.client.publish(
      `match:${matchId}:events`,
      JSON.stringify(envelope),
    );
  }

  /** Publish a private match event that is delivered only to one player. */
  async publishToUser(
    matchId: string,
    userId: string,
    eventType: string,
    payload: unknown,
  ): Promise<void> {
    const envelope: PubSubEnvelope = { type: eventType, payload, targetUserId: userId };
    await this.redis.client.publish(
      `match:${matchId}:events`,
      JSON.stringify(envelope),
    );
  }

  // ─── 60 s late-subscriber cache (race R14) ─────────────────────────────

  /**
   * Cache the full combat-event batch for `matchId` so a client that
   * reconnects within 60 s can fetch it via {@link getCombatResult}.
   * Stored as a STRING with `EX 60` — older entries auto-expire.
   */
  async writeCombatResult(matchId: string, events: CombatEvent[]): Promise<void> {
    await this.redis.client.set(
      `match:${matchId}:combat-result`,
      JSON.stringify(events),
      'EX',
      COMBAT_RESULT_TTL_SECONDS,
    );
  }

  /**
   * Read the cached combat-result batch for `matchId`. Returns `null` if
   * no cache entry exists (either it never was written or the 60 s TTL
   * has elapsed).
   */
  async getCombatResult(matchId: string): Promise<CombatEvent[] | null> {
    const raw = await this.redis.client.get(`match:${matchId}:combat-result`);
    if (!raw) return null;
    try {
      const parsed = JSON.parse(raw) as CombatEvent[];
      return Array.isArray(parsed) ? parsed : null;
    } catch (e: unknown) {
      this.logger.warn(`combat-result parse failed for match=${matchId}: ${(e as Error).message}`);
      return null;
    }
  }

  // ─── Internals ─────────────────────────────────────────────────────────

  /**
   * Parse a `pmessage` envelope and deliver to every local socket that
   * registered for the match. Silently drops messages for matches with no
   * local subscribers (the common case — most matches have only one or two
   * sockets per replica and only the match they care about).
   */
  private async handleMessage(channel: string, payload: string): Promise<void> {
    // channel = "match:<matchId>:events"
    const parts = channel.split(':');
    if (parts.length !== 3 || parts[0] !== 'match' || parts[2] !== 'events') {
      this.logger.warn(`ignoring unexpected channel: ${channel}`);
      return;
    }
    let envelope: PubSubEnvelope;
    try {
      envelope = JSON.parse(payload) as PubSubEnvelope;
    } catch (e: unknown) {
      this.logger.warn(`dropping malformed envelope on ${channel}: ${(e as Error).message}`);
      return;
    }
    if (!envelope?.type) return;

    const matchId = parts[1];
    // The first phase event is what tells a connected, queued player which
    // match they joined. Register those sockets before fan-out so neither the
    // phase nor the immediately-following private shop offer is lost.
    if (envelope.type === 'game:match:phase') {
      for (const userId of playerIdsFromPhase(envelope.payload)) {
        for (const socketId of this.localUserSockets.get(userId) ?? []) {
          this.subscribe(matchId, socketId, userId);
        }
      }
    }

    const bucket = this.localSubscribers.get(matchId);
    if (!bucket || bucket.size === 0) return;

    if (!this.server) {
      // Bridge got a message before the gateway injected the server (shouldn't
      // happen — `OnGatewayInit` runs before any client can publish — but be safe).
      this.logger.warn('pmessage arrived before server injection; dropping');
      return;
    }

    // `this.server` is the `/game` `Namespace` itself — `@WebSocketServer()`
    // on a namespaced `@WebSocketGateway` returns the namespace, NOT the
    // parent Server. So `.to(socketId).emit(...)` here is already
    // namespace-scoped; no extra `.of('/game')` needed.
    for (const [sid, userId] of bucket) {
      if (envelope.targetUserId && envelope.targetUserId !== userId) continue;
      this.server.to(sid).emit(envelope.type, envelope.payload);
    }
  }
}

function playerIdsFromPhase(payload: unknown): string[] {
  if (typeof payload !== 'object' || payload === null) return [];
  const players = (payload as { players?: unknown }).players;
  if (!Array.isArray(players)) return [];
  return players.flatMap((player) => {
    if (typeof player !== 'object' || player === null) return [];
    const id = (player as { id?: unknown }).id;
    return typeof id === 'string' ? [id] : [];
  });
}
