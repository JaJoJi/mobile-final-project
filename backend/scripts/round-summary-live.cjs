// Local two-client regression through nginx, Redis and the running workers.
const { io } = require('socket.io-client');
const { randomUUID } = require('crypto');
const assert = require('node:assert/strict');
const base = 'http://localhost';
const delay = ms => new Promise(resolve => setTimeout(resolve, ms));
async function http(path, body, token) {
  const response = await fetch(base + path, {
    method: 'POST', headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}) },
    body: JSON.stringify(body),
  });
  if (!response.ok) throw new Error(`${path}: ${response.status} ${await response.text()}`);
  return response.json();
}
async function waitFor(predicate, label) {
  const until = Date.now() + 10000;
  while (Date.now() < until) {
    if (predicate()) return;
    await delay(50);
  }
  throw new Error(`Timeout: ${label}`);
}
async function run() {
  const clients = [];
  try {
    for (const side of ['a', 'b']) {
      const name = `summary${Date.now().toString(36)}${side}`;
      const auth = await http('/auth/register', { username: name, email: `${name}@example.test`, password: randomUUID() });
      const socket = io(base + '/game', { transports: ['websocket'], reconnection: false, auth: { token: auth.accessToken } });
      const client = { socket, auth, events: [] };
      socket.onAny((event, payload) => client.events.push({ event, payload, at: Date.now() }));
      clients.push(client);
      await waitFor(() => socket.connected, 'socket connected');
    }
    const [a, b] = clients;
    const room = await http('/rooms', {}, a.auth.accessToken);
    await http('/rooms/join', { code: room.code }, b.auth.accessToken);
    const phase = (c, round, value) => c.events.find(e => e.event === 'game:match:phase' && e.payload.round === round && e.payload.phase === value);
    await waitFor(() => clients.every(c => phase(c, 1, 'shop_place')), 'initial phase');
    const matchId = phase(a, 1, 'shop_place').payload.matchId;
    const send = (c, action, round) => c.socket.emit(`game:match:${action}`, { matchId, round, clientActionId: randomUUID(), ...(action === 'ready' ? { ready: true } : {}) });
    for (const c of clients) send(c, 'ready', 1);
    await waitFor(() => clients.every(c => c.events.some(e => e.event === 'game:match:damage' && e.payload.round === 1)), 'result available before skip');
    send(a, 'combat_done', 1);
    await delay(500);
    assert(!phase(a, 1, 'resolved'), 'first skip must wait for opponent');
    send(b, 'combat_done', 1);
    await waitFor(() => clients.every(c => phase(c, 1, 'resolved')), 'both reach summary');
    await delay(3500);
    assert(clients.every(c => !phase(c, 2, 'shop_place')), 'summary must remain until continue is pressed');
    console.log('PASS result before skip; first skip waits; both skips hold summary >3 seconds');
    const started = Date.now();
    send(a, 'round_ready', 1);
    await waitFor(() => clients.every(c => c.events.some(e => e.event === 'game:match:phase' && e.payload.phase === 'resolved' && e.payload.timer === 3)), 'three-second countdown');
    await delay(1000);
    assert(clients.every(c => !phase(c, 2, 'shop_place')), 'must not advance before countdown');
    await waitFor(() => clients.every(c => phase(c, 2, 'shop_place')), 'next round');
    assert(Date.now() - started >= 2800);
    console.log(`PASS one continue advances both after ${Date.now() - started}ms`);
    for (const c of clients) send(c, 'ready', 2);
    await waitFor(() => clients.every(c => c.events.some(e => e.event === 'game:match:damage' && e.payload.round === 2)), 'round two result');
    for (const c of clients) send(c, 'combat_done', 2);
    await waitFor(() => clients.every(c => phase(c, 2, 'resolved')), 'round two summary');
    for (const c of clients) send(c, 'round_ready', 2);
    await waitFor(() => clients.every(c => phase(c, 3, 'shop_place')), 'both continue');
    send(a, 'surrender', 3);
    await waitFor(() => clients.every(c => c.events.some(e => e.event === 'game:match:end')), 'surrender ends match');
    assert(clients.every(c => c.events.find(e => e.event === 'game:match:end').payload.winnerId === b.auth.userId));
    assert(clients.every(c => !c.events.some(e => e.event === 'game:error')), JSON.stringify(clients.flatMap(c => c.events.filter(e => e.event === 'game:error'))));
    console.log('PASS both continue; surrender awards opponent; no game errors');
  } finally {
    for (const c of clients) c.socket.disconnect();
  }
}
run().catch(error => { console.error(error.message); process.exitCode = 1; });
