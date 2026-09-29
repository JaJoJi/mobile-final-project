import { Controller, Get, Post, UseGuards } from '@nestjs/common';
import { JwtAccessGuard } from '../auth/guards/jwt-access.guard';
import { CurrentUser } from '../user/decorators/current-user.decorator';
import { RoomService } from './room.service';

/**
 * Private rooms (#255) — pre-match 2-player lobby.
 *
 * Same guard convention as `/user/me`. Join/leave and room→match arrive
 * in #258/#259; this controller exposes creation plus self lookup only.
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
}
