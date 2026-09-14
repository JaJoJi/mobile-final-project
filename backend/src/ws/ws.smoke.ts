/**
 * Smoke harness for P0-BE-04 (WebSocket gateway skeleton).
 *
 * Connects to the Nest `/game` namespace with various tokens and asserts
 * the documented behavior:
 *
 *   1. No token in handshake  → server emits `game:error{code:'auth.invalid'}`
 *                               and disconnects.
 *   2. Valid access JWT      → `connect` succeeds, server logs the userId.
 *   3. Same user reconnects  → first socket is forcibly disconnected
 *                               (per-user dedup). The new socket stays.
 *   4. Garbage token         → server emits `game:error{code:'auth.expired'}`
 *                               and disconnects.
 *   9. WS message flood      → server emits `game:error{code:'rate.limited'}`
 *                               before the handler runs.
 *
 * Run inside the docker network:
 *   docker compose exec nest-1 npx ts-node -T src/ws/ws.smoke.ts
 * Or from the host against an exposed gateway (nginx:80 or direct :3000):
 *   HTTP_BASE=http://localhost:3000 npx ts-node -T src/ws/ws.smoke.ts
 */
import { io, Socket } from 'socket.io-client';
import { randomUUID } from 'crypto';

interface AuthResponse {
  userId: string;
  accessToken: string;
  refreshToken: string;
}

interface ErrorEnvelope {
  code?: string;
  message?: string;
}

interface TestResult {
  name: string;
  passed: boolean;
  detail: string;
}

const HTTP_BASE = process.env.HTTP_BASE ?? 'http://localhost:3000';
const NAMESPACE = '/game';
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

function randomEmail(): string {
  return `smoke-${Date.now()}-${Math.random().toString(36).slice(2, 8)}@test.local`;
}

function connect(opts: { token?: string; timeoutMs?: number } = {}): Promise<{
  socket: Socket;
  connectOk: boolean;
  errorPayload: ErrorEnvelope | null;
  disconnected: boolean;
  disconnectReason: string;
}> {
  const timeoutMs = opts.timeoutMs ?? TIMEOUT_MS;
  return new Promise((resolve) => {
    const socket = io(`${HTTP_BASE}${NAMESPACE}`, {
      transports: ['websocket'],
      reconnection: false,
      auth: opts.token !== undefined ? { token: opts.token } : {},
      timeout: timeoutMs,
    });

    let connectOk = false;
    let errorPayload: ErrorEnvelope | null = null;
    let disconnected = false;
    let disconnectReason = 'io client disconnect';
    let settled = false;

    const finish = () => {
      if (settled) return;
      settled = true;
      resolve({ socket, connectOk, errorPayload, disconnected, disconnectReason });
    };

    socket.on('connect', () => {
      connectOk = true;
      // Give the server a moment to either keep us connected or push an
      // error envelope + close. Most auth failures land within ~100ms.
      setTimeout(finish, 500);
    });

    socket.on('game:error', (payload: ErrorEnvelope) => {
      errorPayload = payload;
    });

    socket.on('disconnect', (reason: string) => {
      disconnected = true;
      disconnectReason = reason;
    });

    socket.on('connect_error', (e: Error) => {
      // Transport-level handshake rejection (rare — usually the server
      // accepts and then immediately disconnects).
      disconnectReason = `connect_error: ${e.message}`;
      disconnected = true;
      finish();
    });

    setTimeout(finish, timeoutMs);
  });
}

function once<T>(socket: Socket, event: string, timeoutMs = TIMEOUT_MS): Promise<T> {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error(`${event} timeout`)), timeoutMs);
    socket.once(event, (payload: T) => {
      clearTimeout(timer);
      resolve(payload);
    });
  });
}

function emitWithAck<T>(socket: Socket, event: string, payload: unknown): Promise<T> {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error(`${event} ack timeout`)), TIMEOUT_MS);
    socket.emit(event, payload, (ack: T) => {
      clearTimeout(timer);
      resolve(ack);
    });
  });
}

async function run(): Promise<void> {
  console.log(`[connect] HTTP_BASE=${HTTP_BASE} namespace=${NAMESPACE}`);
  const results: TestResult[] = [];

  // 0. Register a throwaway user so we have a real JWT to test against.
  const email = randomEmail();
  const password = 'hunter22-long-enough';
  const username = `smoke${Date.now().toString(36)}`.slice(0, 20);
  const reg = await http<AuthResponse>('/auth/register', {
    method: 'POST',
    body: JSON.stringify({ email, password, username }),
  });
  console.log(`[register] userId=${reg.userId} (jwt prefix=${reg.accessToken.slice(0, 20)}...)`);

  // 1. No token → game:error{auth.invalid} + server-initiated disconnect
  //    Note: the socket.io `connect` event fires at the transport layer,
  //    BEFORE the gateway's handleConnection runs. So `connectOk=true`
  //    is expected even on auth failures — the real signal is the
  //    `game:error` envelope followed by a `server disconnect`.
  {
    const { socket, connectOk, errorPayload, disconnected, disconnectReason } =
      await connect({});
    socket.close();
    results.push({
      name: '1. no token',
      passed:
        connectOk &&
        errorPayload?.code === 'auth.invalid' &&
        disconnected &&
        disconnectReason === 'io server disconnect',
      detail: `connectOk=${connectOk} errorCode=${errorPayload?.code ?? '∅'} disconnected=${disconnected} reason=${disconnectReason}`,
    });
  }

  // 2. Valid token → connect succeeds, no error envelope
  {
    const { socket, connectOk, errorPayload, disconnected, disconnectReason } =
      await connect({ token: reg.accessToken });
    socket.close();
    results.push({
      name: '2. valid JWT',
      passed: connectOk && errorPayload === null && !disconnected,
      detail: `connectOk=${connectOk} errorCode=${errorPayload?.code ?? '∅'} disconnected=${disconnected} reason=${disconnectReason}`,
    });
  }

  // 3. Dedup: open two sockets with the same JWT → first is server-kicked.
  //    Strategy: hold `first` open with a longer observation window so we
  //    can observe its server-initiated disconnect when `second` joins.
  {
    const first = io(`${HTTP_BASE}${NAMESPACE}`, {
      transports: ['websocket'],
      reconnection: false,
      auth: { token: reg.accessToken },
      timeout: TIMEOUT_MS,
    });
    const firstReady = new Promise<void>((resolve) => first.on('connect', () => resolve()));
    await firstReady;

    // Give the server a moment to register `first` in its dedup map.
    await new Promise((r) => setTimeout(r, 300));

    const firstDisconnect = new Promise<{ reason: string; disconnected: boolean }>((resolve) => {
      first.on('disconnect', (reason: string) => resolve({ reason, disconnected: true }));
    });

    const second = await connect({ token: reg.accessToken });

    const firstResult = await Promise.race([
      firstDisconnect,
      new Promise<{ reason: string; disconnected: boolean }>((resolve) =>
        setTimeout(() => resolve({ reason: 'timeout — never disconnected', disconnected: false }), 1500),
      ),
    ]);

    first.close();
    second.socket.close();

    results.push({
      name: '3. per-user dedup',
      passed:
        second.connectOk &&
        firstResult.disconnected &&
        firstResult.reason === 'io server disconnect',
      detail: `first.disconnected=${firstResult.disconnected} first.reason=${firstResult.reason} second.connectOk=${second.connectOk}`,
    });
  }

  // 4. Garbage token → game:error{auth.expired} + server disconnect
  {
    const garbage =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJzbW9rZSIsInR5cGUiOiJhY2Nlc3MiLCJpYXQiOjB9.invalid_signature_xxxxxxxxxxxxxxxxxxxxxxxxxx';
    const { socket, connectOk, errorPayload, disconnected, disconnectReason } =
      await connect({ token: garbage });
    socket.close();
    results.push({
      name: '4. garbage token',
      passed:
        connectOk &&
        errorPayload?.code === 'auth.expired' &&
        disconnected &&
        disconnectReason === 'io server disconnect',
      detail: `connectOk=${connectOk} errorCode=${errorPayload?.code ?? '∅'} disconnected=${disconnected} reason=${disconnectReason}`,
    });
  }

  // 5. Refresh token used as access → game:error{auth.invalid} (wrong type)
  {
    const { socket, connectOk, errorPayload, disconnected, disconnectReason } =
      await connect({ token: reg.refreshToken });
    socket.close();
    results.push({
      name: '5. wrong token type (refresh used as access)',
      passed:
        connectOk &&
        errorPayload?.code === 'auth.invalid' &&
        disconnected &&
        disconnectReason === 'io server disconnect',
      detail: `connectOk=${connectOk} errorCode=${errorPayload?.code ?? '∅'} disconnected=${disconnected} reason=${disconnectReason}`,
    });
  }

  // 6. Invalid DTO is converted by the gateway filter to game:error.
  {
    const connection = await connect({ token: reg.accessToken });
    const error = once<ErrorEnvelope>(connection.socket, 'game:error');
    connection.socket.emit('game:shop:buy', { round: 'three' });
    const payload = await error;
    connection.socket.close();
    results.push({
      name: '6. invalid handler payload',
      passed: connection.connectOk && payload.code === 'invalid_payload',
      detail: `connectOk=${connection.connectOk} errorCode=${payload.code ?? '∅'}`,
    });
  }

  // 7. A valid handler delegates to matchmaking and returns its result.
  {
    const connection = await connect({ token: reg.accessToken });
    const joined = await emitWithAck<{ queued: boolean }>(
      connection.socket,
      'game:matchmaking:join',
      {},
    );
    const left = await emitWithAck<boolean>(
      connection.socket,
      'game:matchmaking:leave',
      {},
    );
    connection.socket.close();
    results.push({
      name: '7. valid matchmaking handlers',
      passed: joined?.queued === true && left === true,
      detail: `queued=${joined?.queued} left=${left}`,
    });
  }

  // 8. Two real sockets may land on different Nest replicas; both must be
  // auto-subscribed by the first phase event and receive only their own shop.
  {
    const reg2 = await http<AuthResponse>('/auth/register', {
      method: 'POST',
      body: JSON.stringify({
        email: randomEmail(),
        password,
        username: `smoke${(Date.now() + 1).toString(36)}`.slice(0, 20),
      }),
    });
    const [first, second] = await Promise.all([
      connect({ token: reg.accessToken }),
      connect({ token: reg2.accessToken }),
    ]);
    const phase1 = once<{ matchId: string; players: Array<{ id: string }> }>(
      first.socket,
      'game:match:phase',
    );
    const phase2 = once<{ matchId: string; players: Array<{ id: string }> }>(
      second.socket,
      'game:match:phase',
    );
    const offer1 = once<{ matchId: string; offers: unknown[] }>(
      first.socket,
      'game:shop:offer',
    );
    const offer2 = once<{ matchId: string; offers: unknown[] }>(
      second.socket,
      'game:shop:offer',
    );
    await Promise.all([
      emitWithAck(first.socket, 'game:matchmaking:join', {}),
      emitWithAck(second.socket, 'game:matchmaking:join', {}),
    ]);
    const [p1, p2, s1, s2] = await Promise.all([phase1, phase2, offer1, offer2]);
    const sameMatch = p1.matchId === p2.matchId && p1.matchId === s1.matchId && p1.matchId === s2.matchId;
    const bothPlayers = [reg.userId, reg2.userId].every((id) =>
      p1.players.some((player) => player.id === id));

    const boughtStatePromise = once<{
      roster: { board: Array<{ instanceId: string } | null>; bench: Array<{ instanceId: string } | null> };
    }>(first.socket, 'game:match:state');
    const bought = await emitWithAck<{ duplicate: boolean }>(first.socket, 'game:shop:buy', {
      round: 1,
      offerIndex: 0,
      clientActionId: randomUUID(),
    });
    const boughtState = await boughtStatePromise;
    const unit = boughtState.roster.bench.find((entry) => entry !== null);

    const placedStatePromise = once<{
      roster: { board: Array<{ instanceId: string } | null> };
    }>(first.socket, 'game:match:state');
    const placed = await emitWithAck<{ duplicate: boolean }>(first.socket, 'game:match:place', {
      round: 1,
      unitInstanceId: unit?.instanceId,
      target: 'board',
      slot: 0,
      clientActionId: randomUUID(),
    });
    const placedState = await placedStatePromise;

    const battle1 = once<{ phase: string }>(first.socket, 'game:match:phase');
    const battle2 = once<{ phase: string }>(second.socket, 'game:match:phase');
    await emitWithAck(first.socket, 'game:match:ready', {
      round: 1,
      clientActionId: randomUUID(),
    });
    await emitWithAck(second.socket, 'game:match:ready', {
      round: 1,
      clientActionId: randomUUID(),
    });
    const [battlePhase1, battlePhase2] = await Promise.all([battle1, battle2]);
    first.socket.close();
    second.socket.close();
    const actionFlow =
      bought?.duplicate === false &&
      placed?.duplicate === false &&
      Boolean(unit) &&
      placedState.roster.board[0]?.instanceId === unit?.instanceId &&
      battlePhase1.phase === 'battle' &&
      battlePhase2.phase === 'battle';
    results.push({
      name: '8. cross-instance match start fan-out',
      passed:
        sameMatch &&
        bothPlayers &&
        s1.offers.length === 5 &&
        s2.offers.length === 5 &&
        actionFlow,
      detail: `sameMatch=${sameMatch} bothPlayers=${bothPlayers} offers=${s1.offers.length}/${s2.offers.length} actionFlow=${actionFlow}`,
    });
  }

  // 9. The production guard is wired to the gateway and returns the frozen
  // game:error envelope. Malformed messages are intentional: validation owns
  // the first `limit` messages, then the guard must reject the flood first.
  {
    const connection = await connect({ token: reg.accessToken });
    const configured = Number(process.env.WS_MSG_PER_SEC ?? 30);
    const limit = Number.isInteger(configured) && configured > 0 ? configured : 30;
    const rateLimited = new Promise<ErrorEnvelope>((resolve, reject) => {
      const timer = setTimeout(
        () => reject(new Error('rate.limited timeout')),
        TIMEOUT_MS,
      );
      connection.socket.on('game:error', (payload: ErrorEnvelope) => {
        if (payload.code !== 'rate.limited') return;
        clearTimeout(timer);
        resolve(payload);
      });
    });
    for (let i = 0; i <= limit; i++) {
      connection.socket.emit('game:shop:buy', { round: 'three' });
    }
    const payload = await rateLimited;
    connection.socket.close();
    results.push({
      name: '9. per-user WS rate limit',
      passed: connection.connectOk && payload.code === 'rate.limited',
      detail: `connectOk=${connection.connectOk} errorCode=${payload.code ?? '∅'} limit=${limit}`,
    });
  }

  // Report
  console.log('\n[results]');
  let pass = 0;
  for (const r of results) {
    const tag = r.passed ? 'PASS' : 'FAIL';
    if (r.passed) pass++;
    console.log(`  ${tag}  ${r.name.padEnd(40)} ${r.detail}`);
  }
  console.log(`\n[summary] ${pass}/${results.length} passed`);

  if (pass !== results.length) process.exit(1);
}

run().catch((e: unknown) => {
  console.error('[FAIL]', e);
  process.exit(1);
});
