import { WsException } from '@nestjs/websockets';
import { MatchmakingJoinDto, ShopBuyDto } from './ws.dto';
import { WsValidationPipe } from './ws.pipes';

const pipe = new WsValidationPipe();
const meta = (metatype: unknown) => ({ metatype, type: 'body' }) as any;

async function rejectWith(value: unknown, metatype: unknown): Promise<{ code: unknown }> {
  const err = await pipe.transform(value, meta(metatype)).then(
    () => {
      throw new Error('should have rejected');
    },
    (e) => e,
  );
  expect(err).toBeInstanceOf(WsException);
  return err.getError() as { code: unknown };
}

describe('WsValidationPipe (#308)', () => {
  it('passes primitives and untyped payloads through untouched', async () => {
    await expect(pipe.transform('raw', meta(String))).resolves.toBe('raw');
    await expect(pipe.transform(42, meta(Number))).resolves.toBe(42);
    await expect(pipe.transform({ a: 1 }, meta(Object))).resolves.toEqual({ a: 1 });
    await expect(pipe.transform({ a: 1 }, meta(undefined))).resolves.toEqual({ a: 1 });
  });

  it('accepts empty matchmaking DTOs', async () => {
    const out = await pipe.transform({}, meta(MatchmakingJoinDto));
    expect(out).toBeInstanceOf(MatchmakingJoinDto);
  });

  it('accepts a valid shop payload as a DTO instance', async () => {
    const out = (await pipe.transform(
      { round: 2, offerIndex: 3, clientActionId: '11111111-1111-4111-8111-111111111111' },
      meta(ShopBuyDto),
    )) as ShopBuyDto;
    expect(out).toBeInstanceOf(ShopBuyDto);
    expect(out.round).toBe(2);
  });

  it('rejects null/array payloads and out-of-range fields', async () => {
    for (const bad of [null, 'buy', [{ round: 1 }]]) {
      await expect(rejectWith(bad, ShopBuyDto)).resolves.toMatchObject({
        code: 'invalid_payload',
      });
    }
    await expect(
      rejectWith({ round: 0, offerIndex: 9, clientActionId: 'not-a-uuid' }, ShopBuyDto),
    ).resolves.toMatchObject({ code: 'invalid_payload' });
    await expect(
      rejectWith({ round: 1, offerIndex: 0 }, ShopBuyDto),
    ).resolves.toMatchObject({ code: 'invalid_payload' });
  });

  it('strips undeclared fields instead of forwarding them', async () => {
    const out = (await pipe.transform(
      {
        round: 1,
        offerIndex: 0,
        clientActionId: '11111111-1111-4111-8111-111111111111',
        smuggled: 'DROP TABLE matches',
      },
      meta(ShopBuyDto),
    )) as Record<string, unknown>;
    expect(out.smuggled).toBeUndefined();
    expect(out.round).toBe(1);
  });
});
