import { Module } from '@nestjs/common';
import { JwtAuthModule } from '../common/jwt-auth.module';
import { PubsubBridge } from '../runtime/pubsub.bridge';
import { WsAuthGuard } from './guards/ws-auth.guard';
import { WsGateway } from './ws.gateway';
import { WsValidationPipe } from './ws.pipes';

/**
 * WebSocket gateway module (P0-BE-04 skeleton).
 *
 * Imports:
 *   - `JwtAuthModule` — provides `JwtService` so `WsAuthGuard` can verify
 *     the JWT pulled from the socket handshake. Reusing the shared
 *     module (same as `AuthModule` and `UserModule` do) avoids a
 *     parallel `JwtModule.registerAsync` and keeps the verify secret /
 *     algorithm in one place.
 *
 * Providers:
 *   - `PubsubBridge` — stub from P0-BE-04. P0-BE-05 swaps the body for
 *     a real Redis Pub/Sub adapter; the import path and DI token stay
 *     stable, so no other module needs to change.
 *   - `WsAuthGuard` — usable directly by the gateway now, and by
 *     `@UseGuards` on future `@SubscribeMessage` handlers in P0-BE-10.
 *   - `WsGateway` — the `@WebSocketGateway('/game')` itself.
 *   - `WsValidationPipe` — class-validator pipe for incoming message
 *     payloads (P0-BE-08). P0-BE-10 applies it per `@SubscribeMessage`
 *     via `@UsePipes(WsValidationPipe)`.
 *
 * Exports: `WsGateway` so other modules (e.g. orchestrator adapters in
 * P0-BE-13) can emit to connected sockets via DI; `WsValidationPipe` so
 * the handler module in P0-BE-10 can reference it.
 */
@Module({
  imports: [JwtAuthModule],
  providers: [PubsubBridge, WsAuthGuard, WsValidationPipe, WsGateway],
  exports: [PubsubBridge, WsGateway, WsValidationPipe],
})
export class WsModule {}
