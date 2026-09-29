import { Module } from '@nestjs/common';
import { JwtAuthModule } from '../common/jwt-auth.module';
import { MatchModule } from '../match/match.module';
import { PubsubModule } from '../runtime/pubsub.module';
import { RoomController } from './room.controller';
import { RoomService } from './room.service';

/**
 * Room module (#255 core, #258 join/leave).
 *
 * Imports `MatchModule` for the active-match check only
 * (`MatchService.findActiveByUserId`) and `PubsubModule` for
 * `game:room:state` fan-out — the FIFO matchmaking flow itself
 * is untouched. Exports `RoomService` so #259 (room→match) can reuse
 * the key helpers and ownership mapping.
 */
@Module({
  imports: [JwtAuthModule, MatchModule, PubsubModule],
  controllers: [RoomController],
  providers: [RoomService],
  exports: [RoomService],
})
export class RoomModule {}
