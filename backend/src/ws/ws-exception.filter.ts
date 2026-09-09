import { ArgumentsHost, Catch, ExceptionFilter, HttpException, Logger } from '@nestjs/common';
import { WsException } from '@nestjs/websockets';
import type { Socket } from 'socket.io';

export interface GameErrorEnvelope {
  code: string;
  message: string;
  clientActionId?: string;
}

/** Converts pipe, Nest domain, and unexpected failures to the frozen WS shape. */
@Catch()
export class WsGameExceptionFilter implements ExceptionFilter {
  private readonly logger = new Logger(WsGameExceptionFilter.name);

  catch(exception: unknown, host: ArgumentsHost): void {
    const ws = host.switchToWs();
    const client = ws.getClient<Socket>();
    const data = ws.getData<{ clientActionId?: unknown } | undefined>();
    const clientActionId = typeof data?.clientActionId === 'string'
      ? data.clientActionId
      : undefined;
    const envelope = toGameError(exception, 'internal', clientActionId);
    if (envelope.code === 'internal') {
      this.logger.error(
        `Unhandled WS error: ${exception instanceof Error ? exception.stack : String(exception)}`,
      );
    }
    client.emit('game:error', envelope);
  }
}

export function toGameError(
  exception: unknown,
  fallbackCode = 'internal',
  clientActionId?: string,
): GameErrorEnvelope {
  let value: unknown = exception;
  if (exception instanceof WsException) value = exception.getError();
  if (exception instanceof HttpException) value = exception.getResponse();

  const record = isRecord(value) ? value : null;
  const explicitCode = typeof record?.code === 'string' ? record.code : null;
  const code = explicitCode ?? (exception instanceof Error ? 'internal' : fallbackCode);
  const domainMessage = typeof record?.message === 'string'
    ? record.message
    : exception instanceof Error
      ? exception.message
      : typeof value === 'string'
        ? value
        : '';
  const message = code === 'internal' ? 'unexpected error' : domainMessage || code;
  return {
    code,
    message,
    ...(clientActionId ? { clientActionId } : {}),
  };
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}
