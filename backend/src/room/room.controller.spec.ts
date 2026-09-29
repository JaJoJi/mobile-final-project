import { UnauthorizedException } from '@nestjs/common';
import { JwtAccessGuard } from '../auth/guards/jwt-access.guard';
import { RoomController } from './room.controller';

describe('RoomController (#255)', () => {
  it('delegates creation to RoomService with the caller id', async () => {
    const rooms = {
      createRoom: jest.fn(async (ownerId: string) => ({
        roomId: 'room-1',
        code: 'ABC234',
        ownerId,
        guestId: null,
        status: 'waiting',
        expiresAt: new Date().toISOString(),
      })),
      getMyRoom: jest.fn(),
    };
    const controller = new RoomController(rooms as any);
    const body = await controller.create({ sub: 'owner-1', type: 'access' });
    expect(rooms.createRoom).toHaveBeenCalledWith('owner-1');
    expect(body).toMatchObject({ ownerId: 'owner-1', guestId: null, status: 'waiting' });
    expect(body.code).toMatch(/^[A-Z2-9]{6}$/);
  });

  it('delegates mine lookup to RoomService', async () => {
    const rooms = {
      createRoom: jest.fn(),
      joinRoom: jest.fn(),
      leaveRoom: jest.fn(),
      getMyRoom: jest.fn(async (userId: string) => ({ roomId: 'r', ownerId: userId })),
    };
    const controller = new RoomController(rooms as any);
    await controller.mine({ sub: 'owner-1', type: 'access' });
    expect(rooms.getMyRoom).toHaveBeenCalledWith('owner-1');
  });

  it('delegates join/leave with caller id and body', async () => {
    const rooms = {
      createRoom: jest.fn(),
      getMyRoom: jest.fn(),
      joinRoom: jest.fn(async () => ({ status: 'full' })),
      leaveRoom: jest.fn(async () => ({ room: null, closed: true })),
    };
    const controller = new RoomController(rooms as any);
    await controller.join({ sub: 'guest-1', type: 'access' }, { code: 'ABC234' } as any);
    expect(rooms.joinRoom).toHaveBeenCalledWith('guest-1', 'ABC234');
    await expect(
      controller.leave({ sub: 'guest-1', type: 'access' }),
    ).resolves.toEqual({ room: null, closed: true });
  });

  it('requires a JWT (missing header → 401 via the shared guard)', () => {
    const guard = new JwtAccessGuard({ verify: () => ({}) } as any);
    const context = {
      switchToHttp: () => ({ getRequest: () => ({ headers: {} }) }),
    } as any;
    expect(() => guard.canActivate(context)).toThrow(UnauthorizedException);
  });
});
