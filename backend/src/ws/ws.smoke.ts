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
 *
 * Run inside the docker network:
 *   docker compose exec nest-1 npx ts-node -T src/ws/ws.smoke.ts
 * Or from the host against an exposed gateway (nginx:80 or direct :3000):
 *   HTTP_BASE=http://localhost:3000 npx ts-node -T src/ws/ws.smoke.ts
 */
import { io, Socket } from 'socket.io-client';

interface AuthResponse {
  userId: string;
  accessToken: string;
  refreshToken: string;
}

interface ErrorEnvelope {
  code?: string;
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
