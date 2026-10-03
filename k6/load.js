// k6 load test for the NFRs (#140):
//   NFR-2  p95 round-state WS event delivery < 500 ms
//   NFR-3  >= 50 concurrent matches
//   NFR-14 p95 combat latency < 500 ms
//
// One VU = one player. Every VU registers a throwaway user, opens its
// /game socket (Socket.IO over a raw WebSocket), queues in matchmaking and
// is paired with another VU by the real matchmaking worker. MATCHES=50
// therefore runs 100 VUs = 50 concurrent 1v1 matches. Each player then
// plays ROUNDS rounds: shop:buy -> ready -> battle -> combat events ->
// combat_done -> next shop.
//
// Latencies (each measured on the client that sent the request):
//   action_state_latency_ms  shop:buy        -> game:match:state
//   round_state_latency_ms   match:ready     -> game:match:phase "battle"
//   combat_latency_ms        match:ready     -> game:combat:events
// ready->battle/combat also contains "waiting for the opponent's ready"
// (both bots send ready within a few ms of each other, so that skew is
// about the action latency): the numbers are a conservative upper bound.
//
// Needs k6 1.3 (k6/experimental/websockets; plain k6/websockets only exists in newer releases). Run:
//   # one stack on :80 (nginx) or :3000 (one nest)
//   docker run --rm -i --network host -e TARGETS=http://localhost grafana/k6 run - < k6/load.js
//   # several instances, round-robin (exercises the Redis pub/sub path)
//   k6 run -e TARGETS=http://nest-1:3000,http://nest-2:3000,http://nest-3:3000 -e MATCHES=50 k6/load.js
//
// Env: TARGETS (comma list, default http://localhost) - MATCHES (50) -
//      ROUNDS (3) - EVENT_TIMEOUT_MS (20000)
import http from 'k6/http';
import { WebSocket } from 'k6/experimental/websockets';
import { Trend, Counter, Rate } from 'k6/metrics';
import { check } from 'k6';

const TARGETS = (__ENV.TARGETS || 'http://localhost').split(',').map((s) => s.trim()).filter(Boolean);
const MATCHES = parseInt(__ENV.MATCHES || '50', 10);
const ROUNDS = parseInt(__ENV.ROUNDS || '3', 10);
const EVENT_TIMEOUT_MS = parseInt(__ENV.EVENT_TIMEOUT_MS || '20000', 10);

const roundStateLatency = new Trend('round_state_latency_ms', true);
const combatLatency = new Trend('combat_latency_ms', true);
const actionLatency = new Trend('action_state_latency_ms', true);
const matchmakingLatency = new Trend('matchmaking_latency_ms', true);
const playersCompleted = new Counter('players_completed');
const playerFailed = new Rate('player_failed');

export const options = {
  scenarios: {
    players: {
      executor: 'per-vu-iterations',
      vus: MATCHES * 2,
      iterations: 1,
      maxDuration: '10m',
    },
  },
  thresholds: {
    round_state_latency_ms: ['p(95)<500'],
    combat_latency_ms: ['p(95)<500'],
    player_failed: ['rate==0'],
    http_req_failed: ['rate<0.01'],
  },
};

function uuid() {
  return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => {
    const r = (Math.random() * 16) | 0;
    return (c === 'x' ? r : (r & 0x3) | 0x8).toString(16);
  });
}

function register(base) {
  const stamp = `${Date.now()}${Math.floor(Math.random() * 1e6)}`;
  const res = http.post(
    `${base}/auth/register`,
    JSON.stringify({
      email: `k6-${stamp}@load.test`,
      username: `k6${stamp}`.slice(0, 20),
      password: 'k6-load-test-pw-123',
    }),
    { headers: { 'content-type': 'application/json' }, tags: { name: 'register' } },
  );
  check(res, { 'register ok': (r) => r.status === 201 || r.status === 200 });
  const body = res.json();
  return body.accessToken;
}

export default function () {
  const base = TARGETS[__VU % TARGETS.length];
  const token = register(base);

  let done = false;
  let matchId = null;
  let round = 1;
  let roundsPlayed = 0;
  let joinAt = 0;
  let readyAt = 0;
  let buyAt = 0;
  let gotBattle = false;
  let gotCombat = false;
  let timer = null;

  const ws = new WebSocket(base.replace(/^http/, 'ws') + '/socket.io/?EIO=4&transport=websocket');
  const emit = (event, payload) => ws.send('42/game,' + JSON.stringify([event, payload]));

  const finish = (err) => {
    if (done) return;
    done = true;
    if (timer) clearTimeout(timer);
    playerFailed.add(err ? 1 : 0);
    if (err) console.error(`VU${__VU} failed: ${err}`); else playersCompleted.add(1);
    try { ws.close(); } catch (e) { /* already closed */ }
  };

  const arm = (what) => {
    if (timer) clearTimeout(timer);
    timer = setTimeout(() => finish(`timeout waiting for ${what} (round ${round})`), EVENT_TIMEOUT_MS);
  };

  const sendReady = () => {
    emit('game:match:ready', { round, ready: true, clientActionId: uuid() });
    readyAt = Date.now();
    arm('battle phase');
  };

  const onEvent = (ev, p) => {
    if (done) return;
    if (ev === 'game:error') {
      // a rejected buy (e.g. not enough gold) is fine: carry on to ready
      if (buyAt && /shop|buy/.test(String((p && p.code) || ''))) { buyAt = 0; sendReady(); return; }
      return;
    }
    if (ev === 'game:match:phase') {
      if (!matchId) { matchId = p.matchId; matchmakingLatency.add(Date.now() - joinAt); }
      if (p.phase === 'shop_place') {
        round = p.round;
        if (roundsPlayed >= ROUNDS) return finish(null);
        gotBattle = false;
        gotCombat = false;
        buyAt = Date.now();
        emit('game:shop:buy', { round, offerIndex: 0, clientActionId: uuid() });
        arm('state after buy');
      } else if (p.phase === 'battle' && readyAt && !gotBattle) {
        gotBattle = true;
        roundStateLatency.add(Date.now() - readyAt);
        arm('combat events');
      }
    } else if (ev === 'game:match:state' && buyAt) {
      actionLatency.add(Date.now() - buyAt);
      buyAt = 0;
      sendReady();
    } else if (ev === 'game:combat:events' && readyAt && !gotCombat) {
      gotCombat = true;
      combatLatency.add(Date.now() - readyAt);
      roundsPlayed += 1;
      readyAt = 0;
      emit('game:match:combat_done', { matchId, round, clientActionId: uuid() });
      if (roundsPlayed >= ROUNDS) return finish(null);
      arm('next shop phase');
    } else if (ev === 'game:match:end') {
      finish(null);
    }
  };

  // Minimal Socket.IO v4 client on the /game namespace.
  ws.onmessage = (e) => {
    const m = String(e.data);
    if (m[0] === '0') {
      ws.send('40/game,' + JSON.stringify({ token }));           // Engine.IO open -> join namespace
    } else if (m === '2') {
      ws.send('3');                                              // ping -> pong
    } else if (m.indexOf('40/game') === 0) {
      joinAt = Date.now();                                       // namespace connected -> queue
      emit('game:matchmaking:join', {});
      arm('matchmaking pair');
    } else if (m.indexOf('44/game') === 0) {
      finish('namespace refused: ' + m);
    } else if (m.indexOf('42/game,') === 0) {
      const arr = JSON.parse(m.slice('42/game,'.length));
      onEvent(arr[0], arr[1]);
    }
  };
  ws.onclose = () => { if (!done) finish('socket closed early'); };
  ws.onerror = () => { if (!done) finish('socket error'); };
  arm('socket connected');

  // keep the iteration alive until the player is done (event-loop driven)
  return new Promise((resolve) => {
    const t = setInterval(() => { if (done) { clearInterval(t); resolve(); } }, 200);
  });
}
