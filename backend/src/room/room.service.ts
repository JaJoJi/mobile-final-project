import {
  ConflictException,
  Injectable,
  Logger,
  NotFoundException,
  ServiceUnavailableException,
} from '@nestjs/common';
import { randomUUID } from 'crypto';
import { MatchService } from '../match/match.service';
import { MATCHMAKING_QUEUE_KEY } from '../matchmaking/matchmaking.keys';
import { RedisService } from '../redis/redis.service';
import {
  ROOM_TTL_SECONDS,
  RoomStatus,
  RoomView,
  randomRoomCode,
  roomCodeKey,
  roomHashToView,
  roomKey,
  userRoomKey,
} from './room.types';

/**
 * Private-room core for Issue #255 — a 2-player pre-match lobby.
 *
 * Rooms are ephemeral and live in Redis only (no PostgreSQL table).
 * This module is independent from the FIFO matchmaking flow: it only
 * READS `matchmaking:queue` (to refuse double-queuing) and reuses
 * `MatchService.findActiveByUserId` for the active-match check.
 *
 * Synchronization point is Redis, never in-memory locks:
 *   - single membership via `SET user:room:<uid> NX` (double-create races
 *     collapse to exactly one winner);
 *   - code uniqueness via `SET room:code:<CODE> NX` with retry.
 * The final-slot join race (#258) will use Lua; creation needs none beyond NX.
 *
 * Redis errors propagate (rooms have no PostgreSQL fallback — unlike the
 * stats/leaderboard caches, Redis IS the store here).
 */
@Injectable()
export class RoomService {
  private readonly logger = new Logger(RoomService.name);

  constructor(
    private readonly redis: RedisService,
    private readonly matches: MatchService,
  ) {}

  /** Override point for deterministic collision tests (prod uses crypto). */
  protected randomCode(): string {
    return randomRoomCode();
  }

  async createRoom(ownerId: string): Promise<RoomView> {
    // Claim single membership first: concurrent creates by the same user
    // collapse here — exactly one wins the NX.
    const slot = await this.redis.client.set(
      userRoomKey(ownerId),
      'pending',
      'EX',
      ROOM_TTL_SECONDS,
      'NX',
    );
    if (slot !== 'OK') {
      throw new ConflictException({
        code: 'room.already_in_room',
        message: 'You are already in a room',
      });
    }

    try {
      const active = await this.matches.findActiveByUserId(ownerId);
      if (active) {
        throw new ConflictException({
          code: 'match.already_active',
          message: 'You already have an active match',
        });
      }
      const queued = await this.redis.client.zscore(MATCHMAKING_QUEUE_KEY, ownerId);
      if (queued !== null) {
        throw new ConflictException({
          code: 'room.in_matchmaking_queue',
          message: 'Leave the matchmaking queue before creating a room',
        });
      }

      const roomId = randomUUID();
      const code = await this.claimCode(roomId);
      const expiresAt = new Date(Date.now() + ROOM_TTL_SECONDS * 1000).toISOString();
      await this.redis.client.hset(roomKey(roomId), {
        roomId,
        code,
        ownerId,
        guestId: '',
        status: 'waiting' satisfies RoomStatus,
        expiresAt,
      });
      await this.redis.client.expire(roomKey(roomId), ROOM_TTL_SECONDS);
      // Replace the pending placeholder with the real room id (same TTL).
      await this.redis.client.set(
        userRoomKey(ownerId),
        roomId,
        'EX',
        ROOM_TTL_SECONDS,
      );
      this.logger.log(`room created room=${roomId} code=${code} owner=${ownerId}`);
      return { roomId, code, ownerId, guestId: null, status: 'waiting', expiresAt };
    } catch (e: unknown) {
      // Best-effort rollback of our own claim so a failed create does not
      // wedge the owner out of future creates (TTL is the backstop).
      try {
        await this.redis.client.del(userRoomKey(ownerId));
      } catch {
        /* TTL cleans it up */
      }
      throw e;
    }
  }

  async getMyRoom(userId: string): Promise<RoomView> {
    const roomId = await this.redis.client.get(userRoomKey(userId));
    if (!roomId || roomId === 'pending') {
      throw new NotFoundException({
        code: 'room.not_in_room',
        message: 'You are not currently in a room',
      });
    }
    const hash = await this.redis.client.hgetall(roomKey(roomId));
    if (!hash?.roomId) {
      // Mapping outlived the room (expiry race) — clean it and report.
      try {
        await this.redis.client.del(userRoomKey(userId));
      } catch {
        /* TTL cleans it up */
      }
      throw new NotFoundException({
        code: 'room.not_found',
        message: 'Room no longer exists',
      });
    }
    return roomHashToView({
      roomId: hash.roomId,
      code: hash.code,
      ownerId: hash.ownerId,
      guestId: hash.guestId ?? '',
      status: hash.status as RoomStatus,
      expiresAt: hash.expiresAt,
    });
  }

  /** Generate + atomically claim a unique code, retrying on collision. */
  private async claimCode(roomId: string): Promise<string> {
    for (let attempt = 0; attempt < MAX_CODE_CLAIM_ATTEMPTS; attempt += 1) {
      const code = this.randomCode();
      const claimed = await this.redis.client.set(
        roomCodeKey(code),
        roomId,
        'EX',
        ROOM_TTL_SECONDS,
        'NX',
      );
      if (claimed === 'OK') return code;
    }
    throw new ServiceUnavailableException({
      code: 'room.code_unavailable',
      message: 'Could not allocate a room code, please retry',
    });
  }
}

/** Code-claim retries before surfacing room.code_unavailable. */
const MAX_CODE_CLAIM_ATTEMPTS = 10;
