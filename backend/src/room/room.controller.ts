import { Body, Controller, Get, Post, UseGuards } from '@nestjs/common';
import { JwtAccessGuard } from '../auth/guards/jwt-access.guard';
import { CurrentUser } from '../user/decorators/current-user.decorator';
import { RoomJoinDto } from './dto/room-join.dto';
import { RoomService } from './room.service';

/**
 * Private rooms (#255 core, #258 join/leave).
 *
 * Same guard convention as `/user/me`. Room→match auto-transition arrives
 * in #259 — a full room simply waits here.
 */
@Controller('rooms')
@UseGuards(JwtAccessGuard)
export class RoomController {
  constructor(private readonly rooms: RoomService) {}

  @Post()
  async create(@CurrentUser() jwt: { sub: string; type: string }) {
    return this.rooms.createRoom(jwt.sub);
  }

  @Get('mine')
  async mine(@CurrentUser() jwt: { sub: string; type: string }) {
    return this.rooms.getMyRoom(jwt.sub);
  }

  @Post('join')
  async join(
    @CurrentUser() jwt: { sub: string; type: string },
    @Body() dto: RoomJoinDto,
  ) {
    return this.rooms.joinRoom(jwt.sub, dto.code);
  }

  @Post('leave')
  async leave(@CurrentUser() jwt: { sub: string; type: string }) {
    return this.rooms.leaveRoom(jwt.sub);
  }
}
