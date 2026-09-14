import 'package:auto_chess_mobile/core/auth/auth_gate.dart';
import 'package:auto_chess_mobile/core/ws/ws_client.dart';
import 'package:auto_chess_mobile/core/ws/ws_providers.dart';
import 'package:auto_chess_mobile/features/lobby/profile_card.dart';
import 'package:auto_chess_mobile/features/profile/settings_provider.dart';
import 'package:auto_chess_mobile/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/ws/fake_ws_transport.dart';
import 'features/_util.dart';

/// Regression test for the WS-gateway lifecycle bug found while exercising
/// P0-FE-03: nothing in the app was calling [WsClient.connect], so the
/// `AppScaffold` connection banner stayed red forever after sign-in.
///
/// `_AutoChessAppState` now listens to [AuthGate] and opens / closes the
/// WS client on sign-in / sign-out transitions. These tests pin that
/// contract so the banner can't silently regress.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeWsTransport transport;
  late WsClient wsClient;

  setUp(() async {
    // The auth gate is a process-wide singleton; reset it between tests
    // so sign-in / sign-out state never leaks.
    AuthGate.instance.reset();
    // Keep SplashScreen offline in this lifecycle-only test. The auth state
    // transitions below are driven explicitly through AuthGate.
    installFakeSecureStorage();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    transport = FakeWsTransport();
    wsClient = WsClient(
      url: 'ws://localhost',
      getAccessToken: () async => 'jwt',
      transport: transport,
    );
  });

  tearDown(() {
    wsClient.dispose();
    AuthGate.instance.reset();
  });

  /// Pump the full [AutoChessApp] with the WS provider overridden so we
  /// can read the fake transport's counters.
  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final prefs = await SharedPreferences.getInstance();
    // Start on the signed-out route so Splash does not perform a real HTTP
    // refresh in this WS-lifecycle test.
    AuthGate.instance.signalSignedOut();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          wsClientProvider.overrideWithValue(wsClient),
          currentUserProvider.overrideWith(
            (ref) async => {
              'id': 'u1',
              'username': 'tester',
              'rating': 1000,
            },
          ),
        ],
        child: const AutoChessApp(),
      ),
    );
    await tester.pump();
  }

  testWidgets(
    'sign-in → connect() called once, sign-out → disconnect() called once',
    (tester) async {
      await pumpApp(tester);

      // Initial signed-out frame → no WS activity.
      expect(transport.connectCalls, 0);
      expect(transport.disconnectCalls, 0);

      AuthGate.instance.signalSignedIn();
      await tester.pump();
      expect(
        transport.connectCalls,
        1,
        reason: 'sign-in must open the WS gateway',
      );
      expect(transport.disconnectCalls, 0);

      AuthGate.instance.signalSignedOut();
      await tester.pump();
      expect(
        transport.disconnectCalls,
        1,
        reason: 'sign-out must close the WS gateway',
      );
      expect(transport.connectCalls, 1, reason: 'no extra connect on sign-out');
    },
  );

  testWidgets('repeated sign-in signals do not stack connect calls',
      (tester) async {
    await pumpApp(tester);
    AuthGate.instance.signalSignedIn();
    await tester.pump();
    expect(transport.connectCalls, 1);

    // No-op: the listener caches the last state and skips duplicates.
    AuthGate.instance.signalSignedIn();
    await tester.pump();
    expect(transport.connectCalls, 1);
  });

  testWidgets('logout → sign-in reconnects (no sticky disconnect)',
      (tester) async {
    await pumpApp(tester);
    AuthGate.instance.signalSignedIn();
    await tester.pump();
    expect(transport.connectCalls, 1);
    transport.serverConnect();
    await tester.pump();

    AuthGate.instance.signalSignedOut();
    await tester.pump();
    expect(transport.disconnectCalls, 1);

    AuthGate.instance.signalSignedIn();
    await tester.pump();
    expect(
      transport.connectCalls,
      2,
      reason: 'a second sign-in must open a fresh WS',
    );
    expect(transport.disconnectCalls, 1);
  });
}
