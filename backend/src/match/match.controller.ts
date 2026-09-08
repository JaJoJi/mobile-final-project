import { Controller, Get, Param, ParseUUIDPipe, UseGuards } from '@nestjs/common';
import { JwtAccessGuard } from '../auth/guards/jwt-access.guard';
import { CurrentUser } from '../user/decorators/current-user.decorator';
import { MatchService } from './match.service';

@Controller('match')
@UseGuards(JwtAccessGuard)
export class MatchController {
  constructor(private readonly matches: MatchService) {}

  @Get('history')
  history(@CurrentUser() user: { sub: string }) {
    return this.matches.getHistory(user.sub);
  }

  @Get(':matchId')
  detail(
    @Param('matchId', new ParseUUIDPipe({ version: '4' })) matchId: string,
    @CurrentUser() user: { sub: string },
  ) {
    return this.matches.getDetail(matchId, user.sub);
  }
}
