import 'dart:async';

import 'package:auto_chess_mobile/core/api/api_client.dart';
import 'package:auto_chess_mobile/core/auth/auth_gate.dart';
import 'package:auto_chess_mobile/core/auth/auth_repository.dart';
import 'package:auto_chess_mobile/core/router.dart';
import 'package:auto_chess_mobile/core/theme/app_theme.dart';
import 'package:auto_chess_mobile/core/widgets/game_art_frame.dart';
import 'package:auto_chess_mobile/core/widgets/state_views.dart';
import 'package:auto_chess_mobile/features/auth/login_screen.dart';
import 'package:auto_chess_mobile/features/history/history_providers.dart';
import 'package:auto_chess_mobile/features/history/match_models.dart';
import 'package:auto_chess_mobile/features/lobby/lobby_screen.dart';
import 'package:auto_chess_mobile/features/lobby/profile_card.dart';
import 'package:auto_chess_mobile/features/player_hub/player_hub_fixture_provider.dart';
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
        overrides: [
          leaderboardSourceProvider.overrideWith(
            (ref) async => PlayerHubFixtures.leaderboard,
          ),
        ],
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
    expect(find.text('Rival Arena'), findsOneWidget);
    expect(find.byKey(const ValueKey('launch-progress')), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

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

  for (final timeout in [false, true]) {
    testWidgets('keeps splash until home is prepared (timeout: $timeout)',
        (tester) async {
      AuthGate.instance.reset();
      final profile = Completer<Map<String, dynamic>>();
      final history = Completer<List<MatchHistoryEntry>>();
      var historyLoads = 0;
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      final context = tester.element(find.byType(Navigator));
      await tester.runAsync(
        () => Future.wait([
          for (final path in [
            GameBackgroundAssets.arenaBlurred,
            GameBackgroundAssets.homeTeamBanner,
            GameUiAssets.panelTextureBlue,
          ])
            precacheImage(AssetImage(path), context),
        ]),
      );
      final router = buildRouter();
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authRepositoryProvider.overrideWithValue(_ValidAuth()),
            currentUserProvider.overrideWith((ref) => profile.future),
            matchHistoryProvider.overrideWith((ref) {
              historyLoads++;
              return history.future;
            }),
            leaderboardSourceProvider
                .overrideWith((ref) async => PlayerHubFixtures.leaderboard),
          ],
          child: MaterialApp.router(
            theme: buildTheme(Brightness.dark),
            routerConfig: router,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(SplashScreen), findsOneWidget);
      expect(find.byType(LobbyScreen), findsNothing);
      expect(historyLoads, 1);
      if (timeout) {
        await tester.pump(const Duration(seconds: 4));
        await tester.pump();
        expect(AuthGate.instance.isSignedIn, isTrue);
      }
      profile.complete({'username': 'Alice', 'rating': 1000});
      history.complete([]);
      await tester.pumpAndSettle();
      expect(find.byType(LobbyScreen), findsOneWidget);
      expect(find.byType(SkeletonBox), findsNothing);
      expect(historyLoads, 1, reason: 'reuse preloaded data across navigation');
      await tester.pumpWidget(const SizedBox());
    });
  }

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

class _ValidAuth extends AuthRepository {
  _ValidAuth() : super(ApiClient());

  @override
  Future<String?> getAccessToken() async => 'token';

  @override
  Future<AuthResult?> tryRefresh() async => AuthResult(
        accessToken: 'token',
        refreshToken: 'refresh',
        userId: 'alice',
      );
}
