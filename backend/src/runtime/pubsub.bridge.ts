import { Injectable, Logger } from '@nestjs/common';

/**
 * Cross-instance Pub/Sub bridge for game events.
 *
 * This is a NO-OP STUB created in P0-BE-04 so `WsGateway` can already
 * inject a `PubsubBridge` and call `publish()` / `subscribe()` without
 * breaking the boot. The real implementation (Redis Pub/Sub + adapter,
 * fan-out to every Nest instance's connected sockets) lands in P0-BE-05
 * — only the body of this file changes there.
 *
 * Why a real class instead of a mock: P0-BE-05 is the next ticket in
 * the dependency chain, so we want the import path
 * (`../runtime/pubsub.bridge`) and the public surface (`publish`,
 * `subscribe`) to already be in place. Swapping in a working
 * implementation later is a single-file edit with zero ripple.
 *
 * Lifecycle:
 *   - `publish(channel, payload)` — fan-out an event to every Nest
 *     instance's WS gateway. Stub: logs and returns.
 *   - `subscribe(channel, handler)` — register a local handler for
 *     messages received from the bus. Stub: no-op; returns an
 *     unsubscribe function that does nothing.
 */
@Injectable()
export class PubsubBridge {
  private readonly logger = new Logger(PubsubBridge.name);

  constructor() {
    this.logger.warn(
      'PubsubBridge stub active — cross-instance fan-out is disabled. ' +
        'Replace this body in P0-BE-05.',
    );
  }

  publish(channel: string, payload: unknown): void {
    this.logger.debug(`[stub publish] channel=${channel} payload=${JSON.stringify(payload)}`);
  }

  subscribe(_channel: string, _handler: (payload: unknown) => void): () => void {
    return () => {
      /* no-op: nothing to unsubscribe from in the stub */
    };
  }
}
