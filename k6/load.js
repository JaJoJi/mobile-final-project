// k6 load test — P3-DO-05 (#140)
//
// Proves the load NFRs against a `docker compose up` stack:
//   NFR-2  p95 round-state WS event  < 500 ms   -> round_state_latency_ms
//   NFR-14 p95 combat latency        < 500 ms   -> combat_latency_ms
//   NFR-3  >= 50 concurrent matches              -> 50 VUs, each in a match
//
// Run:
//   docker compose up -d --build
//   k6 run --env BASE_URL=http://localhost --env WS_URL=ws://localhost k6/load.js
// or without a local k6 binary:
//   docker run --rm -i --network host -e BASE_URL=http://localhost -e WS_URL=ws://localhost \
//     grafana/k6 run - < k6/load.js
//
// ── KNOWN GAP ──────────────────────────────────────────────────────────
// Latency is measured as (client_now - event.sentAt). The backend does
// NOT emit `sentAt` on WS events yet (small change in ws.gateway.ts /
// the pubsub layer — see #140 "Files to touch"). Until it lands:
//   * round_state_latency_ms / combat_latency_ms collect ZERO samples
//   * their thresholds are reported as "no data" (k6 passes a threshold
//     with no samples), so this script does not yet fail on NFR-2/-14.
// The connection-rate / error-rate / matchmaking thresholds below are
// real today. Flip `LAT_METRICS_LIVE` once the backend emits sentAt.
// ─────────────────────────────────────────────────────────────────────

import http from 'k6/http';
import ws from 'k6/ws';
import { check } from 'k6';
import { Trend, Counter, Rate } from 'k6/metrics';

const BASE_URL = __ENV.BASE_URL || 'http://localhost';
const WS_URL = __ENV.WS_URL || 'ws://localhost';
const VUS = parseInt(__ENV.VUS || '50', 10);
const DURATION = __ENV.DURATION || '5m';
const MATCH_HOLD_S = parseInt(__ENV.MATCH_HOLD_S || '90', 10);

const roundLatency = new Trend('round_state_latency_ms', true);
const combatLatency = new Trend('combat_latency_ms', true);
const matchFound = new Rate('match_found_rate');
const wsConnectErrors = new Counter('ws_connect_errors');
const eventsSeen = new Counter('game_events_total');

export const options = {
  scenarios: {
    matches: {
      executor: 'constant-vus',
      vus: VUS,
      duration: DURATION,
      gracefulStop: '30s',
    },
  },
  thresholds: {
    // NFR-2 / NFR-14 — real once the backend emits `sentAt`.
    round_state_latency_ms: ['p(95)<500'],
    combat_latency_ms: ['p(95)<500'],
    // Real today:
    http_req_failed: ['rate<0.01'],
    ws_connecting: ['p(95)<1000'],
    match_found_rate: ['rate>0.90'],
    ws_connect_errors: ['count<' + Math.ceil(VUS * 0.05)],
  },
};

function j(body) {
  try {
    return JSON.parse(body);
  } catch (_e) {
    return {};
  }
}

// Socket.IO v4 over raw websocket frames: engine.io packet types are a
// leading digit; "42" = Engine.IO MESSAGE + Socket.IO EVENT. Payload is
// then a JSON array [eventName, ...args].
function sioEvent(name, payload) {
  return '42' + JSON.stringify(payload === undefined ? [name] : [name, payload]);
}

function parseSio(raw) {
  if (typeof raw !== 'string') return null;
  if (raw.slice(0, 2) !== '42') return null;
  const arr = j(raw.slice(2));
  if (!Array.isArray(arr) || arr.length === 0) return null;
  return { event: arr[0], data: arr[1] };
}

function latencyFrom(data) {
  // Tolerate a few likely shapes for the server timestamp.
  const t =
    data && (data.sentAt || data.emittedAt || (data.meta && data.meta.sentAt));
  if (!t) return null;
  const ms = Date.now() - Number(t);
  return Number.isFinite(ms) && ms >= 0 && ms < 60000 ? ms : null;
}

export default function () {
  const tag = `k6_${__VU}_${__ITER}`;
  const creds = {
    email: `${tag}@load.local`,
    username: tag,
    password: 'password123',
  };
  const headers = { 'Content-Type': 'application/json' };

  // register is idempotent-ish; ignore a 409 on repeat.
  http.post(`${BASE_URL}/auth/register`, JSON.stringify(creds), {
    headers,
    tags: { name: 'register' },
  });

  const loginRes = http.post(
    `${BASE_URL}/auth/login`,
    JSON.stringify({ email: creds.email, password: creds.password }),
    { headers, tags: { name: 'login' } },
  );
  const okLogin = check(loginRes, { 'login 2xx': (r) => r.status >= 200 && r.status < 300 });
  if (!okLogin) return;

  const { accessToken } = j(loginRes.body);
  if (!accessToken) return;

  const url = `${WS_URL}/socket.io/?EIO=4&transport=websocket`;
  const res = ws.connect(
    url,
    { headers: { Authorization: `Bearer ${accessToken}` } },
    (socket) => {
      let joined = false;

      socket.on('open', () => {
        // Engine.IO handshake: server sends "0{...}", we reply "40" to
        // open the default namespace, then send our join event.
        socket.send('40');
      });

      socket.on('message', (raw) => {
        // Engine.IO ping -> pong keepalive.
        if (raw === '2') {
          socket.send('3');
          return;
        }
        if (raw === '40' || raw.slice(0, 2) === '40') {
          socket.send(sioEvent('game:matchmaking:join'));
          return;
        }
        const msg = parseSio(raw);
        if (!msg) return;
        eventsSeen.add(1);

        switch (msg.event) {
          case 'game:match:phase':
          case 'game:match:state': {
            if (!joined) {
              joined = true;
              matchFound.add(1);
            }
            const ms = latencyFrom(msg.data);
            if (ms !== null) roundLatency.add(ms);
            break;
          }
          case 'game:combat:events':
          case 'game:match:damage': {
            const ms = latencyFrom(msg.data);
            if (ms !== null) combatLatency.add(ms);
            break;
          }
          case 'game:error':
            // auth / protocol error — let the connection close.
            break;
          default:
            break;
        }
      });

      socket.on('error', () => {
        wsConnectErrors.add(1);
      });

      // Stay in the match long enough to observe several rounds of
      // phase + combat events, then leave cleanly.
      socket.setTimeout(() => {
        if (!joined) matchFound.add(0);
        socket.send(sioEvent('game:matchmaking:leave'));
        socket.close();
      }, MATCH_HOLD_S * 1000);
    },
  );

  check(res, { 'ws handshake 101': (r) => r && r.status === 101 }) ||
    wsConnectErrors.add(1);
}

// NOTE: k6 has no DB access for teardown. Load-test users (`k6_*@load.local`)
// accumulate in Postgres. Clean them from CI after the run, e.g.:
//   docker compose exec -T postgres-primary psql -U postgres -d auto_chess \
//     -c "DELETE FROM users WHERE email LIKE 'k6\_%@load.local';"
// (see .github/workflows/load-test.yml).
