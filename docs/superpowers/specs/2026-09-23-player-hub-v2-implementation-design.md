# Player Hub V2 implementation design

## Purpose

Implement the selected Player Hub V2 HTML as the visual and interaction
baseline in Flutter. This covers Profile, Create Room, Join Room, and
Leaderboard. The result lets the team review the complete frontend while the
backend owners finish leaderboard and private-room contracts.

`docs/13-player-hub-v2.html` is the acceptance reference. Flutter may use
responsive-native controls where HTML layout is not directly transferable,
but must preserve the visible hierarchy, Thai copy, states, and interaction
intent of that document.

## Scope and constraints

- Change frontend code only; do not change backend, WebSocket messages, or
  database contracts.
- Use existing arena and unit assets. Player crests are rendered in Flutter;
  no generated player images are added.
- Keep Profile account editing, settings, sign-out, and its existing stats
  request functional.
- Until contracts #254 and #255 are available, Leaderboard and Room flows use
  clearly named frontend fixtures behind a small source interface. They must
  not send speculative HTTP or WebSocket requests.
- Retain accessibility: semantic labels, 48 dp interactive targets, and no
  overflow at 360x640 with text scale 2.0.

## Shared presentation

Create a Player Hub shell that uses the existing blurred arena background,
dark overlay, top title bar, and persistent bottom navigation. The shell is
used by Profile, Leaderboard, Create Room, and Join Room so their spacing,
gold accent, blue-stone panel treatment, and safe-area behavior stay aligned.

The navigation mirrors the HTML labels: Home opens `/lobby`, Profile opens
`/profile`, and History opens `/history`. Unit remains visibly present but
disabled with an accessible "coming soon" message because no unit route
exists. Screens that do not fit the bottom navigation in the HTML still use
the same shell to keep the app cohesive.

## Screens

### Profile (`/profile`)

Rebuild the current V2 Profile implementation to match the HTML hierarchy:

1. Header: `โปรไฟล์ผู้บัญชาการ`, subtitle, and account badge.
2. Identity rail: crest, username, email, rating, rating label, and edit-name
   action.
3. Main column: `บันทึกการประลอง`, HUD statistics, rank banner with a
   Leaderboard action, history panel, then private-account/sign-out action.
4. Settings remain available beneath the profile details in a visually
   subordinate panel; this preserves existing app behavior not represented in
   the HTML mockup.

Desktop uses the HTML two-column layout. Narrow screens stack identity before
the main content as the responsive HTML does.

### Leaderboard (`/leaderboard`)

Add a route and screen with the V2 header, a champion panel for rank one, a
three-column ranking list, a highlighted current-player row, and a separate
`อันดับของคุณ` strip. The initial fixture contains the same seven example
players in the HTML. `โหลดเพิ่มเติม` reveals the final fixture rows once,
then becomes disabled.

The screen exposes success, loading, empty, and error-with-retry states. The
fixture source is the only replacement point when #254 provides its API.

### Create Room (`/rooms/create`)

Add the V2 arena room screen from `12-room-v2.html`: top room utility bar,
two opposing player positions with `VS`, owner room code as secondary utility
information, and room status messaging. The UI starts in the host-waiting
fixture state. A local state control is not exposed in the production UI;
tests cover waiting, peer-joined, and reconnecting fixtures.

No actual room code is created and no match starts until #255 defines the
room lifecycle. The primary action returns to the lobby and is labelled to
avoid implying a real network operation.

### Join Room (`/rooms/join`)

Add the V2 split layout: unit illustration and challenger copy beside the
room-code form. Input normalizes to uppercase. Empty input disables join. A
fixture code `K7M2Q9` transitions to the local joined-room presentation;
other non-empty codes show the exact not-found feedback from the HTML. The
screen does not call a server until #255 is available.

## Data boundaries

`PlayerHubFixtures` owns all temporary leaderboard and room sample data.
Screen widgets consume typed display models through source providers, never
literal maps distributed through widgets. Existing profile API providers stay
unchanged. When backend is ready, replace each fixture source implementation
with an API/WebSocket adapter while preserving the display models and screen
state contract.

## Error handling

- Profile account request failure retains its current retry experience.
- Profile statistics error keeps account/settings interactive and offers retry.
- Leaderboard fixture source can surface loading, empty, and error states for
  widget testing and will use the same handling for future API failures.
- Join validates locally; only `K7M2Q9` succeeds before the room contract.
- Create Room clearly labels fixture status; it never reports a real room as
  created or connected.

## Verification

Widget tests cover each screen's V2 hierarchy and all declared states;
interaction tests cover profile navigation actions, leaderboard load-more,
and join-code normalization/validation. Every Player Hub screen is tested at
360x640 and text scale 2.0 for overflow. Run `flutter analyze` and the full
Flutter test suite before every commit.
