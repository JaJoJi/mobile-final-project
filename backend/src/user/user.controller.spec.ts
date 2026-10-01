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

describe('UserController /user/me read + update (#308)', () => {
  const user = (overrides: Record<string, unknown> = {}) => ({
    id: 'user-1',
    email: 'alice@example.com',
    username: 'alice',
    rating: 1000,
    ...overrides,
  });

  it('returns the profile shape and isolates callers by sub', async () => {
    const users = { findById: jest.fn(async () => user()) };
    const controller = new UserController(users as any, {} as any);
    const body = await controller.me({ sub: 'user-1', type: 'access' });
    expect(users.findById).toHaveBeenCalledWith('user-1');
    expect(body).toEqual({
      id: 'user-1',
      email: 'alice@example.com',
      username: 'alice',
      rating: 1000,
    });
    expect(body).not.toHaveProperty('passwordHash');
  });

  it('rejects profiles for deleted users', async () => {
    const users = { findById: jest.fn(async () => null) };
    const controller = new UserController(users as any, {} as any);
    await expect(controller.me({ sub: 'ghost', type: 'access' })).rejects.toMatchObject({
      status: 409,
    });
  });

  it('returns the updated profile on rename', async () => {
    const users = {
      updateUsername: jest.fn(async () => user({ username: 'alice2' })),
    };
    const controller = new UserController(users as any, {} as any);
    const body = await controller.updateMe(
      { sub: 'user-1', type: 'access' },
      { username: 'alice2' },
    );
    expect(users.updateUsername).toHaveBeenCalledWith('user-1', 'alice2');
    expect(body).toMatchObject({ username: 'alice2' });
  });

  it('maps username collisions to 409 and rethrows anything else', async () => {
    const taken = {
      updateUsername: jest.fn(async () => {
        const err: any = new Error('duplicate');
        err.code = '23505';
        throw err;
      }),
    };
    const controller = new UserController(taken as any, {} as any);
    await expect(
      controller.updateMe({ sub: 'user-1', type: 'access' }, { username: 'bob' }),
    ).rejects.toMatchObject({ status: 409 });

    const broken = {
      updateUsername: jest.fn(async () => {
        throw new Error('connection reset');
      }),
    };
    const controller2 = new UserController(broken as any, {} as any);
    await expect(
      controller2.updateMe({ sub: 'user-1', type: 'access' }, { username: 'bob' }),
    ).rejects.toThrow('connection reset');
  });
});
