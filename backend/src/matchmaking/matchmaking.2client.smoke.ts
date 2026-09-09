/**
 * Two-client matchmaking smoke for P0-BE-11 + P0-BE-10 (orchestrator).
 *
 * Proves end-to-end that two authenticated clients, both emitting
 * `game:matchmaking:join` within milliseconds of each other, are paired
 * together by the BullMQ match-pair worker + `match_pair.lua` and each
 * receive the same `game:match:phase` payload.
 *
 * Runs against the live stack:
 *   - nginx on host:80 → 3 Nest replicas (any one handles each socket)
 *   - real Redis (ZADD/ZREM via `match_pair.lua`)
 *   - real Postgres (Match row inserted by the orchestrator)
 *   - real Pub/Sub fan-out (every replica forwards the phase event)
 *
 * Run inside the docker network while nest-1 + redis + postgres-primary
 * are up:
 *   docker compose exec -T nest-1 npm run smoke:matchmaking-2client
 * Or from a host with the gateway reachable:
 *   HTTP_BASE=http://localhost \
 *     npx ts-node -T src/matchmaking/matchmaking.2client.smoke.ts
 */
import 'reflect-metadata';
import { randomUUID } from 'crypto';
import { io, Socket } from 'socket.io-client';
import { DataSource } from 'typeorm';
import { ENTITIES } from '../database/entities';
import { RedisService } from '../redis/redis.service';
import { Match } from '../match/match.entity';
import { MATCHMAKING_QUEUE_KEY } from './matchmaking.service';

interface AuthResponse {
  userId: string;
  accessToken: string;
  refreshToken: string;
}

interface PhasePayload {
  matchId: string;
  phase: string;
  round: number;
  timer: number;
  players: Array<{ id: string; hp: number; gold: number; ready: boolean }>;
}

interface TestResult {
  name: string;
  passed: boolean;
  detail: string;
}

const HTTP_BASE = process.env.HTTP_BASE ?? 'http://localhost:80';
const REDIS_URL = process.env.REDIS_URL ?? 'redis://localhost:6379';
const DATABASE_URL =
  process.env.DATABASE_URL ?? 'postgres://postgres:postgres@localhost:5432/auto_chess';
const TIMEOUT_MS = 5000;

async function http<T>(path: string, init: RequestInit = {}): Promise<T> {
  const res = await fetch(`${HTTP_BASE}${path}`, {
    ...init,
    headers: { 'content-type': 'application/json', ...(init.headers ?? {}) },
  });
  if (!res.ok) {
    const text = await res.text().catch(() => '');
    throw new Error(`HTTP ${res.status} ${res.statusText} on ${path}: ${text}`);
  }
  return (await res.json()) as T;
}

function record(results: TestResult[], name: string, passed: boolean, detail: string): void {
  results.push({ name, passed, detail });
}

async function once<T>(socket: Socket, event: string, timeoutMs: number): Promise<T> {
  return new Promise<T>((resolve, reject) => {
    const timer = setTimeout(
      () => reject(new Error(`timeout waiting for '${event}' (${timeoutMs}ms)`)),
      timeoutMs,
    );
    socket.once(event, (payload: T) => {
      clearTimeout(timer);
      resolve(payload);
    });
  });
}

async function run(): Promise<void> {
  console.log(`[connect] HTTP=${HTTP_BASE} REDIS=${REDIS_URL}`);
  console.log('[connect] PG=' + DATABASE_URL.replace(/:[^:@]+@/, ':***@'));

  // 1. Register two throwaway users so we get real, fresh JWTs.
  const stamp = Date.now();
  const aliceAuth = await http<AuthResponse>('/auth/register', {
    method: 'POST',
    body: JSON.stringify({
      email: `alice-${stamp}@e2e.test`,
      username: `alice${stamp}`,
      password: 'hunter22-long-enough',
    }),
  });
  const bobAuth = await http<AuthResponse>('/auth/register', {
    method: 'POST',
    body: JSON.stringify({
      email: `bob-${stamp}@e2e.test`,
      username: `bob${stamp}`,
      password: 'hunter22-long-enough',
    }),
  });
  console.log(
    `[register] alice=${aliceAuth.userId.slice(0, 8)}…  bob=${bobAuth.userId.slice(0, 8)}…`,
  );

  // 2. Open two socket.io-client connections to the live gateway, on
  //    the `/game` namespace (matches NestJS `@WebSocketGateway({...})`).
  //    transports: ['websocket'] mirrors the Flutter socket_io_client
  //    default and skips the polling handshake so we exercise the same
  //    WS path the lobby uses.
  const NAMESPACE = '/game';
  const sockA: Socket = io(`${HTTP_BASE}${NAMESPACE}`, {
    transports: ['websocket'],
    reconnection: false,
    auth: { token: aliceAuth.accessToken },
  });
  const sockB: Socket = io(`${HTTP_BASE}${NAMESPACE}`, {
    transports: ['websocket'],
    reconnection: false,
    auth: { token: bobAuth.accessToken },
  });

  const results: TestResult[] = [];

  try {
    // 3. Wait for both to connect — proves JWT auth works for 2 clients
    //    against the live stack.
    await Promise.all([once<unknown>(sockA, 'connect', TIMEOUT_MS)]);
    await Promise.all([once<unknown>(sockB, 'connect', TIMEOUT_MS)]);

    // 4. Both emit matchmaking:join within a few ms of each other.
    sockA.emit('game:matchmaking:join', {});
    sockB.emit('game:matchmaking:join', {});
    console.log('[emit] both matchmaking:join sent');

    // 5. Both should receive game:match:phase. BullMQ match-pair ticks
    //    every 1000ms so we allow up to 2 ticks + buffer = 2500ms.
    const PHASE_TIMEOUT = 2500;
    const [phaseA, phaseB] = await Promise.all([
      once<PhasePayload>(sockA, 'game:match:phase', PHASE_TIMEOUT),
      once<PhasePayload>(sockB, 'game:match:phase', PHASE_TIMEOUT),
    ]);

    // 6. Assertions: same matchId, both players present in some order.
    //    The ZSET is FIFO by join timestamp — which user is p1 vs p2 is
    //    non-deterministic because both `emit('game:matchmaking:join')` calls
    //    happen in the same JS tick. We only assert the SET, not the order.
    const sameMatch = phaseA.matchId === phaseB.matchId;
    record(
      results,
      'both sockets receive the same matchId',
      sameMatch,
      `a=${phaseA.matchId.slice(0, 8)}… b=${phaseB.matchId.slice(0, 8)}…`,
    );

    const seats = phaseA.players.map((p) => p.id).sort();
    const expected = [aliceAuth.userId, bobAuth.userId].sort();
    const bothPlayers =
      seats.length === 2 && seats[0] === expected[0] && seats[1] === expected[1];
    record(
      results,
      'phase.players lists both userIds (order non-deterministic — FIFO)',
      bothPlayers,
      `players=${JSON.stringify(seats.map((s) => s.slice(0, 8)))}`,
    );

    // Same player should occupy the same seat on both sockets (shared
    // fan-out). And alice + bob should sit on opposite seats.
    const aliceSeatA = phaseA.players.findIndex((p) => p.id === aliceAuth.userId);
    const aliceSeatB = phaseB.players.findIndex((p) => p.id === aliceAuth.userId);
    const bobSeatA = phaseA.players.findIndex((p) => p.id === bobAuth.userId);
    const bobSeatB = phaseB.players.findIndex((p) => p.id === bobAuth.userId);
    const sharedSeat =
      aliceSeatA === aliceSeatB &&
      bobSeatA === bobSeatB &&
      aliceSeatA !== bobSeatA &&
      aliceSeatA !== -1;
    record(
      results,
      'both sockets see alice + bob at the SAME opposite seats (shared fan-out)',
      sharedSeat,
      `alice@${aliceSeatA}=${aliceSeatB} bob@${bobSeatA}=${bobSeatB}`,
    );

    const sanePhase =
      phaseA.phase === 'shop_place' && phaseA.round === 1 && phaseA.timer > 0;
    record(
      results,
      'phase payload is shop_place / round 1 / positive timer',
      sanePhase,
      `phase=${phaseA.phase} round=${phaseA.round} timer=${phaseA.timer}`,
    );

    const bothHealthy =
      phaseA.players.every((p) => p.hp > 0 && p.gold >= 0 && !p.ready) &&
      phaseB.players.every((p) => p.hp > 0 && p.gold >= 0 && !p.ready);
    record(
      results,
      'each player: hp>0, gold>=0, ready=false',
      bothHealthy,
      `a=${JSON.stringify(phaseA.players)} b=${JSON.stringify(phaseB.players)}`,
    );

    // 7. Verify the match row landed in Postgres with the right shape.
    const ds = new DataSource({
      type: 'postgres',
      url: DATABASE_URL,
      entities: ENTITIES,
      synchronize: false,
      logging: ['error', 'warn'],
    });
    await ds.initialize();
    try {
      const row = await ds.getRepository(Match).findOne({
        where: { id: phaseA.matchId },
      });
      const rowPlayers = row ? [row.player1Id, row.player2Id].sort() : [];
      const expectedPlayers = [aliceAuth.userId, bobAuth.userId].sort();
      const rowOk =
        row !== null &&
        row.status === 'in_progress' &&
        rowPlayers[0] === expectedPlayers[0] &&
        rowPlayers[1] === expectedPlayers[1] &&
        row.matchSeed.length > 0 &&
        typeof row.p1State === 'object' &&
        typeof row.p2State === 'object';
      record(
        results,
        'PG matches row has both userIds as players, status=in_progress',
        rowOk,
        row === null
          ? 'row not found'
          : `players=${JSON.stringify(rowPlayers.map((s) => s.slice(0, 8)))} status=${row.status}`,
      );
    } finally {
      await ds.destroy();
    }

    // 8. Verify Redis queue is empty (both popped).
    const redis = new RedisService();
    try {
      const remaining = await redis.client.zcard(MATCHMAKING_QUEUE_KEY);
      record(
        results,
        'matchmaking:queue is empty after pairing',
        remaining === 0,
        `zcard=${remaining}`,
      );
    } finally {
      await redis.onModuleDestroy();
    }
  } finally {
    sockA.disconnect();
    sockB.disconnect();
  }

  // Report
  console.log('\n[results]');
  let passed = 0;
  for (const r of results) {
    const tag = r.passed ? 'PASS' : 'FAIL';
    if (r.passed) passed++;
    console.log(`  ${tag}  ${r.name.padEnd(64)} ${r.detail}`);
  }
  console.log(`\n[summary] ${passed}/${results.length} passed`);
  if (passed !== results.length) process.exitCode = 1;
}

// Avoid unused-import warning for the randomUUID import in some bundlers.
void randomUUID;

run().catch((error: unknown) => {
  console.error('[FAIL]', error);
  process.exitCode = 1;
});
