import { Injectable, Logger } from '@nestjs/common';
import { randomUUID } from 'crypto';
import { Match } from '../match/match.entity';
import { MatchRepository } from '../match/match.repository';
import { RedisService } from '../redis/redis.service';
import { PubsubBridge } from '../runtime/pubsub.bridge';

export const MATCHMAKING_QUEUE_KEY = 'matchmaking:queue';
export const MATCH_START_TIMER_SECONDS = 40;

export interface MatchmakingJoinResult {
  /** False means the user was already waiting; their original FIFO score is preserved. */
  queued: boolean;
}

export interface MatchPairResult {
  matchId: string;
  player1Id: string;
  player2Id: string;
}

export class MatchmakingError extends Error {
  constructor(
    public readonly code: 'match.already_active',
    message: string,
  ) {
    super(message);
    this.name = MatchmakingError.name;
  }
}

interface InitialPlayerState extends Record<string, unknown> {
  hp: number;
  gold: number;
  ready: boolean;
  board: null[];
  bench: null[];
}

/**
 * FIFO matchmaking backed by the shared Redis sorted set.
 *
 * Queue removal is performed by `match_pair.lua`, so multiple Nest replicas
 * may poll at the same time without pairing the same queue entry twice.
 */
@Injectable()
export class MatchmakingService {
  private readonly logger = new Logger(MatchmakingService.name);

  constructor(
    private readonly redis: RedisService,
    private readonly matches: MatchRepository,
    private readonly pubsub: PubsubBridge,
  ) {}

  /**
   * Add a player to the FIFO queue unless they already have a live match.
   * `NX` makes retries idempotent and, importantly, does not move an already
   * queued player to the back by replacing their original join timestamp.
   */
  async joinQueue(userId: string, joinedAtMs = Date.now()): Promise<MatchmakingJoinResult> {
    const active = await this.matches.findActiveByUserId(userId);
    if (active) {
      throw new MatchmakingError(
        'match.already_active',
        `User ${userId} already has active match ${active.id}`,
      );
    }

    const added = await this.redis.client.zadd(
      MATCHMAKING_QUEUE_KEY,
      'NX',
      joinedAtMs,
      userId,
    );
    return { queued: added === 1 };
  }

  /** Remove a waiting player. Returns true only when an entry was removed. */
  async leaveQueue(userId: string): Promise<boolean> {
    return (await this.redis.client.zrem(MATCHMAKING_QUEUE_KEY, userId)) > 0;
  }

  /**
   * Atomically take the two oldest players, persist their match and publish
   * the initial phase event. With fewer than two players this is a no-op.
   *
   * If persistence fails, both players are put back in the queue so a
   * transient database failure cannot silently lose them.
   */
  async tryPair(): Promise<MatchPairResult | null> {
    const players = await this.redis.eval<string[]>(
      'match_pair',
      [MATCHMAKING_QUEUE_KEY],
      [],
    );
    if (!Array.isArray(players) || players.length < 2) return null;

    const [player1Id, player2Id] = players;
    const [player1Active, player2Active] = await Promise.all([
      this.matches.findActiveByUserId(player1Id),
      this.matches.findActiveByUserId(player2Id),
    ]);
    if (player1Active || player2Active) {
      const freePlayers = [
        ...(player1Active ? [] : [player1Id]),
        ...(player2Active ? [] : [player2Id]),
      ];
      await this.requeueAfterFailure(...freePlayers);
      this.logger.warn(
        `discarded stale queue entry: player1Active=${Boolean(player1Active)} ` +
          `player2Active=${Boolean(player2Active)}`,
      );
      return null;
    }

    let match: Match;
    try {
      match = await this.createMatch(player1Id, player2Id);
    } catch (error: unknown) {
      await this.requeueAfterFailure(player1Id, player2Id);
      throw error;
    }

    // Once the DB row exists, never requeue these users: doing so after a
    // Pub/Sub outage could create a second active match for the same player.
    await this.publishMatchStart(match);
    this.logger.log(
      `paired match=${match.id} player1=${player1Id} player2=${player2Id}`,
    );
    return { matchId: match.id, player1Id, player2Id };
  }

  private createMatch(player1Id: string, player2Id: string): Promise<Match> {
    return this.matches.create({
      player1Id,
      player2Id,
      matchSeed: randomUUID(),
      p1State: this.initialPlayerState(),
      p2State: this.initialPlayerState(),
    });
  }

  private initialPlayerState(): InitialPlayerState {
    return {
      hp: 100,
      gold: 5,
      ready: false,
      board: Array<null>(9).fill(null),
      bench: Array<null>(8).fill(null),
    };
  }

  private async publishMatchStart(match: Match): Promise<void> {
    await this.pubsub.publish(match.id, 'game:match:phase', {
      matchId: match.id,
      phase: 'shop_place',
      round: 1,
      timer: MATCH_START_TIMER_SECONDS,
      players: [
        { id: match.player1Id, hp: 100, gold: 5, ready: false },
        { id: match.player2Id, hp: 100, gold: 5, ready: false },
      ],
    });
  }

  private async requeueAfterFailure(...playerIds: string[]): Promise<void> {
    if (playerIds.length === 0) return;
    const now = Date.now();
    try {
      const entries = playerIds.flatMap((playerId, index) => [now + index, playerId]);
      await this.redis.client.zadd(MATCHMAKING_QUEUE_KEY, 'NX', ...entries);
    } catch (requeueError: unknown) {
      this.logger.error(
        `failed to requeue players ${playerIds.join(',')}: ${(requeueError as Error).message}`,
      );
    }
  }
}
