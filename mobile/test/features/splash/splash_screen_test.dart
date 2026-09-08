import 'package:auto_chess_mobile/core/auth/auth_gate.dart';
import 'package:auto_chess_mobile/core/router.dart';
import 'package:auto_chess_mobile/core/theme/app_theme.dart';
import 'package:auto_chess_mobile/features/auth/login_screen.dart';
import 'package:auto_chess_mobile/features/lobby/lobby_screen.dart';
import 'package:auto_chess_mobile/features/splash/splash_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../_util.dart';

void main() {
  Future<GoRouter> pumpAppAt(WidgetTester tester) async {
    final router = buildRouter();
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp.router(
          theme: buildTheme(Brightness.light),
          routerConfig: router,
        ),
      ),
    );
    return router;
  }

  testWidgets('shows the logo + spinner on the first frame', (tester) async {
    installFakeSecureStorage();
    AuthGate.instance.reset();

    await pumpAppAt(tester);
    await tester.pump(); // first frame, before _resolve settles

    expect(find.byType(SplashScreen), findsOneWidget);
    expect(find.text('Auto Chess'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pumpAndSettle(); // drain the resolve future + fallback timer
  });

  testWidgets('no stored token → resolves to /login', (tester) async {
    installFakeSecureStorage();
    AuthGate.instance.reset();

    await pumpAppAt(tester);
    await tester.pumpAndSettle();

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(AuthGate.instance.isSignedIn, isFalse);
  });

  testWidgets('stored token → leaves the splash (never freezes on it)',
      (tester) async {
    installFakeSecureStorage(
      {'access_token': 'a', 'refresh_token': 'r', 'user_id': 'u1'},
    );
    AuthGate.instance.reset();

    await pumpAppAt(tester);
    await tester.pumpAndSettle();

    // The silent refresh has no network in the test, so it fails and the
    // gate resolves to signed-out → /login. The point of the smoke test is
    // that the splash always resolves and never hangs.
    expect(find.byType(SplashScreen), findsNothing);
    expect(
      find.byType(LobbyScreen).evaluate().isNotEmpty ||
          find.byType(LoginScreen).evaluate().isNotEmpty,
      isTrue,
    );
  });
}
