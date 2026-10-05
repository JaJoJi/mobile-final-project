import { Body, Controller, Get, Post, UseGuards } from '@nestjs/common';
import { JwtAccessGuard } from '../auth/guards/jwt-access.guard';
import { CurrentUser } from '../user/decorators/current-user.decorator';
import { RoomJoinDto } from './dto/room-join.dto';
import { RoomService } from './room.service';
import { UserService } from '../user/user.service';
import { RoomView } from './room.types';

/**
 * Private rooms: create, join, leave, and owner-controlled match start.
 */
@Controller('rooms')
@UseGuards(JwtAccessGuard)
export class RoomController {
  constructor(private readonly rooms: RoomService, private readonly users: UserService) {}

  private async withNames(room: RoomView) {
    const [owner, guest] = await Promise.all([
      this.users.findById(room.ownerId),
      room.guestId ? this.users.findById(room.guestId) : Promise.resolve(null),
    ]);
    return { ...room, ownerUsername: owner?.username ?? null, guestUsername: guest?.username ?? null };
  }

  @Post()
  async create(@CurrentUser() jwt: { sub: string; type: string }) {
    return this.withNames(await this.rooms.createRoom(jwt.sub));
  }

  @Get('mine')
  async mine(@CurrentUser() jwt: { sub: string; type: string }) {
    return this.withNames(await this.rooms.getMyRoom(jwt.sub));
  }

  @Post('join')
  async join(
    @CurrentUser() jwt: { sub: string; type: string },
    @Body() dto: RoomJoinDto,
  ) {
    return this.withNames(await this.rooms.joinRoom(jwt.sub, dto.code));
  }

  @Post('leave')
  async leave(@CurrentUser() jwt: { sub: string; type: string }) {
    return this.rooms.leaveRoom(jwt.sub);
  }

  @Post('start')
  async start(@CurrentUser() jwt: { sub: string; type: string }) {
    return this.rooms.startRoomForOwner(jwt.sub);
  }
}
