import { UnauthorizedException } from '@nestjs/common';
import { JwtAccessGuard } from '../auth/guards/jwt-access.guard';
import { UserController } from './user.controller';

describe('UserController /user/me/stats (#254)', () => {
  it('delegates to StatsService and returns the exact contract shape', async () => {
    const stats = {
      getStats: jest.fn(async (_userId: string) => ({
        matches: 12,
        wins: 7,
        losses: 5,
        winRate: 58,
        currentRank: 28,
      })),
    };
    const controller = new UserController({} as any, stats as any);
    const body = await controller.getMyStats({ sub: 'user-1', type: 'access' });
    expect(stats.getStats).toHaveBeenCalledWith('user-1');
    expect(body).toEqual({
      matches: 12,
      wins: 7,
      losses: 5,
      winRate: 58,
      currentRank: 28,
    });
  });

  it('requires a JWT (missing header → 401 via the shared guard)', () => {
    const guard = new JwtAccessGuard({ verify: () => ({}) } as any);
    const context = {
      switchToHttp: () => ({ getRequest: () => ({ headers: {} }) }),
    } as any;
    expect(() => guard.canActivate(context)).toThrow(UnauthorizedException);
  });
});
