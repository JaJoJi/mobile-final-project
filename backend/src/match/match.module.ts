import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { MatchRound } from './match-round.entity';
import { Match } from './match.entity';
import { MatchRepository } from './match.repository';

/**
 * Match domain module.
 *
 * Imports `TypeOrmModule.forFeature([Match, MatchRound])` so both
 * entities get their repositories wired (MatchRound's repo is reserved
 * for the orchestrator — P0-BE-13 writes the per-round event log here).
 *
 * Exports `MatchRepository` so the matchmaking flow (P0-BE-11) and
 * the match lifecycle service (P0-BE-12) can both create / look up
 * matches. No controllers — match lifecycle is WS-driven, not REST.
 *
 * Mirrors the structure of `UserModule` (TypeOrmModule.forFeature +
 * providers + exports) so the project stays consistent.
 */
@Module({
  imports: [TypeOrmModule.forFeature([Match, MatchRound])],
  providers: [MatchRepository],
  exports: [MatchRepository],
})
export class MatchModule {}
