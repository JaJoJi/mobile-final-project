import { Module } from '@nestjs/common';
import { PubsubBridge } from './pubsub.bridge';

/**
 * Owns the shared Redis Pub/Sub bridge without depending on the WebSocket
 * gateway. Keeping this provider in a small module lets domain modules publish
 * events while WsModule imports those domains for its incoming handlers,
 * without creating circular module imports.
 */
@Module({
  providers: [PubsubBridge],
  exports: [PubsubBridge],
})
export class PubsubModule {}
