/**
 * OpenTelemetry traces (#225): every HTTP request becomes a trace with
 * child spans for the Nest handler, Postgres queries and Redis commands,
 * exported over OTLP/HTTP to Tempo. The pino instrumentation stamps
 * trace_id / span_id on every log line, so Grafana can jump from a Loki
 * log line to its trace.
 *
 * Opt-in: does nothing unless OTEL_EXPORTER_OTLP_ENDPOINT is set (the
 * production compose sets it), so unit tests, CI smoke runs and local
 * dev never try to reach a collector.
 *
 * Must be imported before anything it instruments is loaded -- it is the
 * first import in main.ts, ahead of @nestjs/core, pg and ioredis.
 *
 * Only the instrumentations this app needs are loaded (not the
 * auto-instrumentations meta-package, which pulls in ~40 libraries).
 */
import { NodeSDK } from '@opentelemetry/sdk-node';
import { OTLPTraceExporter } from '@opentelemetry/exporter-trace-otlp-http';
import { resourceFromAttributes } from '@opentelemetry/resources';
import { ATTR_SERVICE_NAME } from '@opentelemetry/semantic-conventions';
import { HttpInstrumentation } from '@opentelemetry/instrumentation-http';
import { ExpressInstrumentation } from '@opentelemetry/instrumentation-express';
import { NestInstrumentation } from '@opentelemetry/instrumentation-nestjs-core';
import { PgInstrumentation } from '@opentelemetry/instrumentation-pg';
import { IORedisInstrumentation } from '@opentelemetry/instrumentation-ioredis';
import { PinoInstrumentation } from '@opentelemetry/instrumentation-pino';

const endpoint = process.env.OTEL_EXPORTER_OTLP_ENDPOINT;

if (endpoint) {
  const sdk = new NodeSDK({
    resource: resourceFromAttributes({
      [ATTR_SERVICE_NAME]: process.env.OTEL_SERVICE_NAME ?? 'auto-chess-backend',
      'service.instance.id': process.env.HOSTNAME ?? 'local',
    }),
    // Batched export (the SDK default for a trace exporter): one request
    // produces several spans; one POST per span would be wasteful.
    traceExporter: new OTLPTraceExporter({ url: `${endpoint}/v1/traces` }),
    instrumentations: [
      new HttpInstrumentation({
        // Health probes run every few seconds; tracing them is noise.
        ignoreIncomingRequestHook: (req) => (req.url ?? '').startsWith('/health'),
      }),
      new ExpressInstrumentation(),
      new NestInstrumentation(),
      new PgInstrumentation(),
      new IORedisInstrumentation(),
      new PinoInstrumentation(),
    ],
  });

  sdk.start();

  const shutdown = () => {
    sdk.shutdown().finally(() => process.exit(0));
  };
  process.once('SIGTERM', shutdown);
  process.once('SIGINT', shutdown);
}
