import 'package:auto_chess_mobile/core/widgets/app_button.dart';
import 'package:auto_chess_mobile/core/ws/ws_client.dart';
import 'package:auto_chess_mobile/core/ws/ws_providers.dart';
import 'package:auto_chess_mobile/features/lobby/find_match_button.dart';
import 'package:auto_chess_mobile/features/lobby/lobby_screen.dart';
import 'package:auto_chess_mobile/features/lobby/logout_button.dart';
import 'package:auto_chess_mobile/features/lobby/profile_card.dart';
import 'package:auto_chess_mobile/shared/models/game_events.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../core/ws/fake_ws_transport.dart';
import '../_util.dart';

/// P0-FE-03 — lobby screen state transitions + auto-nav.
///
/// Uses [FakeWsTransport] to act as the server (no socket.io, no
/// realtime). The `matchPhaseProvider` fires when the fake server pushes
/// `game:match:phase` via [FakeWsTransport.emitFromServer].
///
/// `currentUserProvider` is overridden directly so the test doesn't
/// need the Dio interceptor dance.
void main() {
  late FakeWsTransport transport;
  late WsClient wsClient;

  setUp(() {
    installFakeSecureStorage({'access_token': 'jwt', 'refresh_token': 'r'});
    transport = FakeWsTransport();
    wsClient = WsClient(
      url: 'ws://localhost',
      getAccessToken: () async => 'jwt',
      transport: transport,
    );
  });

  tearDown(() {
    wsClient.dispose();
  });

  /// Pump [LobbyScreen] inside a GoRouter so `context.go('/match/<id>')`
  /// in the screen is observable (we watch the router for the location
  /// change in test 4).
  Future<GoRouter> pumpLobby(WidgetTester tester) async {
    final connectFuture = wsClient.connect();
    transport.serverConnect();
    await connectFuture;

    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final router = GoRouter(
      initialLocation: '/lobby',
      routes: [
        GoRoute(path: '/lobby', builder: (_, __) => const LobbyScreen()),
        GoRoute(
          path: '/match/:id',
          builder: (_, GoRouterState state) => Scaffold(
            body: Center(child: Text('match:${state.pathParameters['id']}')),
          ),
        ),
        GoRoute(
          path: '/login',
          builder: (_, __) =>
              const Scaffold(body: Center(child: Text('login'))),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          wsClientProvider.overrideWithValue(wsClient),
          currentUserProvider.overrideWith(
            (ref) async => {'username': 'alice', 'rating': 1234},
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    // Let the FutureProvider + connection-state stream resolve one tick.
    await tester.pumpAndSettle();
    return router;
  }

  testWidgets('renders profile, button + status, with no error',
      (tester) async {
    await pumpLobby(tester);
    expect(find.byType(ProfileCard), findsOneWidget);
    expect(find.byType(FindMatchButton), findsOneWidget);
    expect(find.text('Find match'), findsOneWidget);
    expect(find.text('Searching\u2026'), findsNothing);
    expect(find.byType(LogoutButton), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tap Find match → state searching + button shows Cancel',
      (tester) async {
    await pumpLobby(tester);
    await tester.tap(find.text('Find match'));
    await tester.pump();

    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Find match'), findsNothing);
    expect(find.text('Searching\u2026'), findsOneWidget);

    // The notifier should have emitted `game:matchmaking:join` on the WS.
    expect(transport.sent, hasLength(1));
    expect(transport.sent.first.event, GameActions.matchmakingJoin);
  });

  testWidgets('waits for the server ACK before showing Searching',
      (tester) async {
    await pumpLobby(tester);
    transport.withholdAck = true;

    await tester.tap(find.text('Find match'));
    await tester.pump();

    expect(find.text('Joining queue…'), findsWidgets);
    expect(find.text('Searching…'), findsNothing);
    expect(find.text('Cancel'), findsNothing);
    expect(transport.sent.single.event, GameActions.matchmakingJoin);

    // A missing ACK must not leave the button stuck forever.
    await tester.pump(const Duration(seconds: 5));
    await tester.pump();
    expect(find.text('Find match'), findsOneWidget);
    expect(find.text('Joining queue…'), findsNothing);
  });

  testWidgets('Find match stays disabled while WebSocket is disconnected',
      (tester) async {
    await pumpLobby(tester);
    transport.serverDisconnect();
    await tester.pumpAndSettle();

    final button = tester.widget<AppButton>(find.byType(AppButton));
    expect(button.onPressed, isNull);
    expect(find.text('Searching\u2026'), findsNothing);
    expect(transport.sent, isEmpty);
  });

  testWidgets('tap Cancel → state idle + emit matchmaking:leave',
      (tester) async {
    await pumpLobby(tester);
    await tester.tap(find.text('Find match'));
    await tester.pump();
    await tester.tap(find.text('Cancel'));
    await tester.pump();

    expect(find.text('Find match'), findsOneWidget);
    expect(find.text('Searching\u2026'), findsNothing);
    expect(transport.sent.map((e) => e.event).toList(), [
      GameActions.matchmakingJoin,
      GameActions.matchmakingLeave,
    ]);
  });

  testWidgets('game:match:phase event while searching → state matched + nav',
      (tester) async {
    final router = await pumpLobby(tester);
    await tester.tap(find.text('Find match'));
    await tester.pump();

    // Server pairs us.
    transport.emitFromServer(GameEvents.matchPhase, {
      'matchId': 'abc-123',
      'phase': 'shop_place',
      'round': 1,
      'timer': 40,
      'players': <Map<String, dynamic>>[],
    });
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // The screen should now show "Match found!" then navigate.
    expect(
      find.text('match:abc-123'),
      findsOneWidget,
      reason: 'should have navigated to /match/abc-123 after the toast delay',
    );

    // The notifier should have transitioned to `matched` (the nav is the
    // observable side effect — verified above).
    // Verify via the provider container's exposed state would require a
    // ref handle; we infer from the visible UI.

    // Returning after the game must clear the terminal matchmaking state.
    router.go('/lobby');
    await tester.pumpAndSettle();
    expect(find.text('Find match'), findsOneWidget);
    expect(find.text('Match found!'), findsNothing);
  });

  testWidgets(
    'LogoutButton tap shows confirmation dialog',
    (tester) async {
      await pumpLobby(tester);

      await tester.tap(find.byIcon(Icons.logout));
      await tester.pumpAndSettle();

      expect(find.text('Sign out?'), findsOneWidget);
      expect(
        find.text("You'll have to sign in again to play."),
        findsOneWidget,
      );
      expect(find.text('ยกเลิก'), findsWidgets);
      expect(find.text('Sign out'), findsWidgets);

      // Cancel closes the dialog.
      final cancelButtons = find.text('ยกเลิก');
      await tester.tap(cancelButtons.first);
      await tester.pumpAndSettle();
      expect(find.text('Sign out?'), findsNothing);
    },
  );
}
