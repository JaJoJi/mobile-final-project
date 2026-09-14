import {
  ArgumentsHost,
  BadRequestException,
  HttpException,
  HttpStatus,
  NotFoundException,
} from '@nestjs/common';
import { HttpAdapterHost } from '@nestjs/core';
import { AllExceptionsFilter } from './all-exceptions.filter';

function makeFilter() {
  const replies: Array<{ body: unknown; status: number }> = [];
  const headers: Record<string, string> = {};
  const httpAdapter = {
    reply: (_res: unknown, body: unknown, status: number) =>
      replies.push({ body, status }),
    getRequestUrl: () => '/x',
  };
  const logger = {
    setContext: jest.fn(),
    error: jest.fn(),
    warn: jest.fn(),
  };
  const filter = new AllExceptionsFilter(
    { httpAdapter } as unknown as HttpAdapterHost,
    logger as never,
  );
  const res = { setHeader: (k: string, v: string) => (headers[k] = v) };
  return { filter, replies, headers, logger, res };
}

function httpHost(res: unknown): ArgumentsHost {
  return {
    getType: () => 'http',
    switchToHttp: () => ({ getRequest: () => ({}), getResponse: () => res }),
  } as unknown as ArgumentsHost;
}

function wsHost(): ArgumentsHost {
  return { getType: () => 'ws' } as unknown as ArgumentsHost;
}

describe('AllExceptionsFilter (P1-BE-01)', () => {
  it('normalises a plain HttpException to { code, message }', () => {
    const { filter, replies } = makeFilter();
    filter.catch(new NotFoundException('no such match'), httpHost({}));
    expect(replies[0].status).toBe(404);
    expect(replies[0].body).toEqual({ code: 'not_found', message: 'no such match' });
  });

  it('keeps an explicit domain code + details from the thrown response', () => {
    const { filter, replies } = makeFilter();
    filter.catch(
      new BadRequestException({
        code: 'shop.insufficient_gold',
        message: 'need 3 more gold',
        details: { have: 2, need: 5 },
      }),
      httpHost({}),
    );
    expect(replies[0].body).toEqual({
      code: 'shop.insufficient_gold',
      message: 'need 3 more gold',
      details: { have: 2, need: 5 },
    });
  });

  it('adds retryAfter + Retry-After header on 429', () => {
    const { filter, replies, headers } = makeFilter();
    filter.catch(
      new HttpException(
        { code: 'rate_limited', message: 'slow down', retryAfter: 7 },
        HttpStatus.TOO_MANY_REQUESTS,
      ),
      httpHost({ setHeader: (k: string, v: string) => (headers[k] = v) }),
    );
    expect(replies[0].status).toBe(429);
    expect(replies[0].body).toMatchObject({
      code: 'rate_limited',
      message: 'slow down',
      retryAfter: 7,
    });
    expect(headers['Retry-After']).toBe('7');
  });

  it('masks an unknown error as 500 { code: internal } and logs it', () => {
    const { filter, replies, logger } = makeFilter();
    filter.catch(new Error('DATABASE_URL=postgres://user:pw@host'), httpHost({}));
    expect(replies[0].status).toBe(500);
    expect(replies[0].body).toEqual({
      code: 'internal',
      message: 'internal server error',
    });
    expect(logger.error).toHaveBeenCalled();
    expect(logger.warn).not.toHaveBeenCalled();
  });

  it('re-throws for non-http (WS) contexts so the WS filter handles them', () => {
    const { filter } = makeFilter();
    const boom = new Error('ws land');
    expect(() => filter.catch(boom, wsHost())).toThrow(boom);
  });
});
