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
        customProps: (req: IncomingMessage & { id?: string }) => ({
          requestId: req.id,
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

        // Human-readable only when NODE_ENV=development; raw JSON
        // everywhere else (Promtail -> Loki, #138).
        transport: usePretty
          ? {
              target: 'pino-pretty',
              options: { singleLine: true, translateTime: 'SYS:standard' },
            }
          : undefined,
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
