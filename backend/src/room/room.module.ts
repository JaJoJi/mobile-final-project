import { Module } from '@nestjs/common';
import { JwtAuthModule } from '../common/jwt-auth.module';
import { MatchModule } from '../match/match.module';
import { MatchmakingModule } from '../matchmaking/matchmaking.module';
import { PubsubModule } from '../runtime/pubsub.module';
import { RoomController } from './room.controller';
import { RoomService } from './room.service';

/**
 * Room module (#255 core, #258 join/leave, #259 handoff).
 *
 * Imports `MatchModule` for the active-match check only
 * (`MatchService.findActiveByUserId`), `MatchmakingModule` for the shared
 * creation seam (`createMatchForPlayers` — FIFO flow itself untouched),
 * and `PubsubModule` for `game:room:state` fan-out.
 * Exports `RoomService` for future room consumers.
 */
@Module({
  imports: [JwtAuthModule, MatchModule, MatchmakingModule, PubsubModule],
  controllers: [RoomController],
  providers: [RoomService],
  exports: [RoomService],
})
export class RoomModule {}
