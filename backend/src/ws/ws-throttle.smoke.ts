/**
 * Live smoke test for the P1-BE-01 WebSocket rate limit.
 *
 * Run from the host against nginx:
 *   HTTP_BASE=http://localhost npx ts-node -T src/ws/ws-throttle.smoke.ts
 */
import { randomUUID } from 'crypto';
import { io, Socket } from 'socket.io-client';

interface AuthResponse {
  accessToken: string;
}

interface ErrorEnvelope {
  code?: string;
  message?: string;
}

const httpBase = process.env.HTTP_BASE ?? 'http://localhost';
const timeoutMs = 5000;

async function register(): Promise<AuthResponse> {
  const suffix = `${Date.now()}-${randomUUID().slice(0, 8)}`;
  const response = await fetch(`${httpBase}/auth/register`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({
      email: `ws-throttle-${suffix}@test.local`,
      username: `throttle${Date.now().toString(36)}`.slice(0, 20),
      password: 'hunter22-long-enough',
    }),
  });
  if (!response.ok) {
    throw new Error(`register failed: HTTP ${response.status} ${await response.text()}`);
  }
  return (await response.json()) as AuthResponse;
}

function connect(token: string): Promise<Socket> {
  return new Promise((resolve, reject) => {
    const socket = io(`${httpBase}/game`, {
      transports: ['websocket'],
      reconnection: false,
      auth: { token },
      timeout: timeoutMs,
    });
    const timer = setTimeout(() => {
      socket.close();
      reject(new Error('socket connect timeout'));
    }, timeoutMs);
    socket.once('connect', () => {
      clearTimeout(timer);
      resolve(socket);
    });
    socket.once('connect_error', (error) => {
      clearTimeout(timer);
      reject(error);
    });
  });
}

function waitForRateLimit(socket: Socket): Promise<ErrorEnvelope> {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(
      () => reject(new Error('game:error{code:rate.limited} timeout')),
      timeoutMs,
    );
    socket.on('game:error', (payload: ErrorEnvelope) => {
      if (payload.code !== 'rate.limited') return;
      clearTimeout(timer);
      resolve(payload);
    });
  });
}

async function run(): Promise<void> {
  const auth = await register();
  const socket = await connect(auth.accessToken);
  const configured = Number(process.env.WS_MSG_PER_SEC ?? 30);
  const limit = Number.isInteger(configured) && configured > 0 ? configured : 30;
  const rateLimited = waitForRateLimit(socket);

  // Invalid payloads keep this smoke test free of game-state mutations. The
  // throttle guard runs before validation and must eventually win the race.
  for (let i = 0; i <= limit; i++) {
    socket.emit('game:shop:buy', { round: 'three' });
  }

  const error = await rateLimited;
  socket.close();
  if (error.message !== 'slow down') {
    throw new Error(`unexpected rate-limit envelope: ${JSON.stringify(error)}`);
  }
  console.log(`[PASS] ${limit + 1} messages -> game:error{code:'rate.limited'}`);
}

run().catch((error: unknown) => {
  console.error('[FAIL]', error);
  process.exit(1);
});
