# Design Spec — Auto Chess Mobile

> Deliverable for issue [#106 — P0-FE-00](https://github.com/JaJoJi/mobile-final-project/issues/106).
> Source of truth for every UI ticket (P0-FE-03/04/05/06, P2-FE-*). If a screen contradicts this doc, this doc wins — or the doc gets updated in the same PR.

**Audience: humans *and* AI agents.** Everything here is written so a coding agent can produce a screen without asking follow-up questions: token names are exact, wireframes are literal, every screen lists its data source and its four states.

**Related docs**
| Doc | What it locks |
|---|---|
| [`07-design-kit.html`](./07-design-kit.html) | **visual reference** — palette, roster, type, motion, and all 6 screens rendered as a real mockup. Download and open in a browser (no build step). Read this alongside the wireframes below when a text description isn't enough |
| `01-game-design.md` | board 3×3 (updated from 2×3), units, stars, abilities |
| `02-requirements.md` | FR/NFR (40 s phase, authoritative server, disconnect = loss) |
| `04-api-contracts.md` | REST + WS payloads each screen renders |
| `05-combat-spec.md` | combat events the battle screen replays |
| `../../guide/master_ux-uidesign.md` | the long-form UX rulebook this spec is an instance of |

---

## 0. How to use this doc

**Building a screen?** → §4 (that screen) → §2 (tokens) → §3 (components) → §9 checklist.
**Adding a widget?** → §3. If it is used by ≥ 2 screens it belongs in `core/widgets/`.
**Picking a colour / size / duration?** → §2 only. Never invent a value.

Priority tags: **[MUST]** = merge blocker · **[SHOULD]** = default, deviation needs a code comment · **[MAY]** = optional.

---

## 1. Principles & information hierarchy

1. **Server is the truth, UI is a view.** Combat, damage and gold are never computed client-side (NFR-1). The UI may *predict* an action (§5.3) but must reconcile.
2. **Feedback under 100 ms.** Every tap changes something visually immediately, even while the socket round-trip is in flight.
3. **The board is the hero.** During a match, ~80 % of attention is on the board; the HUD gets the remaining 20 %, so the HUD speaks in shapes, colour and fixed positions — not sentences.
4. **Never colour-only.** Team, HP severity, win/loss all carry an icon, a label or a position as well.
5. **Prevent, don't scold.** Disable + explain (“ทองไม่พอ”) beats letting a player tap into an error.

Attention priority used to lay out every in-match screen:

```
P0 — always visible : phase timer · my HP · opponent HP
P1 — visible in phase: gold · my 3×3 board · 5-card shop · Ready button
P2 — on demand      : bench (8) · unit detail · last-round damage
P3 — behind a menu  : settings · profile · history · logout
```

---

## 2. Foundations (tokens)

Values live in `mobile/lib/core/theme/`. **[MUST]** No literal colour, font size, padding, radius or duration anywhere under `features/**`.

### 2.1 Colour tokens

Base palette is generated from one seed so tonal harmony and contrast come for free:

```dart
const seed = Color(0xFF3F51B5); // indigo — matches current main.dart
final lightScheme = ColorScheme.fromSeed(seedColor: seed);
final darkScheme  = ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.dark);
```

Semantic names required by the issue, and how each maps to a Material 3 role. **[MUST]** Read colours through the role, not the hex; the hex column is documentation of what the role resolves to.

| Semantic token | M3 role (`Theme.of(context).colorScheme`) | Light | Dark |
|---|---|---|---|
| `surface.background` | `surface` | `#FCF8FF` | `#131318` |
| `surface.card` | `surfaceContainer` | `#F0EDF4` | `#1F1F25` |
| `surface.cardRaised` | `surfaceContainerHigh` | `#EAE7EF` | `#2A2930` |
| `surface.divider` | `outlineVariant` | `#C7C5D0` | `#46464F` |
| `surface.border` | `outline` | `#77767F` | `#918F9A` |
| `text.primary` | `onSurface` | `#1B1B21` | `#E5E1E9` |
| `text.secondary` | `onSurfaceVariant` | `#46464F` | `#C7C5D0` |
| `text.inverse` | `onPrimary` | `#FFFFFF` | `#1B2678` |
| `accent.primary` | `primary` | `#4A5AC0` | `#B9C3FF` |
| `accent.container` | `secondaryContainer` | `#E0E0F9` | `#43464F` |
| `state.danger` | `error` | `#BA1A1A` | `#FFB4AB` |
| `state.dangerContainer` | `errorContainer` | `#FFDAD6` | `#93000A` |

Game-only colours have no M3 role, so they live in a `ThemeExtension` — **[MUST]** never as loose constants:

| Game token | Light | Dark | Used by |
|---|---|---|---|
| `state.success` (win) | `#256C2E` | `#8BD98F` | result screen, history win rows |
| `state.warning` | `#8A5000` | `#FFB95C` | reconnecting banner, timer < 10 s |
| `ally` | `#3F51B5` | `#B9C3FF` | my units, my HP bar |
| `enemy` | `#B3541E` | `#FFB68C` | opponent units, opponent HP bar |
| `hp.high` (> 50 %) | `#256C2E` | `#8BD98F` | unit + player HP bars |
| `hp.mid` (20–50 %) | `#8A5000` | `#FFB95C` | " |
| `hp.low` (< 20 %) | `#BA1A1A` | `#FFB4AB` | " |
| `gold` | `#7A5A00` | `#F5C542` | gold counter, unit price |
| `unit.tier.1star` | `#5B6BC7` | `#B9C3FF` | 1★ frame + star glyphs |
| `unit.tier.2star` | `#B58A00` | `#F5C542` | 2★ frame + gold glow |
| `board.cell.empty` | `#E7E4EC` | `#26252C` | empty board slot fill |
| `board.cell.validDrop` | `#C7D0FF` | `#3A4370` | drop target highlight |

```dart
// core/theme/game_theme.dart
@immutable
class GameTheme extends ThemeExtension<GameTheme> {
  final Color success, warning, ally, enemy;
  final Color hpHigh, hpMid, hpLow, gold, star1, star2;
  final Color boardCellEmpty, boardCellValidDrop;
  const GameTheme({required this.success, /* ... */});
  @override GameTheme copyWith({/* ... */});
  @override GameTheme lerp(ThemeExtension<GameTheme>? o, double t);
  static GameTheme of(Brightness b) => b == Brightness.light ? _light : _dark;
}

// usage
final g = Theme.of(context).extension<GameTheme>()!;
```

Rules **[MUST]**
- Text always uses the `onX` colour of the surface it sits on.
- Body text ≥ 4.5:1 contrast, large text and meaningful icons/borders ≥ 3:1. Verify with a contrast checker before merging (§9).
- Text over sprites/effects gets a scrim (60 % opaque surface) or a 1 dp outline.
- Never `#000000` as a background in dark theme — use `surface.background`.
- Dark-mode toggle ships in P1-FE-02, but both themes are defined **now** and the match screen is always rendered with the dark scheme (`Theme(data: darkTheme, …)` around that subtree) **[SHOULD]**.

### 2.2 Typography

Font family: **Inter** for Latin + **Noto Sans Thai** fallback (both ship Thai-safe metrics). Numbers use `FontFeature.tabularFigures()` wherever they tick (HP, gold, timer) **[MUST]**.

| Role | Token (`textTheme`) | Size / weight / line-height | Used for |
|---|---|---|---|
| h1 | `displaySmall` | 36 / w700 / 1.2 | WIN · LOSE |
| h2 | `headlineMedium` | 28 / w600 / 1.25 | screen titles |
| h3 | `titleLarge` | 22 / w600 / 1.3 | modal titles, section heads |
| subtitle | `titleMedium` | 16 / w600 / 1.4 | unit name, list row title |
| body | `bodyLarge` | 16 / w400 / 1.5 | **default text everywhere** |
| body-sm | `bodyMedium` | 14 / w400 / 1.5 | secondary description |
| button | `labelLarge` | 14 / w600 / 1.2 | button labels |
| caption | `labelMedium` | 12 / w500 / 1.4 | timestamps, helper text |
| micro | `labelSmall` | 11 / w500 / 1.3 | badges only |

- **[MUST]** In-match text (HUD, cards, buttons) ≥ 16 sp.
- **[MUST]** Thai line-height ≥ 1.4 (stacked vowels).
- **[MUST]** No `fontSize:` in `features/**`; no global `textScaler` override. If the HUD breaks at huge scales, clamp *only* that subtree: `MediaQuery.withClampedTextScaling(minScaleFactor: 1.0, maxScaleFactor: 1.3, child: hud)`.

### 2.3 Spacing, radius, elevation

Spacing scale (4 dp base) — **[MUST]** no other values:

| Token | dp | Use |
|---|---|---|
| `xxs` | 2 | badge inner |
| `xs` | 4 | icon ↔ label |
| `sm` | 8 | gap between cards/buttons |
| `md` | 12 | card padding |
| `lg` | 16 | **screen padding (default)** |
| `xl` | 24 | between sections |
| `xxl` | 32 | around empty-state art |
| `huge` | 48 | above a terminal CTA |

| Radius | dp | Use | | Elevation | Use |
|---|---|---|---|---|---|
| `xs` | 4 | badge, chip | | `level0` (0) | page background |
| `sm` | 8 | text field, board cell | | `level1` (1) | card |
| `md` | 12 | unit card, shop card, button | | `level2` (3) | selected / dragging card |
| `lg` | 16 | modal, bottom sheet | | `level3` (6) | modal, sheet |
| `full` | 999 | avatar, pill, timer ring | | | |

### 2.4 Motion tokens

| Token | ms | Applied to |
|---|---|---|
| `short2` | 100 | ripple, colour change, press state |
| `short4` | 200 | icon toggle, **HP bar tween**, card scale 1.0→1.05 (150–200) |
| `medium2` | 300 | **page transition**, toast in/out, snap-to-slot |
| `medium4` | 400 | modal in, card expand |
| `long2` | 500 | phase change (shop → battle) |
| `extraLong2` | 800 | match-end cinematic |

| Easing | Curve | When |
|---|---|---|
| `emphasized` | `Cubic(0.2, 0.0, 0.0, 1.0)` | default for anything the player notices |
| `emphasizedDecelerate` | `Cubic(0.05, 0.7, 0.1, 1.0)` | element entering the screen |
| `emphasizedAccelerate` | `Cubic(0.3, 0.0, 0.8, 0.15)` | element leaving the screen |

Rule: **enter = decelerate and longer, exit = accelerate and shorter.**
**[MUST]** Anything longer than 400 ms is skippable by tapping, and all decorative motion is dropped when `MediaQuery.disableAnimationsOf(context)` is true (data still shows, instantly).

---

## 3. Component library

Every component below lives in `mobile/lib/core/widgets/`. Variants/sizes/states are exhaustive — if a screen needs a state not listed here, add it here first.

### 3.1 `AppButton`

| Axis | Values |
|---|---|
| Variants | `primary` (`FilledButton`) · `secondary` (`FilledButton.tonal`) · `danger` (`FilledButton` + `state.danger`) · `ghost` (`TextButton`) |
| Sizes | `sm` 40 dp · `md` 48 dp (default) · `lg` 56 dp (in-match actions) |
| States | `default` · `pressed` · `disabled` · `loading` |

| State | Spec |
|---|---|
| default | fill `accent.primary`, label `text.inverse` `labelLarge`, radius `md`, padding `lg` horizontal |
| pressed | ripple + 8 % overlay, `short2` |
| disabled | fill `onSurface @12 %`, label `onSurface @38 %`, **no** ripple, **[MUST]** reason shown via `Tooltip` or helper text below |
| loading | 16 dp `CircularProgressIndicator` replaces the label, width frozen, button non-tappable **[MUST]** (double-submit guard) |

**[MUST]** Labels are verbs (“เข้าสู่ระบบ”, “ค้นหาคู่แข่ง”) — never “OK”/“Submit”. Primary button per screen: exactly one.

### 3.2 `AppCard`

Variants `flat` (level1) · `raised` (level2, for selected/dragging) · `interactive` (adds `InkWell` + ripple).
Padding `md`, radius `md`, fill `surface.card`, border 1 dp `surface.divider` only in `flat` on light theme.
States: `default` · `selected` (2 dp `accent.primary` border) · `disabled` (40 % opacity) · `dragging` (scale 1.05, level2).

### 3.3 `AppTextField`

`OutlineInputBorder` radius `sm`, always a floating `labelText` (**[MUST]** placeholder is not a label).
States: `default` (border `surface.border`) · `focused` (2 dp `accent.primary`) · `error` (2 dp `state.danger` + message below in `bodyMedium`) · `disabled` (fill `surface.card`, 38 % text).
**[MUST]** Set `keyboardType`, `textInputAction`, `autofillHints`; validate on submit/blur, not per keystroke; password fields ship a visibility toggle (already in `login_screen.dart`).

### 3.4 `HealthBar`

```
 ┌──────────────────────────────┐
 │██████████████░░▓▓            │  ▓ = "ghost" of damage just taken
 └──────────────────────────────┘
  62 / 100                        ← always show numerals too
```

| Prop | Spec |
|---|---|
| Sizes | `sm` 4 dp (over a unit) · `md` 8 dp (player HUD) · `lg` 12 dp (result screen) |
| Fill | `hp.high` > 50 % · `hp.mid` 20–50 % · `hp.low` < 20 % |
| Track | `surface.divider`, radius `full` |
| Tween | width animates `short4` (200 ms) with `emphasized` **[MUST]** |
| Ghost | the lost segment stays `state.danger @40 %` for 500 ms, then collapses |
| Low HP | < 20 % pulses scale 1.0→1.04 once per second + a warning icon (never colour alone) **[MUST]** |
| a11y | `Semantics(label: 'พลังชีวิต 62 จาก 100')` |

### 3.5 `UnitAvatar`

Renders one unit anywhere (shop, bench, board, replay).

```
┌───────────────┐
│  ★★           │ ← star glyphs, unit.tier.* colour
│   ◆  (sprite) │ ← MVP: shape+colour placeholder (§6)
│               │
│ Ranger    2g  │ ← name titleMedium · price labelLarge + gold icon
│ 60·12·90      │ ← HP·ATK·SPD, tabular figures, bodyMedium
└───────────────┘
```

| Axis | Values |
|---|---|
| Sizes | `sm` 48 dp (bench chip) · `md` 64×96 dp (board) · `lg` 88×132 dp (shop card) |
| Variants | `shop` (shows price) · `bench` · `board` (shows HP bar `sm`) · `replay` (no price, shows floating damage) |
| States | `default` · `selected` (border 2 dp `accent.primary`) · `unaffordable` (40 % dim + price in `state.danger`) · `dragging` · `fusable` (glow `unit.tier.2star` + “รวมได้” badge) · `dead` (grayscale + 40 % opacity) |

**[MUST]** Fixed `AspectRatio` so grids never reflow; long-press opens the unit detail sheet.

### 3.6 `PhaseTimerRing`

Circular countdown, 56 dp, stroke 6 dp, plus the numeral in the middle (`titleLarge`, tabular).

| State | Spec |
|---|---|
| normal | stroke `accent.primary`, sweeps down over the phase |
| urgent (≤ 10 s) | stroke `state.warning`; ≤ 5 s stroke `state.danger` + pulse 1.0→1.08 per second + light haptic at 5/3/2/1 |
| waiting | after 0, switches to indeterminate + label “รอเซิร์ฟเวอร์…” **[MUST]** (never freeze at 0) |

**[MUST]** Driven by a deadline, not by decrementing a counter — see §5.2.

### 3.7 `AppToast` (snackbar)

Floating, radius `md`, 4 s, one line + optional action.
Variants: `info` (`surface.cardRaised`) · `success` (`state.success` icon) · `danger` (`state.danger` icon).
**[MUST]** Never used for form validation errors (those are inline) and never during a timed phase — use the in-match banner instead.

### 3.8 `AppModal`

`AlertDialog` (confirm) / `showModalBottomSheet` (detail, with drag handle, radius `lg` top corners).
**[MUST]** Destructive confirms put the safe action on the left and default focus; **[MUST]** no modal opens while a phase timer is running — the match screen uses a top banner or a translucent overlay that keeps the board visible.

### 3.9 `AppTabBar`

Used on `/history` (All · Wins · Losses) and `/profile`.
Height 48 dp, indicator 3 dp `accent.primary`, label `labelLarge`, selected `text.primary` / unselected `text.secondary`, each tab ≥ 48 dp wide with an icon + text (never colour alone).

### 3.10 State views (`state_views.dart`)

| Widget | Contract |
|---|---|
| `SkeletonBox` / `SkeletonList` | mirrors the real content’s shape, fill `surface.cardRaised`, 1200 ms shimmer, shimmer disabled under reduced-motion |
| `EmptyView` | icon + one sentence explaining the emptiness + one action button **[MUST]** all three |
| `ErrorView` | icon + human message + **“ลองอีกครั้ง”** button **[MUST]** always an exit |
| `ConnectionBanner` | sticky top banner: `connecting`/`reconnecting` (warning) · `disconnected` (danger + retry + countdown) |

Loading choice **[MUST]**: < 300 ms show nothing · 300 ms–1 s spinner in place · > 1 s or known shape → skeleton · user-triggered action → spinner inside that button.

---

## 4. Screen inventory

Common frame for every screen **[MUST]**: `Scaffold` → `SafeArea` → padding `lg`; forms inside `SingleChildScrollView`; `AppScaffold` injects the `ConnectionBanner`.
Routes are named routes in `main.dart` (`onGenerateRoute` for parameterised ones).

### 4.1 `/login` — Sign in

**Purpose**: authenticate an existing player. **Data**: `POST /auth/login`.

```
+--------------------------------------+
|                                      |
|            [ ♜  64dp ]               |  logo, accent.primary
|            Auto Chess                |  h2
|          เข้าสู่ระบบเพื่อเล่น           |  body, text.secondary
|                                      |
|  +--------------------------------+  |  AppTextField(email)
|  | อีเมล                          |  |
|  +--------------------------------+  |
|  +--------------------------------+  |  AppTextField(password, obscure)
|  | รหัสผ่าน                 [ 👁 ] |  |
|  +--------------------------------+  |
|  ! อีเมลหรือรหัสผ่านไม่ถูกต้อง        |  inline error, state.danger
|                                      |
|  [       เข้าสู่ระบบ (primary)     ]  |  AppButton lg, full width
|                                      |
|      ยังไม่มีบัญชี?  สมัครสมาชิก       |  AppButton ghost
+--------------------------------------+
```

**Tree**: `AppScaffold > SingleChildScrollView > Column[ Logo, Title, Subtitle, AppTextField×2, InlineError?, AppButton(primary), AppButton(ghost) ]`

| State | UI |
|---|---|
| default | button enabled once both fields non-empty |
| loading | button `loading`, fields disabled (existing `_loading` flag wires here) **[MUST]** |
| error | inline text above the button, from `AuthException` → Thai copy (§7) |
| empty | n/a |

Notes: `textInputAction.next → done`, done submits; `autofillHints` email/password; keyboard must not cover the button (scroll view).

### 4.2 `/register` — Create account

**Purpose**: create an account. **Data**: `POST /auth/register`.
Fields: username (3–20, `^[a-zA-Z0-9_]+$`), email, password (≥ 8, with a strength/length hint), confirm password.

```
+--------------------------------------+
|  ←  สมัครสมาชิก                       |  AppBar + back
|  +---------------------+  ชื่อผู้ใช้    |
|  +---------------------+  อีเมล        |
|  +---------------------+  รหัสผ่าน     |
|     • อย่างน้อย 8 ตัวอักษร             |  helper, caption
|  +---------------------+  ยืนยันรหัสผ่าน|
|                                      |
|  [        สมัครสมาชิก (primary)     ]  |
|        มีบัญชีแล้ว?  เข้าสู่ระบบ        |
+--------------------------------------+
```

States mirror `/login`. **[MUST]** On submit show *all* field errors at once and scroll to the first one. `409 username/email taken` maps to an inline error on that field, not a toast.

### 4.3 `/lobby` — Home + matchmaking

**Purpose**: the hub — see who you are, start a match. **Data**: `GET /user/me`, WS connection state, `game:matchmaking:join|leave`.

```
+--------------------------------------+
|  Auto Chess          [🕘] [👤]        |  history · profile (48dp each)
|  ● เชื่อมต่อแล้ว                       |  dot + text (never colour alone)
|                                      |
|      ┌──────────────────────┐        |
|      │  alice               │        |  AppCard: name h3
|      │  เรตติ้ง 1000         │        |  rating + W/L
|      │  ชนะ 4 · แพ้ 2        │        |
|      └──────────────────────┘        |
|                                      |
|          [ board art / logo ]        |
|                                      |
|                                      |
|  [      ค้นหาคู่แข่ง (primary lg)   ]  |  thumb zone, bottom third
+--------------------------------------+
```

Queueing replaces the CTA in place (no navigation):

```
|      กำลังหาคู่แข่ง...  00:12          |  count-UP, indeterminate ring
|  [        ยกเลิก (secondary)       ]  |
```

| State | UI |
|---|---|
| loading | skeleton user card; CTA disabled |
| socket disconnected | CTA disabled + `ConnectionBanner` “กำลังเชื่อมต่อเซิร์ฟเวอร์” **[MUST]** |
| queueing | elapsed timer counting **up**, indeterminate animation — **[MUST]** never a fake percentage; > 30 s copy changes to “ยังหาคู่ไม่ได้ กำลังค้นหาต่อ…” |
| matched | opponent card for 1.5 s (`long2` transition) → `/match/:id` |
| error | `ErrorView` with retry |

### 4.4 `/match/:matchId` — In-game (the screen that matters)

**Purpose**: play one match. **Data**: `game:match:phase`, `game:shop:offer`, `game:match:state`, `game:combat:events`, `game:match:damage`, `game:match:end`.

#### 4.4.0 Why this layout — the board grew, the screen didn't

The board went from 2×3 (6 slots) to **3×3 (9 slots)**. Stacking two full 3×3 boards, an 8-slot bench, a 5-card shop and a HUD on a 360×640 screen the naive way is exactly how this genre gets accused of feeling like a spreadsheet. Teamfight Tactics' own UI team hit this same problem shipping to mobile and solved it with a small set of repeatable moves — we apply the same four here **[MUST]**:

| Technique | Where TFT/mobile auto-chess does it | Applied here |
|---|---|---|
| **Collapse the thing you're not acting on** | TFT keeps round/stage/timer in one strip and layers deeper stats behind a click, rather than surfacing everything at once | Opponent's board renders as a **1-row icon strip**, not a second mirrored 3×3 grid. Full board is one tap away (bottom sheet), because during shop+place you *act on your board*, not theirs |
| **Show ownership/upgradability as a glow, not a label** | Auto Chess Mobile animates a shop card's background when you already own that unit and it's fusable, instead of printing text | Shop cards get a **gold ring** when fusable / already-owned — no extra badge row eating vertical space |
| **Layer detail behind interaction, not always-on text** | TFT trait icons stay simple at small size; full trait tooltips only appear on hover/tap | Board tiles show **shape + star pips only** (no ATK/SPD text on the tile). Full stats appear on **long-press**, in the same bottom sheet used for the opponent board |
| **One HUD strip, not two** | Stage/round/timer condensed to a single top-of-screen strip so it reads at a glance without competing with the board | Both players' HP flank a single **PhaseTimerRing** in one row — not a HP bar row *plus* a separate timer row |

Net effect: the 50% bigger board gets the vertical space the opponent's mirrored board used to take, and per-tile clutter goes down even though slot count went up.

Portrait layout, shop+place phase (40 s):

```
+---------------------------------------------+
| ❤ 78 (คุณ)      ⏱( 23 )      bob ❤ 62   [≡] | one HUD strip — P0, always visible
+---------------------------------------------+
| scout: bob's board  [◆][◇][ ]            ›  | P2 — collapsed opponent strip, tap → sheet
+---------------------------------------------+
|  ทีมของคุณ · รอบ 3                    6/9   | P1 board header + fill count
|      back  ┌────┬────┬────┐                |
|            ├────┼────┼────┤                |
|      front │ ◆★★│ ▲★ │    │  ← enemy       | P1 — front row nearest enemy, always on top
|            └────┴────┴────┘                |
+---------------------------------------------+
| ▾ ม้านั่ง (3/8)     [◆][●][▲]           ›   | P2 — collapsed tray, tap to expand full 8
+---------------------------------------------+
| ร้านค้า  [1g][2g◆owned][1g][2g][1g]  ⟳ 2g   | P1 — owned/fusable card rings gold
| 💰 8                  [     พร้อม (lg)   ]   | P1 gold + Ready (thumb zone)
+---------------------------------------------+
```

Battle phase — the shop/bench/opponent-strip block is replaced, input is locked:

```
| ⚔ กำลังต่อสู้ · รอบ 3      [1x][2x] [ข้าม]  | speed + skip (always reachable)
|  ▰▰▰▰▰▰▱▱▱▱  replay progress                |
|  (both boards now shown full, damage floats) | full opponent board only appears here —
+---------------------------------------------+ battle is the moment both boards matter equally
```

**[MUST]** The opponent's board is drawn in full **only during battle** (both sides matter equally then) and **on demand** during shop+place (tap the scout strip → bottom sheet, dismiss returns focus to your own board). Never render two full 3×3 grids simultaneously during shop+place — that is the layout this redesign replaces.

**Tree**: `AppScaffold > Column[ MatchHud(HealthBar×2, PhaseTimerRing, MenuButton), OpponentScoutStrip(tap→sheet), BoardGrid(9 × UnitAvatar|EmptySlot, longPress→detailSheet), BenchTray(collapsed: 3 chips + count, expand→8), ShopRow(5 × UnitAvatar(ownedRing) + RefreshButton), ActionBar(GoldCounter, ReadyButton) ]`

| State | UI |
|---|---|
| loading (joining) | full-screen skeleton of the board + “กำลังเข้าสู่แมตช์…” |
| shop_place | as drawn; all actions optimistic (§5.3) |
| battle | inputs locked except speed/skip **[MUST]**; replay per §5.4 |
| resolved | 1.5 s overlay “คุณเสีย 12 HP” from `game:match:damage`, board still visible |
| finished | route-replace to the result view (§4.5) |
| ws error | in-match banner from `game:error` — **[MUST]** never kick the player out of the match |
| disconnected | blocking overlay “การเชื่อมต่อหลุด — แมตช์นี้ถือว่าแพ้” + back-to-lobby (matches NFR-12) |

Layout rules **[MUST]**
- My board takes the largest vertical share; my **front row (row 0) renders on top** of my block — closest to the enemy per `01-game-design.md` §2 — with mid (row 1) and back (row 2) below it. Row labels are icons + one word (“หน้า / กลาง / หลัง”), not a sentence.
- Board cell **48–56 dp** (not 64 — nine cells at 64 dp doesn't fit a 360 dp-wide screen with gaps), gap `xs` (4dp) between cells, `sm` around the grid. The unit glyph fills ~85 % of the cell; **star pips only**, no stat text on the tile itself (§4.4.0).
- Opponent board is a **collapsed 1-row scout strip** during shop+place, tap → bottom sheet with the full 3×3 read-only; rendered in full inline only during the battle phase (§4.4.0). Never two full boards on screen at once outside battle.
- Bench is a **collapsible tray**: collapsed state shows up to 3 chips + a “(n/8)” count and is the default; tapping the handle expands to the full 8-slot strip and pushes the shop down (`medium2` height animation). This is what buys back the vertical space the extra board row costs.
- Long-press any board or bench unit → bottom sheet with full stats/abilities (same sheet component as the opponent scout). Tap alone selects/drags.
- Ready → becomes “รอคู่แข่ง (1/2)” and stays cancellable until `readyCount == 2`.
- A fusable pair glows gold on the board/bench; a shop card for a unit you already own (fusable via purchase) gets the same gold ring — **[MUST]** no separate “owned” text badge, the ring *is* the signal (paired with the “fusable” label read by screen readers).
- Landscape **[SHOULD]**: board left, shop/bench/scout-strip stacked right, HUD across the top (`OrientationBuilder`).

### 4.5 Match result (overlay on `/match/:matchId`)

**Data**: `game:match:end`.

```
+--------------------------------------+
|              🏆                       |  icon (redundant with colour)
|            ชนะ!                       |  h1, state.success (or danger + 💀)
|      แพ้ให้ bob · 7 รอบ · 4:12         |  body, text.secondary
|                                      |
|   ทีมสุดท้าย  [◆2★][●][▲]             |  UnitAvatar sm row
|   HP สุดท้าย  ██████ 32 / 100          |  HealthBar lg
|                                      |
|  [        เล่นอีกครั้ง (primary)     ]  |
|  [       กลับหน้าหลัก (secondary)    ]  |
+--------------------------------------+
```

**[MUST]** No auto-navigation away — the player dismisses it. `reason: 'disconnect'` shows “คู่แข่งหลุดการเชื่อมต่อ” (or the loss copy if it was us).

### 4.6 `/history` — Past matches

**Purpose**: list the last 50 matches. **Data**: `GET /match/history`.

```
+--------------------------------------+
|  ←  ประวัติการแข่งขัน                   |
|  [ ทั้งหมด ][ ชนะ ][ แพ้ ]             |  AppTabBar
|  ┃ ✔ ชนะ   vs bob      7 รอบ  2 ชม.  |  ┃ = 4dp status stripe
|  ┃ ✘ แพ้   vs carol    5 รอบ  1 วัน   |
|  ┃ ✔ ชนะ   vs dan      9 รอบ  2 วัน   |
+--------------------------------------+
```

Row height 72 dp (tap target), stripe + icon + word (three redundant cues) **[MUST]**.

| State | UI |
|---|---|
| loading | 6 skeleton rows |
| empty | `EmptyView` “ยังไม่มีประวัติแมตช์ · เล่นแมตช์แรกเพื่อเริ่มเก็บสถิติ · [ค้นหาคู่แข่ง]” |
| error | `ErrorView` + retry |
| success | `ListView.builder` + `RefreshIndicator`, 20 rows per page, skeleton row while paging |

### 4.7 `/history/:matchId` — Match detail

**Data**: `GET /match/:matchId`.

```
+--------------------------------------+
|  ←  รายละเอียดแมตช์                    |
|   alice  vs  bob            ✔ ชนะ    |  h3 + result chip
|   7 มี.ค. 2569 · 14:02 · 4:12         |  caption
|  ──────────────────────────────────  |
|  รอบ   ผู้ชนะรอบ        ดาเมจ         |
|   1    alice              0          |
|   2    bob               -5          |
|   3    alice             -5          |
+--------------------------------------+
```

Rounds render as a table/list from `rounds[]`; damage negative-red for the loser side, with a sign as well as colour **[MUST]**. States: loading skeleton · error+retry · (no empty state — a match always has ≥ 1 round).

### 4.8 `/profile` — Account + settings

**Data**: `GET /user/me`, `PATCH /user/me`.

```
+--------------------------------------+
|  ←  โปรไฟล์                           |
|   ( AB )  alice                       |  avatar (initials) + name h3
|           alice@example.com           |  caption, text.secondary
|           เรตติ้ง 1000                 |
|  [ แก้ไขชื่อผู้ใช้ (secondary) ]         |  opens bottom sheet
|  ──────────────────────────────────  |
|  ธีม            [ ระบบ ▾ ]            |  system / light / dark (P1-FE-02)
|  เสียง           [  ●—  ]             |
|  การสั่น         [  ●—  ]             |
|  ลดการเคลื่อนไหว  [ —○  ]              |
|  ──────────────────────────────────  |
|  เซิร์ฟเวอร์      ● ปกติ               |
|  เวอร์ชัน         0.1.0+1              |
|  [        ออกจากระบบ (danger)      ]  |  confirm modal first
+--------------------------------------+
```

Username edit sheet: `AppTextField` + save button (`loading` while patching); `409` → inline “ชื่อนี้ถูกใช้แล้ว”. Logout is `danger` + `AppModal` confirm **[MUST]**.

---

## 5. Motion & realtime behaviour

### 5.1 Page transitions

Push/pop = shared-axis horizontal, `medium2` (300 ms), `emphasized`. Entering `/match/:id` from lobby = fade-through `long2` (it is a context switch, not a drill-down). **[MUST]** No custom per-screen transitions — set it once in `ThemeData.pageTransitionsTheme`.

### 5.2 The countdown must not lie **[MUST]**

`game:match:phase` currently ships `timer` (seconds remaining), not an absolute deadline. So:

```dart
// on every phase event
final deadline = DateTime.now().add(Duration(seconds: payload.timer)); // + clock offset
// render from deadline, re-derive on every frame/second tick
```

- Never `Timer.periodic` that just subtracts 1 — it drifts and freezes when the app is backgrounded.
- On `AppLifecycleState.resumed`, recompute from `deadline` immediately.
- At 0 with no next phase yet → `PhaseTimerRing` switches to the `waiting` state.
- **Backend follow-up (recommended)**: add `phaseEndsAt` (epoch ms) to `game:match:phase` so the client stops depending on message-arrival time. Until then the derived deadline carries one network-latency of error (~< 500 ms per NFR-2), which is acceptable for a 40 s phase.

### 5.3 Optimistic actions **[MUST]**

Allowed to predict: `buy`, `sell`, `refresh`, `fuse`, `place`, `ready` — each carries a `clientActionId`.

```
tap → apply locally + mark pending (card at 70 % opacity, still interactive)
     → server confirms via game:match:state  → clear pending, no visual jump
     → game:error with that clientActionId   → roll back + AppToast(danger) + heavy haptic
```

Never predicted: combat outcomes, damage, HP after battle, match end — those come from the server only (NFR-1).

Error-code → copy mapping lives in §7 and is keyed off `docs/04-api-contracts.md` §5.

### 5.4 Combat replay

The server sends **one** `game:combat:events` batch (100–2000 events); the client plays it, then acks `game:match:combat_done` (60 s server timeout).

| Requirement | Spec |
|---|---|
| Controls | speed `1x / 2x / 4x` + **ข้าม** (jump to final state) **[MUST]** |
| Progress | thin bar showing events played / total |
| `attack` | attacker nudges toward target `short2`; damage numeral floats up 24 dp and fades `medium2`; target `HealthBar` tweens `short4` |
| `heal` / `lifesteal` | green numeral, upward drift, same timing |
| `pierce` | secondary numeral on the unit behind, 60 % size |
| `revive` | white flash 150 ms + HP refill tween |
| `slow` | speed icon over the unit for the rest of the cycle |
| `death` | 200 ms fade to grayscale + drop 8 dp |
| `cycle_end` | 100 ms beat between cycles (readability) |
| `battle_end` | freeze 500 ms, then ack |
| Frame budget | if the batch is too long to play at 1x within the phase, **compress per-event duration** — never drop events (the final state must match the server) **[MUST]** |
| Reduced motion | play at 4x with no floats; final state still shown |

Implementation: one `AnimationController` driving a timeline; only the affected `UnitAvatar`/`HealthBar` rebuild (`AnimatedBuilder`), never a full-screen `setState` **[MUST]**.

### 5.5 Connection UX **[MUST]**

| Socket state | UI |
|---|---|
| `connected` | small green dot + “เชื่อมต่อแล้ว” in lobby AppBar |
| `connecting` / `reconnecting` | warning `ConnectionBanner` “กำลังเชื่อมต่อใหม่… (ครั้งที่ N)” |
| `disconnected` (out of match) | danger banner + “เชื่อมต่อใหม่” + auto-retry countdown |
| `disconnected` (in match) | blocking overlay — the match is lost per NFR-12; warn *while* the link is flaky, not only after the loss |

---

## 6. Assets

**Decision for MVP: placeholder shapes, no sprite art.** Rationale: art is not on the 1-month critical path and every screen above works with shapes; swapping in sprites later touches only `UnitAvatar`.

| Asset | MVP | Later |
|---|---|---|
| Fighter | ● circle, `ally`/`enemy` tint | sprite 128×128 png |
| Healer | ✚ cross | " |
| Ranger | ▲ triangle | " |
| Tank | ■ square | " |
| Star level | 0–2 ★ glyphs, tier colour | frame + glow |
| Board background | flat `surface.card` + 1 dp grid | tiled board art |
| Lobby art | logo + gradient (`accent.primary` → `surface.background`) | key art |
| Icons | **Material Icons** (bundled) | custom set |

**[MUST]** Every unit shape is *also* distinguishable without colour (shape + star count + name label), so colourblind players and grayscale screenshots still read correctly.
Asset conventions: `mobile/assets/images/`, declared in `pubspec.yaml`, 1x/2x/3x variants when real art lands, `ExcludeSemantics` on decorative images.

---

## 7. Copy (Thai)

Rules **[MUST]**: Thai UI, verbs on buttons, no technical terms (`null`, `socket`, `token`, `500`), never blame the user.

| Trigger | Copy |
|---|---|
| `auth.invalid` / bad login | อีเมลหรือรหัสผ่านไม่ถูกต้อง |
| `auth.expired` (refresh failed) | เซสชันหมดอายุ กรุณาเข้าสู่ระบบใหม่ |
| email/username taken (409) | ชื่อนี้ถูกใช้แล้ว ลองชื่ออื่น |
| password too short | รหัสผ่านต้องยาวอย่างน้อย 8 ตัวอักษร |
| network down / timeout | เชื่อมต่อไม่ได้ ตรวจสอบอินเทอร์เน็ตแล้วลองอีกครั้ง |
| 5xx | เซิร์ฟเวอร์มีปัญหาชั่วคราว ลองใหม่อีกครั้ง |
| `shop.insufficient_gold` | ทองไม่พอ ต้องการ {n} ทอง |
| `shop.refresh_used` | รีเฟรชได้รอบละครั้ง |
| `place.slot_occupied` | ช่องนี้มีตัวอยู่แล้ว |
| `place.slot_out_of_range` / board full | บอร์ดเต็ม ย้ายหรือขาย unit ก่อน |
| `match.not_your_turn` | ทำไม่ได้ในเฟสนี้ |
| `rate.limited` | กดเร็วเกินไป รอสักครู่ |
| waiting for opponent | รอคู่แข่งกดพร้อม (1/2) |
| queue > 30 s | ยังหาคู่ไม่ได้ กำลังค้นหาต่อ… |
| disconnected mid-match | การเชื่อมต่อหลุด — แมตช์นี้ถือว่าแพ้ |
| empty history | ยังไม่มีประวัติแมตช์ |

---

## 8. Accessibility

**[MUST]**
1. Contrast: body ≥ 4.5:1, large text / meaningful icons ≥ 3:1.
2. Tap targets ≥ 48×48 dp, ≥ 8 dp apart; in-match controls 56–72 dp. Grow the hit area, not the artwork (`IconButton(constraints: BoxConstraints(minWidth: 48, minHeight: 48))`).
3. No overflow at `textScale 2.0` on a 360×640 screen.
4. Nothing communicated by colour alone (team, HP, win/loss, damage sign).
5. Every tappable icon has a `Semantics(label:)` or `tooltip` in Thai; decorative art is wrapped in `ExcludeSemantics`.
6. Drag-and-drop always has a **tap-to-select → tap-to-place** equivalent.
7. No flashing faster than 3 Hz; “ลดการเคลื่อนไหว” in `/profile` plus `MediaQuery.disableAnimationsOf` are both respected.

Automated check, one per main screen:

```dart
final handle = tester.ensureSemantics();
await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
await expectLater(tester, meetsGuideline(textContrastGuideline));
await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
handle.dispose();
```

---

## 9. Implementation map + Definition of Done

### 9.1 Files this spec creates

```
mobile/lib/core/theme/
├── app_theme.dart        # buildTheme(Brightness) → ThemeData (§2)
├── app_colors.dart       # seed + schemes
├── app_typography.dart   # TextTheme (§2.2)
├── app_spacing.dart      # AppSpacing / AppRadius / AppElevation (§2.3)
├── app_motion.dart       # AppMotion durations + curves (§2.4)
└── game_theme.dart       # ThemeExtension<GameTheme> (§2.1)

mobile/lib/core/widgets/
├── app_scaffold.dart     # SafeArea + padding + ConnectionBanner
├── app_button.dart · app_card.dart · app_text_field.dart
├── health_bar.dart · unit_avatar.dart · phase_timer_ring.dart
├── app_toast.dart · app_modal.dart · app_tab_bar.dart
└── state_views.dart      # Skeleton / EmptyView / ErrorView / ConnectionBanner
```

`main.dart` migration **[MUST]**: move the inline `ThemeData` into `buildTheme()`, add `darkTheme` + `themeMode`, and register routes `/lobby`, `/match/:id` (via `onGenerateRoute`), `/history`, `/history/:matchId`, `/profile` (today: `/login`, `/register`, `/home`).

### 9.2 Per-PR checklist

- [ ] No `Colors.*`, `Color(0x…)`, `fontSize:`, off-scale padding or raw `Duration` under `features/**`
- [ ] Colours read from `colorScheme` / `GameTheme`; both themes rendered and eyeballed
- [ ] Contrast verified for new colour pairs (4.5:1 / 3:1)
- [ ] Screen wrapped in `AppScaffold`; forms scrollable; no overflow at 360×640 and textScale 2.0
- [ ] All four states implemented (loading skeleton / empty / error-with-exit / success)
- [ ] Tap targets ≥ 48 dp, ≥ 8 dp apart; frequent actions in the bottom third
- [ ] Submit buttons guard double-submit and show in-button loading; disabled buttons explain why
- [ ] Countdown derived from a deadline; recomputed on resume
- [ ] Optimistic actions carry `clientActionId` and roll back on `game:error`
- [ ] Motion uses `AppMotion`; > 400 ms animations skippable; reduced motion honoured
- [ ] Semantics labels on icon buttons; `meetsGuideline` × 4 passing
- [ ] Copy matches §7; buttons are verbs
- [ ] `flutter analyze` clean; profile-mode pass on `/match/:id` shows no jank

### 9.3 Issue #106 acceptance mapping

| Done-when (issue) | Where |
|---|---|
| All 6 screens spec’d with wireframes | §4.1–4.8 (7 screens + result overlay) |
| Colour tokens for light + dark | §2.1 |
| Typography + spacing scale | §2.2, §2.3 |
| All reusable components with variants + states | §3.1–3.10 |
| Motion timings documented | §2.4, §5 |
| Doc checked into the repo | this file + README §9/§13 |

Open decisions recorded here rather than left implicit:
1. **Asset pipeline** → placeholder shapes for MVP (§6).
2. **Dark mode** → both themes defined now; the user-facing toggle lands with P1-FE-02; the match screen uses the dark scheme regardless.
3. **`phaseEndsAt`** → client derives a deadline today; backend field recommended (§5.2).
4. **Bench size** → 8 slots per `04-api-contracts.md` (`game:match:state`), not 5.
5. **Board size** → 3×3 (9 slots) per side, updated from the original 2×3 (6 slots); `01-game-design.md` §2, `04-api-contracts.md`, `05-combat-spec.md` §2 updated in the same pass as this doc. Match-screen layout redesigned around it (§4.4.0) rather than just adding a row to the old layout.

### 9.4 Sources — match-screen decluttering research

The 3×3 redesign (§4.4.0) is grounded in patterns documented from Riot's own TFT UI work and mobile auto-chess ports, not invented from scratch:
- TFT keeps stage/round/timer in a single top strip and layers deeper information behind interaction rather than surfacing it all at once — Zachary Roberson, [Teamfight Tactics UI Design](https://zacharyrobes.com/teamfight-tactics-ui-design); misa moirao, [A Riot Games' Video Game Case Study](https://moirao.me/home/tft-ui).
- Trait/unit icons stay simple and unlabelled at small size, with detail on demand — same sources above.
- Auto Chess Mobile animates a shop card's background when the player already owns/can-upgrade that unit, replacing a text badge with a glow — via [Pixune, Best Examples in Mobile Game UI Design](https://pixune.com/blog/best-examples-mobile-game-ui-design/).
- General mobile-game HUD guidance (minimal always-on HUD, thumb-zone controls, layered menus over dense screens): [Trinergy Digital, UI/UX for Game Design](https://www.trinergydigital.com/news/ui-ux-for-game-design-key-elements-for-gamified-interfaces); [Sunstrike Studios, HUD Design Guide](https://sunstrikestudios.com/en/blog/HUD_design_in_games/).
