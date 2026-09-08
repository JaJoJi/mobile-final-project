import { Module } from '@nestjs/common';
import { runBattle } from '../game';
import { MatchModule } from '../match/match.module';
import { QueueModule } from '../queue/queue.module';
import { RUNTIME_QUEUE_PROCESSORS } from '../queue/queue.processors';
import { WsModule } from '../ws/ws.module';
import { RUN_BATTLE } from './combat-engine.provider';
import { CombatCoordinator } from './combat.coordinator';
import { MatchRuntimeAdapter } from './match.runtime.adapter';

@Module({
  imports: [MatchModule, QueueModule, WsModule],
  providers: [
    { provide: RUN_BATTLE, useValue: runBattle },
    CombatCoordinator,
    MatchRuntimeAdapter,
    ...RUNTIME_QUEUE_PROCESSORS,
  ],
  exports: [MatchRuntimeAdapter, CombatCoordinator],
})
export class RuntimeModule {}
