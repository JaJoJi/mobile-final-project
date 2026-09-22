/**
 * P3-DO-21 (revised) — real OTel SDK, replacing the Beyla-traceparent
 * plan. That plan assumed Beyla injects a `traceparent` header into
 * inbound requests the app could read — verified false, three ways,
 * including the full nginx->backend topology with propagation enabled
 * on both hops (see the old trace-context.middleware.ts, removed in
 * this change, for the full writeup). This SDK generates trace context
 * itself, so there's no "does the header arrive" question: every
 * incoming request gets a real span, and the active span's trace id is
 * available directly to app code (see logger.module.ts's customProps).
 *
 * Must run before anything it instruments is `require`d — imported as
 * the very first line of main.ts, before @nestjs/core.
 *
 * Beyla stays on nest-1/2/3 for metrics only (OTEL_TRACES_EXPORTER=none
 * on those Beyla instances, verified live: Prometheus scrape keeps
 * working, zero attempt to reach an OTLP endpoint) — two trace
 * producers for the same requests would double up in Tempo otherwise.
 * nginx keeps Beyla as-is (no SDK option there).
 */
import { NodeSDK } from '@opentelemetry/sdk-node';
import { getNodeAutoInstrumentations } from '@opentelemetry/auto-instrumentations-node';
import { OTLPTraceExporter } from '@opentelemetry/exporter-trace-otlp-http';
import { resourceFromAttributes } from '@opentelemetry/resources';
import { ATTR_SERVICE_NAME } from '@opentelemetry/semantic-conventions';

const sdk = new NodeSDK({
  resource: resourceFromAttributes({
    [ATTR_SERVICE_NAME]: 'auto-chess-backend',
  }),
  // Batched (not Simple/synchronous) — verified live that a single
  // request produces ~9 child spans (DNS, TCP connect, DB/Redis calls);
  // one HTTP POST per span to Tempo would be wasteful at real traffic.
  traceExporter: new OTLPTraceExporter({
    url: `${process.env.OTEL_EXPORTER_OTLP_ENDPOINT ?? 'http://tempo:4318'}/v1/traces`,
  }),
  instrumentations: [
    getNodeAutoInstrumentations({
      // Filesystem instrumentation is noisy (every require()) and not
      // useful for this app's actual bottlenecks (DB/Redis/HTTP).
      '@opentelemetry/instrumentation-fs': { enabled: false },
    }),
  ],
});

sdk.start();

process.on('SIGTERM', () => {
  sdk.shutdown().finally(() => process.exit(0));
});
