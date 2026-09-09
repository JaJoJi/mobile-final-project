import { Module } from '@nestjs/common';
import { JwtAuthModule } from '../common/jwt-auth.module';
import { MatchModule } from '../match/match.module';
import { MatchmakingModule } from '../matchmaking/matchmaking.module';
import { RuntimeModule } from '../runtime/match.runtime.module';
import { PubsubModule } from '../runtime/pubsub.module';
import { WsAuthGuard } from './guards/ws-auth.guard';
import { WsGameExceptionFilter } from './ws-exception.filter';
import { WsGateway } from './ws.gateway';
import { WsValidationPipe } from './ws.pipes';

/**
 * WebSocket gateway module (P0-BE-04 scaffold + P0-BE-10 handlers).
 *
 * Imports:
 *   - `JwtAuthModule` — provides `JwtService` so `WsAuthGuard` can verify
 *     the JWT pulled from the socket handshake. Reusing the shared
 *     module (same as `AuthModule` and `UserModule` do) avoids a
 *     parallel `JwtModule.registerAsync` and keeps the verify secret /
 *     algorithm in one place.
 *   - `PubsubModule` — shared cross-instance fan-out provider.
 *   - Matchmaking/Runtime/Match modules — services delegated to by handlers.
 *
 * Providers:
 *   - `WsAuthGuard` — verifies the namespace handshake.
 *   - `WsGateway` — the `@WebSocketGateway('/game')` itself.
 *   - `WsValidationPipe` — class-validator pipe applied to every message body.
 *   - `WsGameExceptionFilter` — maps pipe failures to `game:error`.
 *
 * Exports: `WsGateway` and `WsValidationPipe` for focused integration tests.
 */
@Module({
  imports: [JwtAuthModule, PubsubModule, MatchModule, RuntimeModule, MatchmakingModule],
  providers: [WsAuthGuard, WsValidationPipe, WsGameExceptionFilter, WsGateway],
  exports: [WsGateway, WsValidationPipe],
})
export class WsModule {}
