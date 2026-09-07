# Combat Specification

> Server-authoritative. Pure functions in `backend/src/game/`. Tick-based cycle model.

## 1. Cycle Model

Each battle phase is **≤ 30 cycles**. Each cycle is **100 ticks**.

### 1.1 Unit actions per cycle

For a unit with SPD `s` where 0 ≤ s ≤ 95:

```
cooldown      = 100 - s
actionsPerCycle = floor(100 / cooldown)
```

| Unit (default SPD) | Cooldown | Actions/cycle |
|---|---|---|
| Tank (0) | 100 | 1 |
| Fighter (20) | 80 | 1 |
| Healer (50) | 50 | 2 |
| Ranger (90) | 10 | 10 |

*SPD values are MVP placeholders; tune via playtest. SPD > 95 is forbidden.*

### 1.2 Action schedule within a cycle

For each tick `t = 1..100`:
1. Collect alive units whose scheduled action tick is `t` (i.e., `(cycleStartTick + cooldownDone) mod 100 == t mod 100`).
2. Order them per tie-break (Section 6).
3. For each, execute `unitAct(unit, state)`.

### 1.3 End of battle

At end of cycle `N`:
- If one side has no alive units → `battle_end` event with winner = that side's opposite.
- If `N == 30` and both sides have units → `battle_end` event with winner = `null` (tie).

The engine produces the WHOLE battle as a single `CombatEvent[]`. **The engine is a synchronous function that returns the array — it does not stream events**. The orchestrator (NestJS) takes the result and delivers it to clients in one batch (see §1.4).

### 1.4 Battle end flow (orchestrator ↔ engine ↔ clients)

```
[WS handler: phase = 'shop_place', both Ready OR timer expired]
  ↓
[Orchestrator]                              [Engine]                       [Redis]
  read runtime from HSET                                              Lua: phase_flip
  acquire combat-lock:<id> SET NX EX 30s                              (atomic)
  call engine.runBattle(state) → events: CombatEvent[]
  HSET match:<id>:combat-result events + EXPIRE 60
  PUBLISH match:<id>:events {round, events}                            ↓ fan-out
  ↓
  wait for:
    - combat-done:<id> HSET pushed by 2 clients  (Lua: combat_done ack)
    - OR 60s timeout (BullMQ delayed job expires)
  ↓
  apply damage (wipe or tie)
  HSET runtime {phase: 'resolved', ...}
  PUBLISH match:<id>:damage {...}
```

The engine itself never observes the network. It is a pure sync function (`runBattle(state): CombatEvent[]`) called once, then discarded. Everything multi-instance is in the orchestrator layer.

## 2. Targeting Algorithm

```
function pickTarget(attacker, state):
  enemies = state.enemyTeamOf(attacker).units.filter(u => u.alive)
  if enemies.isEmpty: return null                  // skip turn

  // 2★ global rules FIRST:
  if attacker.star == 2 and attacker.unitId == 'ranger':
    return lowestHp(enemies)                       // global lowest HP

  if attacker.unitId in ('fighter','tank','healer') and
     enemyHasAliveStar2Tank(state.enemyTeamOf(attacker)):
    tank2 = findAliveStar2Tank(state.enemyTeamOf(attacker))
    candidates = [tank2]
    // Prioritize but not absolute — fall through if below returns nothing.
    // (Practically: if tank2 is alive, restrict to it.)

  // Base rule: row → lane (3-row board: row 0 = front, 1 = middle, 2 = back)
  sameLane  = enemies.filter(u => u.position.col == attacker.position.col)
  frontRow  = sameLane.filter(u => u.position.row == 0)
  middleRow = sameLane.filter(u => u.position.row == 1)
  backRow   = sameLane.filter(u => u.position.row == 2)
  if frontRow.isNotEmpty:
    candidates = frontRow
  else if middleRow.isNotEmpty:
    candidates = middleRow
  else if backRow.isNotEmpty:
    candidates = backRow

  // If still nothing in same lane, fall back across lanes:
  if candidates is null or empty:
    // iterate col in 0,1,2 order; pick first non-empty row (front, then middle, then back)
    for col in [0,1,2]:
      colFront = enemies.filter(u => u.position.col == col and u.position.row == 0)
      if colFront.isNotEmpty: candidates = colFront; break
      colMiddle = enemies.filter(u => u.position.col == col and u.position.row == 1)
      if colMiddle.isNotEmpty: candidates = colMiddle; break
      colBack = enemies.filter(u => u.position.col == col and u.position.row == 2)
      if colBack.isNotEmpty: candidates = colBack; break

  // Unit-specific tie-breaker within candidates:
  if attacker.unitId == 'ranger':
    return lowestHp(candidates)
  else:
    return lowestColThenPosition(candidates)
```

### 2.1 Tie-breaker (within equal priority)

1. Lowest `position.col`.
2. Lowest `position.row` (front row 0 before middle row 1 before back row 2).
3. Lower `instanceId` (UUID/string compare) for total determinism.

## 3. Damage Application & Revive

```
function applyDamage(target, dmg, source):
  lethal = dmg >= target.hp
  if lethal and target.unitId == 'tank' and target.star >= 1 and not target.revivedThisRound:
    target.hp             = floor(target.maxHp * 0.5)
    target.revivedThisRound = true
    emit('revive', { unit: target.instanceId, hpAfter: target.hp })
    return                                              // tank didn't die

  target.hp -= dmg
  if target.hp <= 0:
    target.hp = 0
    target.alive = false
    emit('death', { unit: target.instanceId })

  emit('attack', { attacker: source.instanceId, target: target.instanceId,
                   damage: dmg, targetHpAfter: target.hp })
```

> The Revive handler runs in-tick. The cycle does **not** break.

## 4. Ability Effects

All effects emit a `combat:event` for the UI. The combat engine consumes/publishes events through a single `EventEmitter`; no side-effects on external state.

### 4.1 Fighter

After every successful attack (`dmg > 0`):
```
if star == 1: heal = floor(dmg * 0.05)
if star == 2: heal = floor(dmg * 0.10)
heal = max(0, min(heal, fighter.maxHp - fighter.hp))
fighter.hp += heal
emit('lifesteal', { unit: fighter.instanceId, amount: heal, hpAfter: fighter.hp })
```

### 4.2 Ranger

After `applyDamage`:
- `star == 1` (Pierce): find next alive enemy in same column, **directly** behind target (i.e. `row + 1` — adjacent). If exists, deal `floor(damage * 0.10)` and emit `pierce`. No further pierce beyond the adjacent row.
- `star == 2`: targeting already handled in §2 (global lowest HP). No additional event here.

### 4.3 Tank

- HP-revival handler — see §3.
- 2★ Prioritize — see §2 (overlays candidate filter).
- 2★ inherits 1★ Revive — the same `revivedThisRound` flag is used.

### 4.4 Healer

After `applyDamage` (which always lands ≥ 0 damage on a chosen target; if no target, skip attack but **still heal** below):

```
// Heal lowest-HP ally (any lane; can be self)
healTarget = lowestHp(fighter.team.units.filter(u => u.alive))
healAmount = min(10, healTarget.maxHp - healTarget.hp)
healTarget.hp += healAmount
emit('heal', { target: healTarget.instanceId, by: healer.instanceId,
               amount: healAmount, targetHpAfter: healTarget.hp })

if healer.star == 2:
  nextTarget = lowestHp(fighter.team.units.filter(u => u.alive and u != healTarget))
  if nextTarget:
    amt = min(10, nextTarget.maxHp - nextTarget.hp)
    nextTarget.hp += amt
    emit('heal', { ... })

// Slow debuff (1★+)
if healer.star >= 1 and lastAttackedEnemy != null:
  lastAttackedEnemy.slowActive  = true
  lastAttackedEnemy.slowBy      = healer.instanceId
  emit('slow', { target: lastAttackedEnemy.instanceId, by: healer.instanceId })
```

Slow effect on the target:
```
target.effectiveSpd = target.baseSpd * 0.7
```
Rounded to nearest int, clamped ≥ 0. Slow **persists until the Healer attacks again**, at which point the Healer clears `slowActive` on all units she slowed.

Implementation detail: store `slowActive: boolean` and `slowUntilHealerAct: healerId`. When Healer attacks (any future tick), she iterates her tracked targets and resets `effectiveSpd`.

### 4.5 Ability effects vs. multiple units

- Healer ally-targeting: any unit on the ally team, **regardless of lane** — consistent with the design "specific one with less health on her team only".
- Tank 2★ Prioritize: applies only to **enemies** of the Tank; allies of the Tank are unaffected.

## 5. Wipe Damage & Tie Damage

End-of-battle (called once after `battle_end` event):

```
function resolveEnd(battleResult, state):
  if battleResult.winner == null:                       // tie
    state.p1.hp = max(0, state.p1.hp - 5)
    state.p2.hp = max(0, state.p2.hp - 5)
    return

  loser = battleResult.winner == 'p1' ? state.p2 : state.p1
  idx = loser.wipeIndex ?? 0
  idx += 1
  if idx > 5: idx = 5
  dmg = idx * 5
  loser.wipeIndex = idx
  loser.hp = max(0, loser.hp - dmg)
```

| Wipe # | Damage |
|---|---|
| 1 | 5 |
| 2 | 10 |
| 3 | 15 |
| 4 | 20 |
| 5+ | 25 (cap) |

## 6. Tie-Tick Resolution

When two units share the same tick within a cycle:

1. Server generates a **random init** for the round using `state.roundSeed`. `initSide ∈ { 'p1', 'p2' }`.
2. Within the init side, order by:
   1. Higher SPD first.
   2. Position order (front-left → back-right): row, then col.
   3. `instanceId` for total determinism.
3. Within the non-init side, same sub-ordering.
4. Then the non-init side.

> `roundSeed` derives from `matchSeed + round`. Same match + inputs ⇒ identical order.

## 7. RNG Sources

| RNG | Seed source | Purpose |
|---|---|---|
| Shop offers | `matchSeed + round + playerId` | Same match ⇒ same offers per player. |
| Tie-tick init | `matchSeed + round` | Same match ⇒ same init ordering. |
| Battle | none (deterministic) | Pure combat, no RNG. |

All random consumed via a **seeded RNG injected at the engine entry point**. The combat engine has no `Math.random()`.

## 8. Edge Case Table

| # | Case | Resolution |
|---|---|---|
| E1 | Healer attacks when no enemy in range | If no enemies alive anywhere → turn ends; Healer still heals (lowest ally = self). |
| E2 | Tank 2★ dies mid-round | If `revivedThisRound` already true → dies permanently; subsequent enemies use normal targeting next cycle. |
| E3 | All units die in same tick | Both sides wipe → tie. Both take 5. |
| E4 | Multiple Ranger 2★ on board | Each independently picks global lowest HP. If both target same unit, both attack it. |
| E5 | Tank 2★ and Tank 1★ on same team | Tank 2★ applies global rule; Tank 1★ has separate Revive handler. (Single Tank entity: only one star per unit, so this is moot in practice.) |
| E6 | Slow vs attack cooldown | Slow does not prevent attack; just lengthens the target's cooldown. |
| E7 | Player places 0 units on board | Battle → wipe in 0 cycles; loser takes wipe damage. |
| E8 | Gold goes negative from overspend | Server rejects with `shop.insufficient_gold`. Gold never < 0. |
| E9 | Sell during battle phase | Rejected — sell only during `shop_place` phase. |
| E10 | Disconnect during battle | Per current spec: instant forfeit. (NFR-12 lists grace period as future option.) |
| E11 | Two units same instanceId | Server rejects shop/place actions on stale instanceIds (always uses the live roster copy). |
| E12 | Healer with 0★ has Slow disabled | Confirmed. Only 1★+. |
| E13 | Heal on full-HP target | Heal amount capped to `maxHp - hp`. If 0, no `heal` event emitted. |
| E14 | Healer 2★ only one ally alive | Heals that ally once with first tick; second heal target is `null`, omitted. |
| E15 | Fighter Lifesteal would overheal | Cap at maxHp. |
| E16 | Multiple Tank 2★ on a team | Each adds another prioritize filter (only the alive one matters). |

## 9. Performance Budget

- Per cycle: 100 ticks × up to 20 actions/tick = ~2000 ops/cycle.
- 30 cycles × ~2000 = ~60 000 ops/match.
- Engine returns the full array in milliseconds on a single thread.
- Network latency dominates: from `phase: battle` flip to `game:combat:events` echoed to clients must be < 500 ms p95 (NFR-14).

## 10. Determinism Tests

For each combat function:

- Same `state` + same actions ⇒ identical output.
- Same `matchSeed` ⇒ identical shop and tie-tick init.
- Backend must store `matchSeed` per match.

Combat engine `engine.spec.ts` covers:

- Each ability at each star level — kill, lifesteal, heal, slow, pierce, ranger global, tank revive, tank prioritize.
- Targeting tie-breaker matrix.
- Edge cases E1–E16.
- A fixed-seed full-battle fixture (regression) — guarantees identical `CombatEvent[]` byte-for-byte.

Coverage target: ≥ 90 % lines in `backend/src/game/`.
