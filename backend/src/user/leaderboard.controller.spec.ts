import { plainToInstance } from 'class-transformer';
import { validate } from 'class-validator';
import { UnauthorizedException } from '@nestjs/common';
import { JwtAccessGuard } from '../auth/guards/jwt-access.guard';
import {
  LEADERBOARD_DEFAULT_LIMIT,
  LEADERBOARD_DEFAULT_OFFSET,
  LeaderboardQueryDto,
} from './dto/leaderboard-query.dto';
import { LeaderboardController } from './leaderboard.controller';

const toQuery = (input: Record<string, unknown>) =>
  plainToInstance(LeaderboardQueryDto, input);

describe('LeaderboardQueryDto validation (#256)', () => {
  it('applies defaults limit=20 offset=0', async () => {
    const dto = toQuery({});
    expect(await validate(dto)).toHaveLength(0);
    expect(dto.limit).toBe(LEADERBOARD_DEFAULT_LIMIT);
    expect(dto.offset).toBe(LEADERBOARD_DEFAULT_OFFSET);
  });

  it('accepts custom limit/offset', async () => {
    const dto = toQuery({ limit: '5', offset: '10' });
    expect(await validate(dto)).toHaveLength(0);
    expect(dto.limit).toBe(5);
    expect(dto.offset).toBe(10);
  });

  it.each([{ limit: '0' }, { limit: '-1' }, { limit: 'abc' }, { limit: '101' }])(
    'rejects invalid limit %p with 400-class errors',
    async (input) => {
      expect(await validate(toQuery(input))).not.toHaveLength(0);
    },
  );

  it.each([{ offset: '-1' }, { offset: 'abc' }])(
    'rejects invalid offset %p with 400-class errors',
    async (input) => {
      expect(await validate(toQuery(input))).not.toHaveLength(0);
    },
  );
});

describe('LeaderboardController (#256)', () => {
  it('delegates to the service and returns the exact contract shape', async () => {
    const board = {
      getLeaderboard: jest.fn(async () => ({
        entries: [{ rank: 1, username: 'MoonKnight', rating: 1840 }],
        me: { rank: 28, username: 'JaJoJi', rating: 1240 },
        limit: 20,
        offset: 0,
        total: 132,
      })),
    };
    const controller = new LeaderboardController(board as any);
    const body = await controller.list(
      { limit: 20, offset: 0 } as LeaderboardQueryDto,
      { sub: 'user-1', type: 'access' },
    );
    expect(board.getLeaderboard).toHaveBeenCalledWith('user-1', 20, 0);
    expect(body).toEqual({
      entries: [{ rank: 1, username: 'MoonKnight', rating: 1840 }],
      me: { rank: 28, username: 'JaJoJi', rating: 1240 },
      limit: 20,
      offset: 0,
      total: 132,
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
