/**
 * Smoke harness for P0-BE-08 (WS payload DTOs + validation pipe).
 *
 * Pure — no Redis / DB / socket. Runs `WsValidationPipe.transform`
 * against a table of good and bad payloads and asserts the outcome,
 * proving the "Done when" checks on the ticket:
 *   - bad payload  → WsException { code: 'invalid_payload' } before any handler
 *   - good payload → returns the DTO instance, unknown fields stripped
 *
 * Run:
 *   cd backend && npx ts-node -T src/ws/ws.dto.smoke.ts
 */
import { WsException } from '@nestjs/websockets';
import type { ArgumentMetadata } from '@nestjs/common';
import {
  MatchCombatDoneDto,
  MatchPlaceDto,
  MatchReadyDto,
  MatchmakingJoinDto,
  MatchmakingLeaveDto,
  ShopBuyDto,
  ShopFuseDto,
  ShopRefreshDto,
  ShopSellDto,
} from './ws.dto';
import { WsValidationPipe } from './ws.pipes';

const pipe = new WsValidationPipe();
const meta = (metatype: unknown): ArgumentMetadata =>
  ({ type: 'body', metatype: metatype as ArgumentMetadata['metatype'], data: undefined });

const UUID = '11111111-1111-4111-8111-111111111111';

interface Case {
  name: string;
  dto: unknown;
  payload: unknown;
  expect: 'pass' | 'fail';
}

const cases: Case[] = [
  // --- valid ---
  { name: 'shop:buy valid', dto: ShopBuyDto, expect: 'pass',
    payload: { round: 3, offerIndex: 4, clientActionId: UUID } },
  { name: 'shop:sell valid (board)', dto: ShopSellDto, expect: 'pass',
    payload: { round: 1, source: 'board', slot: 8, clientActionId: UUID } },
  { name: 'shop:fuse valid', dto: ShopFuseDto, expect: 'pass',
    payload: { round: 2, unitId: 'ranger', clientActionId: UUID } },
  { name: 'match:place valid', dto: MatchPlaceDto, expect: 'pass',
    payload: { round: 1, unitInstanceId: UUID, target: 'bench', slot: 0, clientActionId: UUID } },
  { name: 'match:ready valid', dto: MatchReadyDto, expect: 'pass',
    payload: { round: 5, clientActionId: UUID } },
  { name: 'match:ready cancel valid', dto: MatchReadyDto, expect: 'pass',
    payload: { round: 5, ready: false, clientActionId: UUID } },
  { name: 'match:combat_done valid', dto: MatchCombatDoneDto, expect: 'pass',
    payload: { matchId: UUID, round: 5, clientActionId: UUID } },
  { name: 'matchmaking:join empty', dto: MatchmakingJoinDto, expect: 'pass', payload: {} },
  { name: 'matchmaking:join undefined body', dto: MatchmakingJoinDto, expect: 'pass', payload: undefined },
  { name: 'matchmaking:leave empty', dto: MatchmakingLeaveDto, expect: 'pass', payload: {} },
  { name: 'shop:refresh valid', dto: ShopRefreshDto, expect: 'pass',
    payload: { round: 4, clientActionId: UUID } },
  // P1-BE-02 acceptance: a valid buy still passes the door.
  { name: 'shop:buy valid (round 1, offerIndex 0)', dto: ShopBuyDto, expect: 'pass',
    payload: { round: 1, offerIndex: 0, clientActionId: UUID } },

  // --- invalid ---
  { name: 'shop:buy round is string', dto: ShopBuyDto, expect: 'fail',
    payload: { round: 'three', offerIndex: 1, clientActionId: UUID } },
  { name: 'shop:buy offerIndex out of range', dto: ShopBuyDto, expect: 'fail',
    payload: { round: 1, offerIndex: 5, clientActionId: UUID } },
  // P1-BE-02 acceptance: `{ round: 99, offerIndex: 100 }` — rejected on
  // offerIndex (round has no static upper bound by design; the
  // round-matches-server check is stateful, P0-BE-10..14).
  { name: 'shop:buy offerIndex 100', dto: ShopBuyDto, expect: 'fail',
    payload: { round: 99, offerIndex: 100, clientActionId: UUID } },
  { name: 'shop:buy missing clientActionId', dto: ShopBuyDto, expect: 'fail',
    payload: { round: 1, offerIndex: 0 } },
  { name: 'shop:buy clientActionId not a uuid', dto: ShopBuyDto, expect: 'fail',
    payload: { round: 1, offerIndex: 0, clientActionId: 'nope' } },
  { name: 'shop:sell bad source enum', dto: ShopSellDto, expect: 'fail',
    payload: { round: 1, source: 'graveyard', slot: 0, clientActionId: UUID } },
  { name: 'shop:sell slot out of range', dto: ShopSellDto, expect: 'fail',
    payload: { round: 1, source: 'bench', slot: 9, clientActionId: UUID } },
  { name: 'shop:fuse bad unitId', dto: ShopFuseDto, expect: 'fail',
    payload: { round: 1, unitId: 'wizard', clientActionId: UUID } },
  { name: 'match:place round below 1', dto: MatchPlaceDto, expect: 'fail',
    payload: { round: 0, unitInstanceId: UUID, target: 'board', slot: 0, clientActionId: UUID } },
  { name: 'shop:refresh payload is an array', dto: ShopRefreshDto, expect: 'fail', payload: [1, 2, 3] },
];

async function checkExtraFieldStripped(): Promise<void> {
  const out = (await pipe.transform(
    { round: 1, offerIndex: 0, clientActionId: UUID, hax: 'x', gold: 9999 },
    meta(ShopBuyDto),
  )) as Record<string, unknown>;
  if ('hax' in out || 'gold' in out) {
    throw new Error(`whitelist failed — unknown fields survived: ${JSON.stringify(out)}`);
  }
  if (!(out instanceof ShopBuyDto)) {
    throw new Error('transform did not return a ShopBuyDto instance');
  }
  console.log('[strip] unknown fields (hax, gold) removed, instance is ShopBuyDto');
}

async function run(): Promise<void> {
  let failed = 0;

  for (const c of cases) {
    let outcome: 'pass' | 'fail';
    let detail = '';
    try {
      await pipe.transform(c.payload, meta(c.dto));
      outcome = 'pass';
    } catch (e) {
      outcome = 'fail';
      if (e instanceof WsException) {
        const err = e.getError();
        detail = typeof err === 'object' ? JSON.stringify(err) : String(err);
        if (typeof err === 'object' && (err as { code?: string }).code !== 'invalid_payload') {
          console.error(`  ! ${c.name}: wrong error code ${detail}`);
          failed++;
        }
      } else {
        console.error(`  ! ${c.name}: threw non-WsException ${String(e)}`);
        failed++;
      }
    }
    const ok = outcome === c.expect;
    if (!ok) failed++;
    console.log(`  ${ok ? 'OK  ' : 'FAIL'} ${c.name.padEnd(38)} → ${outcome}${detail ? '  ' + detail : ''}`);
  }

  await checkExtraFieldStripped();

  if (failed > 0) {
    throw new Error(`${failed} smoke check(s) failed`);
  }
  console.log(`\n[OK] ${cases.length} payload cases + whitelist check passed`);
}

run().catch((err) => {
  console.error('[FAIL]', err);
  process.exit(1);
});
