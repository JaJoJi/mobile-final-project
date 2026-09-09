import {
  ArgumentsHost,
  Catch,
  ExceptionFilter,
  HttpException,
  HttpStatus,
} from '@nestjs/common';
import { HttpAdapterHost } from '@nestjs/core';
import { PinoLogger } from 'nestjs-pino';

/**
 * Global REST exception filter — P1-BE-01 (#113), NFR-7.
 *
 * Every 4xx / 5xx response body is normalised to:
 *   { code: string, message: string, details?: unknown }
 * A 429 additionally carries `retryAfter` (seconds).
 *
 * WS exceptions are left alone — `WsGameExceptionFilter` owns that path
 * and emits `game:error`. This filter only touches the `http` context.
 */
@Catch()
export class AllExceptionsFilter implements ExceptionFilter {
  constructor(
    private readonly httpAdapterHost: HttpAdapterHost,
    private readonly logger: PinoLogger,
  ) {
    this.logger.setContext(AllExceptionsFilter.name);
  }

  catch(exception: unknown, host: ArgumentsHost): void {
    if (host.getType() !== 'http') {
      // Not an HTTP request — re-throw so the WS filter (or the default)
      // handles it.
      throw exception;
    }

    const { httpAdapter } = this.httpAdapterHost;
    const ctx = host.switchToHttp();
    const req = ctx.getRequest();
    const res = ctx.getResponse();

    const status =
      exception instanceof HttpException
        ? exception.getStatus()
        : HttpStatus.INTERNAL_SERVER_ERROR;

    const body = this.toEnvelope(exception, status);

    if (status >= 500) {
      this.logger.error(
        { err: exception, path: httpAdapter.getRequestUrl(req), statusCode: status },
        'unhandled exception',
      );
    } else {
      this.logger.warn(
        { code: body.code, path: httpAdapter.getRequestUrl(req), statusCode: status },
        body.message,
      );
    }

    if (status === HttpStatus.TOO_MANY_REQUESTS && body.retryAfter != null) {
      res.setHeader?.('Retry-After', String(body.retryAfter));
    }

    httpAdapter.reply(res, body, status);
  }

  private toEnvelope(
    exception: unknown,
    status: number,
  ): { code: string; message: string; details?: unknown; retryAfter?: number } {
    if (exception instanceof HttpException) {
      const raw = exception.getResponse();
      const rec =
        typeof raw === 'object' && raw !== null
          ? (raw as Record<string, unknown>)
          : {};

      const code =
        typeof rec.code === 'string' ? rec.code : codeForStatus(status);
      const message =
        typeof rec.message === 'string'
          ? rec.message
          : Array.isArray(rec.message)
            ? String(rec.message[0])
            : typeof raw === 'string'
              ? raw
              : exception.message || codeForStatus(status);

      const out: {
        code: string;
        message: string;
        details?: unknown;
        retryAfter?: number;
      } = { code, message };

      if (rec.details !== undefined) out.details = rec.details;
      if (status === HttpStatus.TOO_MANY_REQUESTS) {
        out.retryAfter =
          typeof rec.retryAfter === 'number'
            ? rec.retryAfter
            : Number(process.env.RATE_LIMIT_RETRY_AFTER ?? 1);
      }
      return out;
    }

    // Unknown / programmer error — never leak internals to the client.
    return { code: 'internal', message: 'internal server error' };
  }
}

function codeForStatus(status: number): string {
  const map: Record<number, string> = {
    [HttpStatus.BAD_REQUEST]: 'bad_request',
    [HttpStatus.UNAUTHORIZED]: 'unauthorized',
    [HttpStatus.FORBIDDEN]: 'forbidden',
    [HttpStatus.NOT_FOUND]: 'not_found',
    [HttpStatus.CONFLICT]: 'conflict',
    [HttpStatus.UNPROCESSABLE_ENTITY]: 'unprocessable_entity',
    [HttpStatus.TOO_MANY_REQUESTS]: 'rate_limited',
  };
  return map[status] ?? (status >= 500 ? 'internal' : 'error');
}
