import { Type } from 'class-transformer';
import { IsInt, Max, Min } from 'class-validator';

export const LEADERBOARD_DEFAULT_LIMIT = 20;
export const LEADERBOARD_DEFAULT_OFFSET = 0;
export const LEADERBOARD_MAX_LIMIT = 100;

/**
 * `GET /leaderboard` query params (#256).
 *
 * Coerced from query strings by the global `ValidationPipe`
 * (`transform: true`). Anything outside the bounds below is a
 * `400 Bad Request` — never silently clamped.
 */
export class LeaderboardQueryDto {
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(LEADERBOARD_MAX_LIMIT)
  limit: number = LEADERBOARD_DEFAULT_LIMIT;

  @Type(() => Number)
  @IsInt()
  @Min(0)
  offset: number = LEADERBOARD_DEFAULT_OFFSET;
}
