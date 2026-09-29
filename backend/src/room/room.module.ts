import { Module } from '@nestjs/common';
import { JwtAuthModule } from '../common/jwt-auth.module';
import { MatchModule } from '../match/match.module';
import { RoomController } from './room.controller';
import { RoomService } from './room.service';

/**
 * Room module (#255).
 *
 * Imports `MatchModule` for the active-match check only
 * (`MatchService.findActiveByUserId`) — the FIFO matchmaking flow itself
 * is untouched. Exports `RoomService` so #258/#259 (join, leave,
 * room→match) can reuse the key helpers and ownership mapping.
 */
@Module({
  imports: [JwtAuthModule, MatchModule],
  controllers: [RoomController],
  providers: [RoomService],
  exports: [RoomService],
})
export class RoomModule {}
