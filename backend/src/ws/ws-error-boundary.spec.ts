import { BadRequestException, HttpException, HttpStatus } from '@nestjs/common';
import { WsException } from '@nestjs/websockets';
import { toGameError } from './ws-exception.filter';

describe('toGameError matrix (#308)', () => {
  // Comment-only note: every case below asserts the masking rule — only an
  // explicit `code` field survives; raw messages with secrets never do.
  it('passes domain codes through and keeps clientActionId', () => {
    expect(
      toGameError(
        new BadRequestException({ code: 'shop.insufficient_gold', message: 'broke' }),
        'shop.buy_failed',
        'act-1',
      ),
    ).toEqual({
      code: 'shop.insufficient_gold',
      message: 'broke',
      clientActionId: 'act-1',
    });
  });

  it('uses the fallback code for uncoded HttpExceptions', () => {
    expect(toGameError(new BadRequestException('plain'))).toEqual({
      code: 'internal',
      message: 'unexpected error',
    });
  });

  it('masks string HttpException responses as internal (no uncoded passthrough)', () => {
    const err = new HttpException('upstream says no', HttpStatus.BAD_GATEWAY);
    expect(toGameError(err, 'match.failed')).toEqual({
      code: 'internal',
      message: 'unexpected error',
    });
  });

  it('unwraps WsException string errors with the fallback code', () => {
    expect(toGameError(new WsException('rate.limited'), 'internal')).toEqual({
      code: 'internal',
      message: 'unexpected error',
    });
  });

  it('masks Error and unknown throws as internal without details', () => {
    expect(toGameError(new Error('postgres://user:pass@host/db'))).toEqual({
      code: 'internal',
      message: 'unexpected error',
    });
    expect(toGameError(42, 'fallback')).toEqual({ code: 'fallback', message: 'fallback' });
    expect(toGameError(null)).toEqual({ code: 'internal', message: 'unexpected error' });
  });

  it('omits clientActionId when the payload carries none', () => {
    const envelope = toGameError(
      new WsException({ code: 'invalid_payload', message: 'bad' }),
      'internal',
      undefined,
    );
    expect(envelope).toEqual({ code: 'invalid_payload', message: 'bad' });
    expect('clientActionId' in envelope).toBe(false);
  });
});
