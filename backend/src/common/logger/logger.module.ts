import { randomUUID } from 'crypto';
import { IncomingMessage, ServerResponse } from 'http';
import { Module, RequestMethod } from '@nestjs/common';
import { LoggerModule as PinoLoggerModule } from 'nestjs-pino';

/**
 * Structured logging — P1-BE-01 (#113), NFR-8.
 *
 * Wraps `nestjs-pino` so every log line is JSON with a stable shape:
 *   { level, time, msg, requestId?, instanceId, pid, context?, ... }
 *
 * `main.ts` calls `app.useLogger(app.get(Logger))` from nestjs-pino, so
 * the existing `new Logger(ctx)` / `Logger.log(...)` calls scattered
 * across the services keep working and now emit through pino — no
 * per-file rewrite needed. New code can inject `PinoLogger` for the
 * structured `logger.info({ matchId }, 'msg')` form.
 *
 * Log levels (the convention from the ticket):
 *   error  — unhandled exceptions (AllExceptionsFilter, WS filter)
 *   warn   — handled `game:error` / 4xx responses
 *   info   — lifecycle + phase transitions
 *   debug  — everything else (LOG_LEVEL=debug to see it)
 */

const isProd = process.env.NODE_ENV === 'production';
// pino-pretty is a devDependency and a worker thread — only opt in when
// explicitly developing locally, so `test` / prod / an unset NODE_ENV all
// emit raw JSON and never need the module resolvable.
const usePretty = process.env.NODE_ENV === 'development';

// P3-DO-21 — pino-loki pushes directly to Loki (no Promtail agent for
// app logs — only nginx's ModSecurity log needs one, see
// promtail/promtail.yml). `pino/file` with destination 1 keeps stdout
// output alongside it: mtail (mtail/pino.mtail) still reads stdout via
// Docker's json-file log driver, so replacing stdout with a single
// Loki-only transport would silently break mtail's counters — verified
// both targets fire from the same logger before wiring this in.
const lokiTransportTarget = {
  targets: [
    { target: 'pino/file', options: { destination: 1 }, level: 'trace' },
    {
      target: 'pino-loki',
      options: {
        host: process.env.LOKI_URL ?? 'http://loki:3100',
        labels: { app: 'auto-chess-backend' },
        // Found live: pino-loki@3.0.0's default batching (multiple
        // streams in one push) sent Loki a malformed body — Loki
        // rejected every batch with "unmarshalerDecoder: Value looks
        // like Number/Boolean/None, but can't find its end" and
        // silently dropped all those logs. One HTTP push per line
        // costs more requests but was the config that actually got
        // logs into Loki when tested for real; revisit if pino-loki
        // fixes batch serialization in a later version.
        batching: false,
      },
      level: 'trace',
    },
  ],
};

@Module({
  imports: [
    PinoLoggerModule.forRoot({
      pinoHttp: {
        level: process.env.LOG_LEVEL ?? (isProd ? 'info' : 'debug'),

        // Fields on every line.
        base: {
          instanceId: process.env.HOSTNAME ?? 'local',
          pid: process.pid,
        },
        timestamp: () => `,"time":"${new Date().toISOString()}"`,
        messageKey: 'msg',

        // One id per HTTP request, surfaced as `requestId` and echoed
        // back in the `x-request-id` response header.
        genReqId: (req: IncomingMessage, res: ServerResponse) => {
          const existing =
            (req.headers['x-request-id'] as string | undefined) ?? randomUUID();
          res.setHeader('x-request-id', existing);
          return existing;
        },
        customProps: (req: IncomingMessage & { id?: string; traceId?: string }) => ({
          requestId: req.id,
          // P3-DO-21 — would be set by traceContextMiddleware from
          // Beyla's traceparent header. Verified Beyla doesn't actually
          // send that header today (see that file's header comment) —
          // req.traceId is always undefined in practice right now, so
          // this omits trace_id from every log line. Left wired in case
          // that changes.
          ...(req.traceId ? { trace_id: req.traceId } : {}),
        }),

        // 5xx -> error, 4xx -> warn, everything else -> info.
        customLogLevel: (_req, res: ServerResponse, err?: Error) => {
          if (err || res.statusCode >= 500) return 'error';
          if (res.statusCode >= 400) return 'warn';
          return 'info';
        },

        // Never log credentials / tokens.
        redact: {
          paths: [
            'req.headers.authorization',
            'req.headers.cookie',
            'req.body.password',
            'req.body.accessToken',
            'req.body.refreshToken',
            '*.password',
            '*.accessToken',
            '*.refreshToken',
          ],
          censor: '[redacted]',
        },

        // Human-readable only when NODE_ENV=development; raw JSON to
        // stdout (mtail) + pino-loki (Loki, full-text search) everywhere
        // else — see lokiTransportTarget above (P3-DO-21; supersedes the
        // stale "Promtail -> Loki, #138" this comment used to say —
        // Promtail only handles nginx's ModSecurity log now, not this one).
        transport: usePretty
          ? {
              target: 'pino-pretty',
              options: { singleLine: true, translateTime: 'SYS:standard' },
            }
          : isProd
            ? lokiTransportTarget
            : undefined, // test / unset NODE_ENV: plain stdout, no Loki dependency
      },
      // Health checks are noise — one per few seconds per instance.
      exclude: [
        { method: RequestMethod.ALL, path: 'health' },
        { method: RequestMethod.ALL, path: 'health/(.*)' },
      ],
    }),
  ],
})
export class LoggerModule {}
