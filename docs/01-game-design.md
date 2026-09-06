# Auto Chess — Game Design

> 2-player auto-chess on a 6-cell board. Last player standing wins.
> University project; 3 people; 1-month MVP.

## 1. Core Loop

```
[Matchmaking]
     ↓
[Round N] → [40s Shop+Place] → [Battle (≤30 cycles)] → [Damage]
     ↓
   ...
     ↓
[Match ends] ← a player's HP hits 0, or a player disconnects
```

A match has **no fixed round limit**. Each player starts at **100 HP**. Damage reduces HP. When HP = 0 the player loses.

## 2. Board Layout

Each player has their own 2×3 grid:

```
        Bob's perspective (top)
   ┌────┬────┬────┐
   │    │    │    │   back row
   │    │    │    │   front row (closest to enemy)
   ╞════════════════╡
   │    │    │    │   front row (closest to enemy)
   │    │    │    │   back row
   └────┴────┴────┘
        Alice's perspective (bottom)
```

Units in the same column fight each other across the front line. **Front row is closer to the enemy; back row is behind.**

- **Lane** = column index (0, 1, 2).
- Each player has independent row numbering: their row 0 = own front row; row 1 = own back row.

## 3. Units

Four unit types. Each has stats and a star-upgrade path.

| Unit | Cost | HP | ATK | SPD | Role |
|---|---|---|---|---|---|
| Fighter | 1g | 100 | 15 | 20 | All-rounder (sustain) |
| Healer | 1g | 70 | 6 | 50 | Support / sustain |
| Ranger | 2g | 60 | 12 | 90 | DPS carry |
| Tank | 2g | 150 | 8 | 0 | Frontline |

*MVP placeholder stats; tune via playtest.*

### 3.1 Base targeting (all units)

When a unit picks an attack target:

1. Filter to **enemy** units that are **alive**.
2. Prefer **front row** over back row.
3. Within chosen row, prefer **same lane** (same column as attacker). If no target in same lane, fall back to other lanes (deterministic order: lane 0 → 1 → 2).
4. Within candidates of equal priority, apply unit-specific tie-breaker.

### 3.2 Unit-specific targeting

- **Fighter / Tank / Healer**: lowest column index wins ties. Within same column, **front row** before back row. Then lower `instanceId`.
- **Ranger**: among candidates, pick **lowest current HP**. Tie-break by lowest column index.
- **Ranger 2★**: ignore lane rules entirely; pick **lowest-HP enemy anywhere on the enemy team**. Tie-break by lowest column index.

### 3.3 Star Upgrades (fusion)

```
0★ + 0★    →  1★
1★ + 1★    →  2★
```

Two copies of a unit at the same star level consume both and yield **one** copy at the next level. Star level affects stats and unlocks abilities.

Star-upgrade flow:
- Buying from shop auto-fuses with an existing roster copy when possible.
- A "Fuse now" button explicitly fuses two roster copies.

### 3.4 Abilities (per star level)

#### Fighter
- **0★**: no ability.
- **1★**: **Lifesteal 5%** — heal self for `floor(damage * 0.05)` after each successful attack.
- **2★**: **Lifesteal 10%** — heal self for `floor(damage * 0.10)` after each successful attack.

#### Ranger
- **0★**: no ability.
- **1★**: **Pierce** — 10% of damage spills to the next alive enemy directly behind the primary target in the same lane. If no such unit exists, the pierce event is omitted.
- **2★**: **Global Targeting** — ignores lane rules; picks the lowest-HP enemy across the enemy team.

#### Tank
- **0★**: no ability.
- **1★**: **Revive** — when HP would drop to 0, revive with HP = `floor(maxHp * 0.5)`. **Once per round**. Subsequent lethal damage kills normally.
- **2★**: **Prioritize** — while a 2★ Tank is alive on its team, enemy attackers prefer the Tank as their target over their normal lane-priority rule. If the Tank is dead, unreachable, or no candidate is the Tank, fall back to normal targeting.
  - **Inherits 1★ Revive.**

#### Healer
- **0★**: on every successful attack, heal her team's **lowest-HP ally** (any lane; can include herself) for **10 HP** (capped at maxHp).
- **1★**: on every attack, apply **Slow** to the unit most recently attacked by this Healer. Slow sets `effectiveSpd = SPD * 0.7` for **target's cooldown computation**, lasting **until the Healer attacks again**.
- **2★**: heal **two** lowest-HP allies (10 HP each) on every successful attack.

> *Healer's attack targeting* follows the base rule (front row, same lane, fall back across lanes).
> *Healer's heal target* is **her own team's** lowest-HP ally, any lane.

## 4. Shop

Each round, every player receives **5 random unit offers**. Each player has their own shop (different RNG seed per player, but seeded by matchSeed for replay).

### 4.1 Pool (MVP)

| Unit | Probability | Cost |
|---|---|---|
| Fighter | 40% | 1g |
| Healer | 40% | 1g |
| Ranger | 15% | 2g |
| Tank | 5% | 2g |

All offers are 0★. Star upgrades happen only via fusion of two same-star copies.

### 4.2 Shop actions

- **Buy**: pay cost (in gold), unit enters roster.
- **Sell**: recover **100%** of unit cost. Unit leaves roster.
- **Refresh**: reroll all 5 offers. Free **once per merged phase**.
- **Auto-fuse** when buying a duplicate, or via a "Fuse now" button.

## 5. Phases per Round

### 5.1 Merged Shop + Place phase (40 s)

Players see their shop and board at the same time. They can:

- Buy / sell / refresh / fuse units.
- Drag units between **board** and **bench** (positions persist).
- Place units on their 2×3 grid.

If **both players** click **Ready**, battle starts early. Otherwise battle auto-starts at the 40 s timer expiry.

### 5.2 Battle phase

The server simulates the battle and emits WebSocket events. Battle ends when:

- One side's units are all dead → winner determined; loser takes **wipe damage**.
- **30 cycles** elapse with both sides alive → **tie**; **both** players take **5 damage**.

See `docs/05-combat-spec.md` for the full combat algorithm.

### 5.3 Resolve phase

- Compute damage.
- Award **+5 g** to each player.
- Start the next round.

## 6. Damage & Win Condition

### 6.1 Wipe damage (escalating, capped)

| Wipe # | Damage |
|---|---|
| 1 | 5 |
| 2 | 10 |
| 3 | 15 |
| 4 | 20 |
| 5+ | 25 (cap) |

Each wipe advances the counter by one (cap at index 5). Counter is per-match and per-player.

### 6.2 Tie damage

5 to each player; does **not** advance the wipe counter for either side.

### 6.3 Win condition

- Player HP ≤ 0 → loses match; opponent wins.
- Player disconnects → loses match; opponent wins (no damage applied).
- Surrender → opponent wins. *(Optional, post-MVP.)*

## 7. Roster Constraints

- **Board**: 6 slots (2 rows × 3 cols).
- **Bench**: 8 slots.
- Positions persist across rounds unless the player moves a unit during the next merged phase.

## 8. Matchmaking

Two-player queue. Server matches by nearest rating; if no compatible opponent within 30 s, any two queued players are matched.

## 9. Out of Scope (MVP)

These are intentionally cut to fit 1-month timeline. Keep them in mind for v2:

- 3+ player modes.
- Items.
- XP / level-up system.
- Spectator mode.
- Replay (other than seeded determinism).
- Cosmetics / animation polish.
- Multi-region deployment.
- Push notifications.
- Surrender button.
- Anti-cheat measures beyond authoritative server + WS payload validation.
