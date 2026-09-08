import { Module } from '@nestjs/common';
import { MatchModule } from '../match/match.module';
import { QueueModule } from '../queue/queue.module';
import { WsModule } from '../ws/ws.module';
import { MatchmakingProcessor } from './matchmaking.processor';
import { MatchmakingScheduler } from './matchmaking.scheduler';
import { MatchmakingService } from './matchmaking.service';

@Module({
  imports: [MatchModule, QueueModule, WsModule],
  providers: [MatchmakingService, MatchmakingProcessor, MatchmakingScheduler],
  exports: [MatchmakingService],
})
export class MatchmakingModule {}
