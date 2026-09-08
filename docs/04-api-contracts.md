# API Contracts

> All schemas mirror between TypeScript (backend) and Dart (Flutter).
> Auth for REST: `Authorization: Bearer <jwt>`. Auth for WS: `auth.token` in socket handshake.

**Implementation status** (last updated end of Week 1):

| Endpoint | Status | Notes |
|---|---|---|
| `POST /auth/register` | ✅ implemented | bcrypt(10) + JWT(HS256) |
| `POST /auth/login` | ✅ implemented | |
| `POST /auth/refresh` | ✅ implemented | long-lived (no rotation); both old + new refresh work |
| `GET /user/me` | ✅ implemented | guarded by `JwtAccessGuard` |
| `PATCH /user/me` | ✅ implemented | username only |
| `GET /match/history` | ⏳ planned | |
| `GET /match/:matchId` | ⏳ planned | |
| WS gateway (`/socket.io`) | ⏳ planned | schema frozen in §2 |

## 1. REST Endpoints

### POST `/auth/register` ✅
**Request**
```json
{ "email": "alice@example.com", "username": "alice", "password": "pass1234" }
```
**Response 201**
```json
{ "userId": "uuid", "accessToken": "jwt", "refreshToken": "jwt" }
```
**Errors**: `400` invalid email/password length, invalid username regex, etc.; `409` email already exists (also returned for duplicate username via PATCH `/user/me`).

### POST `/auth/login` ✅
**Request**
```json
{ "email": "alice@example.com", "password": "pass1234" }
```
**Response 200**: same shape as register.

### POST `/auth/refresh` ✅
**Request**
```json
{ "refreshToken": "jwt" }
```
**Response 200**
```json
{ "userId": "uuid", "accessToken": "jwt", "refreshToken": "jwt" }
```

JWT payload shape: `{ sub: <userId>, type: 'access' | 'refresh' }`. Guards reject the wrong type (a refresh token can't authenticate `/user/me`; an access token can't be used to refresh).

### GET `/user/me` ✅
**Response 200**
```json
{ "id": "uuid", "email": "alice@example.com", "username": "alice", "rating": 1000 }
```
**Errors**: `401` missing / invalid / expired token, or token of wrong type (refresh used here).

### PATCH `/user/me` ✅
**Request**
```json
{ "username": "newname" }
```
**Response 200** (updated user, same shape as GET `/user/me`)
**Errors**:
- `400` invalid username (regex `^[a-zA-Z0-9_]+$`, 3–20 chars).
- `409` username already in use (PG `23505` translated).
- `401` same as GET `/user/me`.

> Email and password are non-editable in MVP (per design decision).

### GET `/match/history`
**Response 200**
```json
[
  { "matchId": "uuid", "opponent": "bob", "winner": "alice", "createdAt": "ISO", "duration": 180 }
]
```
Most recent 50 matches.

### GET `/match/:matchId`
**Response 200**
```json
{
  "matchId": "uuid",
  "players": [{ "id": "uuid", "username": "alice" }, { "id": "uuid", "username": "bob" }],
  "winner": "alice",
  "rounds": [
    { "roundNumber": 1, "winner": "alice", "damage": 0 }
  ],
  "createdAt": "ISO", "finishedAt": "ISO"
}
```

## 2. WebSocket Events

**Namespace**: `/game`. **Transport**: Socket.IO.

### 2.1 Outgoing — server → client

#### `game:match:phase`
Sent when phase changes (match start or transition).
```ts
{
  matchId: string;
  phase: 'shop_place' | 'battle' | 'resolved' | 'finished';
  round: number;
  timer: number;        // seconds remaining in phase
  players: Array<{ id: string; hp: number; gold: number; ready: boolean }>;
}
```

#### `game:shop:offer`
Per-player (each player only sees their own shop).
```ts
{
  matchId: string;
  round: number;
  offers: Array<{
    offerId: string;
    unitId: 'fighter' | 'healer' | 'ranger' | 'tank';
    star: 0;
  }>;
}
```

#### `game:match:state`
Sent to both clients when roster changes (purchase, sell, place).
```ts
{
  matchId: string;
  round: number;
  yourSide: 'p1' | 'p2';
  roster: {
    // Board slot indexing: row-major order, slot 0..2 = row 0 (front), 3..5 = row 1 (middle), 6..8 = row 2 (back)
    //   col = slot % 3, row = floor(slot / 3)
    board: Array<{ instanceId: string; unitId: string; star: 0|1|2; hp: number; maxHp: number } | null>; // 9 slots (3 rows × 3 cols)
    bench:  Array<...>;                                                                           // 8 slots
    gold: number;
    hp: number;
  };
  opponent: {
    gold: number;
    hp: number;
    boardSummary: Array<{ unitId: string; star: 0|1|2 } | null>;  // 9 slots, no HP detail
  };
  readyCount: 0 | 1 | 2;
}
```

#### `game:combat:events`
**Batch of every combat tick event for one battle**, sent ONCE per battle. The Flutter client plays the events locally as animations, then acks with `game:match:combat_done`. The server emits this payload via Redis Pub/Sub `match:<id>:events` so all instances forward to their connected sockets.

```ts
{
  matchId: string;
  round: number;
  cycleCount: number;        // typically ≤ 30
  endedAt: number;           // epoch ms when engine finished
  events: CombatEvent[];     // full ordered list; usually 100–2000 events
}

type CombatEvent =
  | { type: 'attack';      cycle: number; tick: number; attacker: string; target: string;  damage: number; targetHpAfter: number }
  | { type: 'death';       cycle: number; tick: number; unit: string }
  | { type: 'revive';      cycle: number; tick: number; unit: string;  hpAfter: number }
  | { type: 'heal';        cycle: number; tick: number; target: string; by: string;  amount: number; targetHpAfter: number }
  | { type: 'lifesteal';   cycle: number; tick: number; unit: string;  amount: number; hpAfter: number }
  | { type: 'pierce';      cycle: number; tick: number; attacker: string; target: string;  damage: number }
  | { type: 'slow';        cycle: number; tick: number; target: string; by: string }
  | { type: 'cycle_end';   cycle: number }
  | { type: 'battle_end';  cycle: number; winner: 'p1' | 'p2' | null /* tie */ };
```

The 60-second combat-done timeout applies after this event is emitted. If at least one client fails to ack within 60 s, the server forces the next phase.

#### `game:match:damage`
End-of-round.
```ts
{
  matchId: string;
  round: number;
  damage: {
    p1: { wiped: boolean; tie: boolean; hpBefore: number; hpAfter: number; damageApplied: number };
    p2: { wiped: boolean; tie: boolean; hpBefore: number; hpAfter: number; damageApplied: number };
  };
  winner: 'p1' | 'p2' | 'tie' | null;
}
```

#### `game:match:end`
```ts
{
  matchId: string;
  winnerId: string | null;     // null on double 0 HP
  reason: 'hp_zero' | 'forfeit' | 'disconnect';
  final: { p1: { hp: number; gold: number }, p2: { hp: number; gold: number } };
}
```

#### `game:error`
```ts
{ code: string; message: string; clientActionId?: string }
```

### 2.2 Incoming — client → server

#### `game:matchmaking:join`
```ts
{ }
```

#### `game:matchmaking:leave`
```ts
{ }
```

#### `game:shop:buy`
```ts
{ round: number; offerIndex: number /* 0..4 */; clientActionId: string }
```

#### `game:shop:sell`
```ts
{ round: number; source: 'board' | 'bench'; slot: number /* 0..8 board, 0..7 bench */; clientActionId: string }
```

#### `game:shop:refresh`
```ts
{ round: number; clientActionId: string }
```

#### `game:shop:fuse`
```ts
{ round: number; unitId: string; clientActionId: string }
```

#### `game:match:place`
```ts
{
  round: number;
  unitInstanceId: string;
  target: 'board' | 'bench';
  slot: number;          // 0..8 board, 0..7 bench
  clientActionId: string;
}
```

#### `game:match:ready`
```ts
{ round: number; clientActionId: string }
```

#### `game:match:combat_done`
Client tells the server it's finished playing the `game:combat:events` batch locally and is ready for `game:match:damage`. Server waits for BOTH clients' acks (or 60 s timeout) before proceeding.

```ts
{ matchId: string; round: number; clientActionId: string }
```

## 3. Validation Rules

Server validates every incoming payload:

- `round` matches server's current round.
- `slot`/`offerIndex` within valid range.
- `unitInstanceId` exists in caller's roster.
- Source of funds / unit ownership.
- `clientActionId` not previously processed for this user.

Failure → `game:error` with an appropriate code.

## 4. Idempotency

Every shop/match action carries a `clientActionId` (UUID generated client-side). Server stores last processed `clientActionId` per user and ignores duplicates. Re-tries after network failures are safe.

## 5. Error Codes

| Code | Meaning |
|---|---|
| `auth.invalid` | Bad/missing token |
| `auth.expired` | Expired JWT |
| `rate.limited` | Too many actions |
| `match.not_found` | Unknown matchId |
| `match.not_your_turn` | Wrong phase for action |
| `shop.insufficient_gold` | Not enough gold |
| `shop.invalid_offer_index` | offerIndex out of range |
| `shop.refresh_used` | Already refreshed this phase |
| `place.slot_occupied` | Slot already taken |
| `place.slot_out_of_range` | Slot index invalid |
| `place.unit_not_owned` | unitInstanceId not in roster |
| `combat.internal` | Combat engine bug (should never fire) |
| `combat.not_in_battle` | `game:match:combat_done` sent when match is not in `battle` phase |
| `combat.lock_held` | Another instance is running combat for this match (informational; clients should retry shortly) |
