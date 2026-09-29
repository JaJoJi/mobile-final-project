import { randomBytes, randomUUID } from 'crypto';

export type RoomStatus = 'waiting' | 'full' | 'matched';

export interface RoomView {
  roomId: string;
  code: string;
  ownerId: string;
  guestId: string | null;
  status: RoomStatus;
  expiresAt: string;
  /** Set once the room has transitioned into a match (#259). */
  matchId: string | null;
}

/** Redis key holding the room hash. */
export const roomKey = (roomId: string): string => `room:${roomId}`;

/** Redis key mapping a join code to its room (claimed atomically). */
export const roomCodeKey = (code: string): string => `room:code:${code}`;

/** Redis key mapping a user to their current room (single membership). */
export const userRoomKey = (userId: string): string => `user:room:${userId}`;

/** Redis key guarding the Room → Match handoff (#259, auto-expiring claim). */
export const roomHandoffKey = (roomId: string): string => `room:${roomId}:handoff`;

/** Handoff claim TTL — bounds a crashed worker; room stays retryable. */
export const ROOM_HANDOFF_TTL_SECONDS = 120;

/**
 * Matched-room tombstone TTL — lets late retries converge on the recorded
 * matchId instead of not_found. Short; no permanent room keys remain.
 */
export const ROOM_MATCH_TOMBSTONE_TTL_SECONDS = 300;

/** Room TTL — inside the 30–60 min project convention for ephemeral state. */
export const ROOM_TTL_SECONDS = 45 * 60;

const CODE_LENGTH = 6;
/**
 * Human-friendly alphabet: A-Z + 2-9 minus ambiguous 0/O/1/I
 * (32 symbols, one per 5-bit chunk).
 */
const CODE_ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
const MAX_CODE_ATTEMPTS = 10;

/** Pure 6-char code generator — statistical properties tested, not exact values. */
export function randomRoomCode(): string {
  const bytes = randomBytes(CODE_LENGTH);
  return Array.from(bytes, (b) => CODE_ALPHABET[b % CODE_ALPHABET.length]).join('');
}

/** Stored hash shape — `guestId`/`matchId` are `''` when empty (Redis hashes are strings). */
export interface RoomHash extends Record<string, string> {
  roomId: string;
  code: string;
  ownerId: string;
  guestId: string;
  status: RoomStatus;
  expiresAt: string;
  matchId: string;
}

export function roomHashToView(hash: RoomHash): RoomView {
  return {
    roomId: hash.roomId,
    code: hash.code,
    ownerId: hash.ownerId,
    guestId: hash.guestId === '' ? null : hash.guestId,
    status: hash.status,
    expiresAt: hash.expiresAt,
    matchId: hash.matchId === '' || hash.matchId === undefined ? null : hash.matchId,
  };
}

/**
 * Shared WS payload for `game:room:state` (#258 reuses this — #255 only
 * defines the contract, it does not emit yet).
 */
export function roomStatePayload(room: RoomView): RoomView {
  return { ...room };
}
