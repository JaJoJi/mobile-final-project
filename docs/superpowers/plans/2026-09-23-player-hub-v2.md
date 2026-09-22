# Player Hub V2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the selected HTML V2 as the Flutter experience for Profile, Leaderboard, Create Room, and Join Room.

**Architecture:** Keep backend-independent display data behind typed Riverpod fixture providers. Build a reusable Player Hub shell above those data sources, then compose route-specific screens inside it. Existing Profile API providers remain intact; fixture sources are only for Leaderboard and Rooms, so later API/WebSocket adapters replace sources without changing widgets.

**Tech Stack:** Flutter, Dart, flutter_riverpod, go_router, flutter_test, existing arena and unit assets.

**Spec:** `docs/superpowers/specs/2026-09-23-player-hub-v2-implementation-design.md`

## Global Constraints

- Change frontend code only; do not change backend, WebSocket messages, or database contracts.
- Use existing arena and unit assets; render player crests in Flutter and add no generated player images.
- Preserve Profile account editing, settings, sign-out, and its existing stats request.
- Leaderboard and Room flows use typed fixture sources and send no speculative HTTP or WebSocket requests until #254 and #255 exist.
- Preserve semantic labels, 48 dp targets, and no overflow at 360x640 with text scale 2.0.
- Treat `docs/13-player-hub-v2.html` and `docs/12-room-v2.html` as the visual/copy acceptance references.

## Review Focus

- A long Thai username/email must wrap or ellipsize without changing the identity panel width; test it in Task 2.
- A player outside the first loaded leaderboard rows must still see the separate `อันดับของคุณ` strip; test it in Task 3.
- A leaderboard retry must recover from an error without navigating away; test it in Task 3.
- A pasted room code containing lowercase letters and spaces must normalize to uppercase before validation; test it in Task 4.
- Text scale 2.0 must not overflow any Player Hub route; test each route in its owning task.

---

## File structure

- `mobile/lib/features/player_hub/player_hub_models.dart` — immutable typed display models for ranking and room fixture states.
- `mobile/lib/features/player_hub/player_hub_fixture_provider.dart` — Riverpod fixture sources and state overrides for tests.
- `mobile/lib/features/player_hub/player_hub_shell.dart` — V2 arena background, title bar, safe-area layout, and navigation.
- `mobile/lib/features/player_hub/player_crest.dart` — reusable Flutter-painted crest used by profile, champion, and room players.
- `mobile/lib/features/leaderboard/leaderboard_screen.dart` — V2 Leaderboard route and state rendering.
- `mobile/lib/features/rooms/create_room_screen.dart` — V2 Create Room fixture route.
- `mobile/lib/features/rooms/join_room_screen.dart` — V2 Join Room form and joined-room transition.
- `mobile/lib/features/profile/profile_screen.dart` — V2 Profile hierarchy and route actions, preserving existing account/settings behavior.
- `mobile/lib/core/router.dart` — routes for leaderboard and rooms.
- `mobile/test/features/...` — widget tests colocated by feature.

### Task 1: Typed fixture boundary

**Files:**
- Create: `mobile/lib/features/player_hub/player_hub_models.dart`
- Create: `mobile/lib/features/player_hub/player_hub_fixture_provider.dart`
- Test: `mobile/test/features/player_hub/player_hub_fixture_provider_test.dart`

**Interfaces:**
- Produces `LeaderboardEntry`, `LeaderboardViewData`, `RoomPlayer`, `RoomViewState`, `leaderboardSourceProvider`, and `roomFixtureProvider`.
- Consumed by Tasks 3 and 4; neither task accesses literal fixture maps.

- [ ] **Step 1: Write the failing fixture-model tests**

```dart
test('leaderboard fixture separates visible rows from current player', () {
  final data = PlayerHubFixtures.leaderboard;
  expect(data.entries, hasLength(7));
  expect(data.currentPlayer.username, 'JaJoJi');
  expect(data.currentPlayer.rank, 28);
});

test('room fixture starts with host waiting for an opponent', () {
  expect(PlayerHubFixtures.hostWaiting.status, RoomFixtureStatus.waiting);
  expect(PlayerHubFixtures.hostWaiting.guest, isNull);
});
```

- [ ] **Step 2: Run the fixture test to verify it fails**

Run: `rtk flutter test --no-pub test/features/player_hub/player_hub_fixture_provider_test.dart`

Expected: FAIL because the fixture types and provider do not exist.

- [ ] **Step 3: Implement immutable models and providers**

```dart
enum RoomFixtureStatus { waiting, joined, reconnecting }

class LeaderboardEntry {
  const LeaderboardEntry({required this.rank, required this.username, required this.rating});
  final int rank;
  final String username;
  final int rating;
}

final leaderboardSourceProvider =
    FutureProvider<LeaderboardViewData>((ref) async => PlayerHubFixtures.leaderboard);

final roomFixtureProvider = Provider<RoomViewState>((ref) => PlayerHubFixtures.hostWaiting);
```

Populate the seven names/rating values and `JaJoJi #28 / 1,240` exactly as displayed in the V2 HTML. Keep fixtures in `PlayerHubFixtures` and use `overrideWith` in widgets tests to exercise loading, empty, and error state.

- [ ] **Step 4: Run the fixture tests to verify they pass**

Run: `rtk flutter test --no-pub test/features/player_hub/player_hub_fixture_provider_test.dart`

Expected: PASS.

- [ ] **Step 5: Commit the independently testable boundary**

```bash
rtk git add mobile/lib/features/player_hub mobile/test/features/player_hub
rtk git commit -m "feat(player-hub): add typed display fixtures"
```

### Task 2: Shared V2 shell and exact Profile hierarchy

**Files:**
- Create: `mobile/lib/features/player_hub/player_hub_shell.dart`
- Create: `mobile/lib/features/player_hub/player_crest.dart`
- Modify: `mobile/lib/features/profile/profile_screen.dart`
- Modify: `mobile/lib/features/profile/player_hub_navigation.dart`
- Test: `mobile/test/features/profile/profile_screen_test.dart`

**Interfaces:**
- Consumes `ProfileScreen` account/stats providers and `PlayerHubShell(title, subtitle, badge, child, selectedTab)`.
- Produces a Profile page whose rank CTA calls `context.go('/leaderboard')` and history CTA calls `context.go('/history')`.
- Task 3 consumes `PlayerHubShell` and `PlayerCrest`.

- [ ] **Step 1: Write failing Profile V2 acceptance tests**

```dart
expect(find.text('โปรไฟล์ผู้บัญชาการ'), findsOneWidget);
expect(find.text('บันทึกการประลอง'), findsOneWidget);
expect(find.text('ดูตารางอันดับ'), findsOneWidget);
expect(find.text('ทุกแมตช์คือประสบการณ์'), findsOneWidget);
expect(find.text('ข้อมูลบัญชีเป็นส่วนตัว'), findsOneWidget);
```

Add a 360x640/text-scale-2 test using a long username and email, and retain tests for settings, statistics failure, edit name, and logout confirmation.

- [ ] **Step 2: Run the Profile test to verify it fails**

Run: `rtk flutter test --no-pub test/features/profile/profile_screen_test.dart`

Expected: FAIL because the V2 rank/history/private-account hierarchy is absent.

- [ ] **Step 3: Implement shell, crest, and Profile composition**

```dart
class PlayerHubShell extends StatelessWidget {
  const PlayerHubShell({
    super.key,
    required this.title,
    required this.subtitle,
    required this.child,
    this.badge,
    this.selectedTab = PlayerHubTab.profile,
  });
}

class PlayerCrest extends StatelessWidget {
  const PlayerCrest({super.key, required this.label, this.size = 108});
  final String label;
  final double size;
}
```

Move arena backdrop/title/navigation code out of `ProfileScreen` into the shell. Make Profile match the V2 order: identity rail, HUD stats, rank banner + leaderboard CTA, history panel + CTA, private-account/sign-out row, then the retained settings panel. On narrow screens stack the rail before content. Clamp only dense header/navigation controls, never the whole screen.

- [ ] **Step 4: Run Profile tests to verify they pass**

Run: `rtk flutter test --no-pub test/features/profile/profile_screen_test.dart`

Expected: PASS with no Flutter overflow exception.

- [ ] **Step 5: Commit the shell and Profile slice**

```bash
rtk git add mobile/lib/features/player_hub mobile/lib/features/profile mobile/test/features/profile
rtk git commit -m "feat(profile): match Player Hub V2 layout"
```

### Task 3: Leaderboard route and visual states

**Files:**
- Create: `mobile/lib/features/leaderboard/leaderboard_screen.dart`
- Create: `mobile/test/features/leaderboard/leaderboard_screen_test.dart`
- Modify: `mobile/lib/core/router.dart`

**Interfaces:**
- Consumes `LeaderboardViewData` through `leaderboardSourceProvider`, `PlayerHubShell`, and `PlayerCrest`.
- Produces `LeaderboardScreen.path == '/leaderboard'`.
- Task 2's Profile rank CTA and Task 4 room header can navigate to this path.

- [ ] **Step 1: Write failing Leaderboard tests**

```dart
expect(find.text('ตารางอันดับ'), findsOneWidget);
expect(find.text('MoonKnight'), findsWidgets);
expect(find.text('อันดับของคุณ'), findsOneWidget);
expect(find.text('#28'), findsOneWidget);

await tester.tap(find.text('โหลดเพิ่มเติม'));
await tester.pumpAndSettle();
expect(find.text('SilverPawn'), findsOneWidget);
expect(find.text('แสดงข้อมูลตัวอย่างครบแล้ว'), findsOneWidget);
```

Add provider overrides that assert `กำลังโหลดข้อมูล…`, `ยังไม่มีข้อมูลอันดับ`, and `โหลดข้อมูลไม่สำเร็จ` plus a retry button. Include a 360x640/text-scale-2 render test.

- [ ] **Step 2: Run Leaderboard tests to verify they fail**

Run: `rtk flutter test --no-pub test/features/leaderboard/leaderboard_screen_test.dart`

Expected: FAIL because the screen and route do not exist.

- [ ] **Step 3: Implement the V2 Leaderboard**

```dart
class LeaderboardScreen extends ConsumerStatefulWidget {
  const LeaderboardScreen({super.key});
  static const path = '/leaderboard';
}
```

Use the shell header copy `ผู้บัญชาการแห่งสนาม · เรียงตามเรตติ้ง`, champion panel, rank/player/rating table, gold self-row treatment when the current player is visible, and the separate current-player strip unconditionally. Initially render five rows; reveal fixture rows 6–7 from a local `bool _showAll`. The error state's retry invalidates `leaderboardSourceProvider`.

- [ ] **Step 4: Run Leaderboard tests to verify they pass**

Run: `rtk flutter test --no-pub test/features/leaderboard/leaderboard_screen_test.dart`

Expected: PASS.

- [ ] **Step 5: Commit Leaderboard**

```bash
rtk git add mobile/lib/features/leaderboard mobile/lib/core/router.dart mobile/test/features/leaderboard
rtk git commit -m "feat(leaderboard): add Player Hub V2 ranking"
```

### Task 4: Create Room and Join Room fixture routes

**Files:**
- Create: `mobile/lib/features/rooms/create_room_screen.dart`
- Create: `mobile/lib/features/rooms/join_room_screen.dart`
- Create: `mobile/test/features/rooms/create_room_screen_test.dart`
- Create: `mobile/test/features/rooms/join_room_screen_test.dart`
- Modify: `mobile/lib/core/router.dart`

**Interfaces:**
- Consumes `RoomViewState`, `RoomFixtureStatus`, `roomFixtureProvider`, `PlayerHubShell`, and `PlayerCrest`.
- Produces `CreateRoomScreen.path == '/rooms/create'` and `JoinRoomScreen.path == '/rooms/join'`.
- Uses no Dio client and no WebSocket provider.

- [ ] **Step 1: Write failing Room tests**

```dart
expect(find.text('สร้างห้อง'), findsOneWidget);
expect(find.text('VS'), findsOneWidget);
expect(find.text('กำลังรอเพื่อนเข้าร่วม'), findsOneWidget);

await tester.enterText(find.byType(TextField), ' k7m2q9 ');
await tester.tap(find.text('เข้าร่วมห้อง'));
await tester.pumpAndSettle();
expect(find.text('K7M2Q9'), findsOneWidget);

await tester.enterText(find.byType(TextField), 'nope');
await tester.tap(find.text('เข้าร่วมห้อง'));
await tester.pump();
expect(find.text('ไม่พบห้องนี้ ลองรหัสตัวอย่าง K7M2Q9'), findsOneWidget);
```

Override `roomFixtureProvider` for joined/reconnecting room assertions. Add 360x640/text-scale-2 tests for both routes.

- [ ] **Step 2: Run Room tests to verify they fail**

Run: `rtk flutter test --no-pub test/features/rooms`

Expected: FAIL because room routes and screens do not exist.

- [ ] **Step 3: Implement Create Room and Join Room**

```dart
class CreateRoomScreen extends ConsumerWidget {
  const CreateRoomScreen({super.key});
  static const path = '/rooms/create';
}

class JoinRoomScreen extends ConsumerStatefulWidget {
  const JoinRoomScreen({super.key});
  static const path = '/rooms/join';
}
```

Create Room uses the `12-room-v2.html` arena layout: utility room-code bar, host/guest crest positions, central `VS`, and waiting/joined/reconnecting copy. Join uses the V2 fighter illustration, challenger copy, uppercase room-code input, and fixture-only success path for `K7M2Q9`; success replaces the form with the joined-room visual. Other non-empty values show the exact not-found message. Add both routes to `buildRouter()`.

- [ ] **Step 4: Run Room tests to verify they pass**

Run: `rtk flutter test --no-pub test/features/rooms`

Expected: PASS with no network calls.

- [ ] **Step 5: Commit Room UI**

```bash
rtk git add mobile/lib/features/rooms mobile/lib/core/router.dart mobile/test/features/rooms
rtk git commit -m "feat(rooms): add Player Hub V2 fixture screens"
```

### Task 5: Discoverability and complete regression verification

**Files:**
- Modify: `mobile/lib/features/lobby/lobby_screen.dart`
- Modify: `mobile/test/features/lobby/lobby_screen_test.dart`
- Modify: `mobile/test/features/profile/profile_screen_test.dart`

**Interfaces:**
- Consumes the paths from `LeaderboardScreen`, `CreateRoomScreen`, and `JoinRoomScreen`.
- Produces authenticated, discoverable navigation to all new V2 routes.

- [ ] **Step 1: Write failing lobby navigation tests**

```dart
expect(find.text('สร้างห้องส่วนตัว'), findsOneWidget);
expect(find.text('เข้าร่วมห้อง'), findsOneWidget);
expect(find.text('ตารางอันดับ'), findsOneWidget);
```

Tap each control in a router test and assert its target screen title. Keep `FindMatchButton` behavior unchanged.

- [ ] **Step 2: Run the lobby test to verify it fails**

Run: `rtk flutter test --no-pub test/features/lobby/lobby_screen_test.dart`

Expected: FAIL because the V2 route actions are not exposed from the lobby.

- [ ] **Step 3: Add compact V2 route actions without changing matchmaking**

```dart
Wrap(
  spacing: AppSpacing.sm,
  runSpacing: AppSpacing.sm,
  children: [
    OutlinedButton(onPressed: () => context.go(CreateRoomScreen.path), child: const Text('สร้างห้องส่วนตัว')),
    OutlinedButton(onPressed: () => context.go(JoinRoomScreen.path), child: const Text('เข้าร่วมห้อง')),
    TextButton(onPressed: () => context.go(LeaderboardScreen.path), child: const Text('ตารางอันดับ')),
  ],
)
```

Place these beneath the existing matchmaking status so `FindMatchButton` remains the primary CTA.

- [ ] **Step 4: Run focused and full verification**

Run: `rtk flutter analyze`

Expected: `No issues found!`

Run: `rtk flutter test --no-pub --reporter compact`

Expected: all tests pass.

Run: `rtk git diff --check`

Expected: no output.

- [ ] **Step 5: Commit the final integrated slice**

```bash
rtk git add mobile/lib/features/lobby mobile/test/features/lobby mobile/test/features/profile
rtk git commit -m "feat(lobby): expose Player Hub V2 routes"
```
