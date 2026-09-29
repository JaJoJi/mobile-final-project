import {
  BadRequestException,
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
import { PubsubBridge } from '../runtime/pubsub.bridge';
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

/** Join result codes from room_join.lua (see the script header). */
const JOIN_OK = 1;
const JOIN_ROOM_NOT_FOUND = 0;
const JOIN_ROOM_FULL = -1;
const JOIN_ALREADY_IN_ROOM = -2;
const JOIN_NOT_WAITING = -3;
const JOIN_OWNER = -4;

/** Leave result codes from room_leave.lua. */
const LEAVE_MISSING = 0;
const LEAVE_GUEST = 1;
const LEAVE_OWNER = 2;

export interface LeaveRoomResult {
  room: RoomView | null;
  closed: boolean;
}

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
    private readonly pubsub: PubsubBridge,
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

  /**
   * Join a room by code (#258). Advisory checks (format, membership, active
   * match, queue) run first for clear errors; the guest-slot claim itself
   * is one atomic Lua transition (WAITING → FULL + both key writes).
   *
   * Known limitation (documented, accepted): the queue/active-match reads
   * cannot join the Lua atomically — a user could enter the FIFO queue in
   * the gap between the check and the commit. Lua still guarantees the
   * slot invariant; a global lock to close the gap is deliberately avoided.
   */
  async joinRoom(userId: string, rawCode: string): Promise<RoomView> {
    const code = rawCode.trim().toUpperCase();
    if (!/^[A-Z2-9]{6}$/.test(code)) {
      throw new BadRequestException({
        code: 'room.invalid_code',
        message: 'Room code must be 6 characters A-Z/2-9',
      });
    }
    const roomId = await this.redis.client.get(roomCodeKey(code));
    if (!roomId) {
      throw new NotFoundException({
        code: 'room.not_found',
        message: 'No room exists for this code',
      });
    }
    if (await this.redis.client.get(userRoomKey(userId))) {
      throw new ConflictException({
        code: 'room.already_in_room',
        message: 'You are already in a room',
      });
    }
    if (await this.matches.findActiveByUserId(userId)) {
      throw new ConflictException({
        code: 'match.already_active',
        message: 'You already have an active match',
      });
    }
    if ((await this.redis.client.zscore(MATCHMAKING_QUEUE_KEY, userId)) !== null) {
      throw new ConflictException({
        code: 'room.in_matchmaking_queue',
        message: 'Leave the matchmaking queue before joining a room',
      });
    }

    const result = Number(
      await this.redis.eval<number>(
        'room_join',
        [roomKey(roomId), userRoomKey(userId)],
        [userId, roomId, ROOM_TTL_SECONDS],
      ),
    );
    switch (result) {
      case JOIN_ROOM_NOT_FOUND:
        throw new NotFoundException({
          code: 'room.not_found',
          message: 'Room no longer exists',
        });
      case JOIN_ROOM_FULL:
        throw new ConflictException({
          code: 'room.full',
          message: 'Room already has two players',
        });
      case JOIN_ALREADY_IN_ROOM:
        throw new ConflictException({
          code: 'room.already_in_room',
          message: 'You are already in a room',
        });
      case JOIN_NOT_WAITING:
        throw new ConflictException({
          code: 'room.not_waiting',
          message: 'Room is no longer accepting players',
        });
      case JOIN_OWNER:
        throw new BadRequestException({
          code: 'room.owner_cannot_join',
          message: 'The room owner is already in the room',
        });
      case JOIN_OK:
        break;
      default:
        throw new ServiceUnavailableException({
          code: 'room.join_failed',
          message: 'Could not join the room, please retry',
        });
    }

    const room = await this.loadRoom(roomId);
    await this.pubsub.publishToRoom(roomId, 'game:room:state', room, [
      room.ownerId,
      room.guestId as string,
    ]);
    return room;
  }

  /**
   * Leave the caller's room (#258). Guest leave flips back to waiting;
   * owner leave destroys all four keys atomically (guest is never promoted).
   */
  async leaveRoom(userId: string): Promise<LeaveRoomResult> {
    const roomId = await this.redis.client.get(userRoomKey(userId));
    if (!roomId || roomId === 'pending') {
      throw new NotFoundException({
        code: 'room.not_in_room',
        message: 'You are not currently in a room',
      });
    }
    // Pre-read for the owner-destroy notification only (best-effort);
    // the authoritative mutation is the Lua call below.
    const before = await this.redis.client.hgetall(roomKey(roomId));
    const result = Number(
      await this.redis.eval<number>(
        'room_leave',
        [roomKey(roomId), userRoomKey(userId)],
        [userId],
      ),
    );
    if (result === LEAVE_MISSING) {
      try {
        await this.redis.client.del(userRoomKey(userId));
      } catch {
        /* TTL cleans it up */
      }
      throw new NotFoundException({
        code: 'room.not_in_room',
        message: 'You are not currently in a room',
      });
    }
    if (result === LEAVE_OWNER) {
      const guestId = before?.guestId;
      if (guestId) {
        await this.pubsub.publishToRoom(
          roomId,
          'game:room:state',
          {
            roomId,
            code: before.code,
            ownerId: before.ownerId,
            guestId,
            status: 'closed',
            expiresAt: before.expiresAt,
          },
          [guestId],
        );
      }
      return { room: null, closed: true };
    }
    const room = await this.loadRoom(roomId);
    await this.pubsub.publishToRoom(roomId, 'game:room:state', room, [room.ownerId]);
    return { room, closed: false };
  }

  private async loadRoom(roomId: string): Promise<RoomView> {
    const hash = await this.redis.client.hgetall(roomKey(roomId));
    if (!hash?.roomId) {
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
