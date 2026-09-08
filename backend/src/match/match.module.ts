import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { JwtAuthModule } from '../common/jwt-auth.module';
import { UserModule } from '../user/user.module';
import { WsModule } from '../ws/ws.module';
import { MatchController } from './match.controller';
import { MatchRound } from './match-round.entity';
import { Match } from './match.entity';
import { MatchRepository } from './match.repository';
import { MatchService } from './match.service';

/**
 * Match domain module.
 *
 * Imports `TypeOrmModule.forFeature([Match, MatchRound])` so both
 * entities get their repositories wired. The lifecycle service persists
 * round events here and P0-BE-13's orchestrator will call that service.
 *
 * Exports the repository and lifecycle service for matchmaking and the
 * orchestrator. MatchController exposes the guarded history/detail routes.
 *
 * Mirrors the structure of `UserModule` (TypeOrmModule.forFeature +
 * providers + exports) so the project stays consistent.
 */
@Module({
  imports: [
    TypeOrmModule.forFeature([Match, MatchRound]),
    JwtAuthModule,
    UserModule,
    WsModule,
  ],
  controllers: [MatchController],
  providers: [MatchRepository, MatchService],
  exports: [MatchRepository, MatchService],
})
export class MatchModule {}
