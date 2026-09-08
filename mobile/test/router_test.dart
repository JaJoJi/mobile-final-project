import 'package:auto_chess_mobile/core/auth/auth_gate.dart';
import 'package:auto_chess_mobile/core/router.dart';
import 'package:auto_chess_mobile/features/auth/login_screen.dart';
import 'package:auto_chess_mobile/features/lobby/lobby_screen.dart';
import 'package:auto_chess_mobile/features/profile/profile_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void _installFakeStorage() {
  final store = <String, String>{};
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
    (call) async {
      final args = (call.arguments as Map?) ?? const {};
      switch (call.method) {
        case 'read':
          return store[args['key']];
        case 'write':
          store[args['key'] as String] = args['value'] as String;
          return null;
        case 'delete':
          store.remove(args['key']);
          return null;
        case 'readAll':
          return Map<String, String>.from(store);
        case 'deleteAll':
          store.clear();
          return null;
      }
      return null;
    },
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(_installFakeStorage);

  Future<GoRouter> pumpApp(WidgetTester tester) async {
    final router = buildRouter();
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    return router;
  }

  testWidgets('not signed in → protected route redirects to /login',
      (tester) async {
    AuthGate.instance.signalSignedOut();
    final router = await pumpApp(tester);

    router.go(LobbyScreen.path);
    await tester.pumpAndSettle();

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.byType(LobbyScreen), findsNothing);
  });

  testWidgets('signed in → /login redirects to /lobby', (tester) async {
    AuthGate.instance.signalSignedIn();
    final router = await pumpApp(tester);

    router.go(LoginScreen.path);
    await tester.pumpAndSettle();

    expect(find.byType(LobbyScreen), findsOneWidget);
  });

  testWidgets('signed in → deep link to /profile resolves', (tester) async {
    AuthGate.instance.signalSignedIn();
    final router = await pumpApp(tester);

    router.go(ProfileScreen.path);
    await tester.pumpAndSettle();

    expect(find.byType(ProfileScreen), findsOneWidget);
  });

  testWidgets('sign-out signal bounces an authed screen back to /login',
      (tester) async {
    AuthGate.instance.signalSignedIn();
    final router = await pumpApp(tester);
    router.go(ProfileScreen.path);
    await tester.pumpAndSettle();
    expect(find.byType(ProfileScreen), findsOneWidget);

    AuthGate.instance.signalSignedOut();
    await tester.pumpAndSettle();

    expect(find.byType(LoginScreen), findsOneWidget);
  });
}
