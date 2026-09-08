import { IsIn, IsInt, IsUUID, Max, Min } from 'class-validator';

/**
 * DTOs for every incoming WS payload (`client → server`).
 *
 * Schema frozen in `docs/04-api-contracts.md §2.2`; validation rules in
 * `§3`. These classes are the security boundary for the WS layer
 * (`NFR-6` — validate all WS payloads). A handler in P0-BE-10 receives
 * the already-validated instance via `@MessageBody()` once
 * `WsValidationPipe` is applied.
 *
 * What is checked HERE (shape / range, static):
 *   - field presence + primitive type (`@IsInt`, `@IsUUID`)
 *   - static bounds (`offerIndex` 0..4, `slot` 0..8, `round` >= 1)
 *   - enum membership (`source`, `target`, `unitId`)
 *
 * What is NOT checked here (runtime / stateful — lives in P0-BE-10..14):
 *   - `round` equals the server's current round
 *   - `unitInstanceId` is in the caller's roster
 *   - gold / ownership / "refresh already used"
 *   - `clientActionId` not already processed (idempotency, §4)
 */

/** Board is 3×3 (slots 0..8); bench holds 8 (slots 0..7). Upper bound
 *  is the board's — the bench-specific 0..7 check is stateful (P0-BE-10). */
const SLOT_MAX = 8;
/** 5 shop offers per round → indices 0..4. */
const OFFER_INDEX_MAX = 4;

/** Canonical unit ids — `docs/05-combat-spec.md §3`. */
export const UNIT_IDS = ['fighter', 'healer', 'ranger', 'tank'] as const;
export type UnitId = (typeof UNIT_IDS)[number];

export const PLACE_SOURCES = ['board', 'bench'] as const;
export type PlaceSource = (typeof PLACE_SOURCES)[number];

/** `game:matchmaking:join` — no payload. */
export class MatchmakingJoinDto {}

/** `game:matchmaking:leave` — no payload. */
export class MatchmakingLeaveDto {}

/** `game:shop:buy` — `{ round, offerIndex 0..4, clientActionId }`. */
export class ShopBuyDto {
  @IsInt()
  @Min(1)
  round!: number;

  @IsInt()
  @Min(0)
  @Max(OFFER_INDEX_MAX)
  offerIndex!: number;

  @IsUUID()
  clientActionId!: string;
}

/** `game:shop:sell` — `{ round, source, slot 0..8, clientActionId }`. */
export class ShopSellDto {
  @IsInt()
  @Min(1)
  round!: number;

  @IsIn(PLACE_SOURCES)
  source!: PlaceSource;

  @IsInt()
  @Min(0)
  @Max(SLOT_MAX)
  slot!: number;

  @IsUUID()
  clientActionId!: string;
}

/** `game:shop:refresh` — `{ round, clientActionId }`. */
export class ShopRefreshDto {
  @IsInt()
  @Min(1)
  round!: number;

  @IsUUID()
  clientActionId!: string;
}

/** `game:shop:fuse` — `{ round, unitId, clientActionId }`. */
export class ShopFuseDto {
  @IsInt()
  @Min(1)
  round!: number;

  @IsIn(UNIT_IDS)
  unitId!: UnitId;

  @IsUUID()
  clientActionId!: string;
}

/**
 * `game:match:place` —
 * `{ round, unitInstanceId, target, slot 0..8, clientActionId }`.
 */
export class MatchPlaceDto {
  @IsInt()
  @Min(1)
  round!: number;

  @IsUUID()
  unitInstanceId!: string;

  @IsIn(PLACE_SOURCES)
  target!: PlaceSource;

  @IsInt()
  @Min(0)
  @Max(SLOT_MAX)
  slot!: number;

  @IsUUID()
  clientActionId!: string;
}

/** `game:match:ready` — `{ round, clientActionId }`. */
export class MatchReadyDto {
  @IsInt()
  @Min(1)
  round!: number;

  @IsUUID()
  clientActionId!: string;
}

/** `game:match:combat_done` — `{ matchId, round, clientActionId }`. */
export class MatchCombatDoneDto {
  @IsUUID()
  matchId!: string;

  @IsInt()
  @Min(1)
  round!: number;

  @IsUUID()
  clientActionId!: string;
}

/**
 * Event name → DTO class. P0-BE-10 wires each `@SubscribeMessage` to the
 * matching DTO; keeping the map here means one place lists the full WS
 * incoming surface.
 */
export const WS_INCOMING_DTOS = {
  'game:matchmaking:join': MatchmakingJoinDto,
  'game:matchmaking:leave': MatchmakingLeaveDto,
  'game:shop:buy': ShopBuyDto,
  'game:shop:sell': ShopSellDto,
  'game:shop:refresh': ShopRefreshDto,
  'game:shop:fuse': ShopFuseDto,
  'game:match:place': MatchPlaceDto,
  'game:match:ready': MatchReadyDto,
  'game:match:combat_done': MatchCombatDoneDto,
} as const;
