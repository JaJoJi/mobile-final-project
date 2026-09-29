import { Controller, Get, Query, UseGuards } from '@nestjs/common';
import { JwtAccessGuard } from '../auth/guards/jwt-access.guard';
import { CurrentUser } from './decorators/current-user.decorator';
import {
  LEADERBOARD_DEFAULT_LIMIT,
  LEADERBOARD_DEFAULT_OFFSET,
  LeaderboardQueryDto,
} from './dto/leaderboard-query.dto';
import { LeaderboardService } from './leaderboard.service';

/**
 * `GET /leaderboard?limit=&offset=` (#256).
 *
 * Same guard as `/user/me`. Pagination validated by `LeaderboardQueryDto`
 * (invalid values → 400 via the global `ValidationPipe`). Rank is computed
 * server-side with `RANK()` semantics — never from the page position.
 */
@Controller('leaderboard')
@UseGuards(JwtAccessGuard)
export class LeaderboardController {
  constructor(private readonly board: LeaderboardService) {}

  @Get()
  async list(
    @Query() query: LeaderboardQueryDto,
    @CurrentUser() jwt: { sub: string; type: string },
  ) {
    return this.board.getLeaderboard(
      jwt.sub,
      query.limit ?? LEADERBOARD_DEFAULT_LIMIT,
      query.offset ?? LEADERBOARD_DEFAULT_OFFSET,
    );
  }
}
