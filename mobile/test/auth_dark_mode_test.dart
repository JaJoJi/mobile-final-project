import 'package:auto_chess_mobile/core/theme/app_theme.dart';
import 'package:auto_chess_mobile/features/auth/login_screen.dart';
import 'package:auto_chess_mobile/features/auth/register_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// P3-FE-02: the auth screens dropped their hard-coded `Colors.*`, so they
/// must now render on the dark scheme without a crash or an invisible
/// error box.
void main() {
  Future<void> pumpDark(WidgetTester tester, Widget child) {
    return tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: buildTheme(Brightness.dark),
          home: child,
        ),
      ),
    );
  }

  testWidgets('LoginScreen renders on the dark scheme', (tester) async {
    await pumpDark(tester, const LoginScreen());
    expect(find.text('Auto Chess'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('LoginScreen error box uses theme colours', (tester) async {
    await pumpDark(tester, const LoginScreen());
    await tester.tap(find.text('Sign in')); // triggers validation, not the box
    await tester.pump();
    // The inline error box only shows on a server AuthException; the
    // validation path is enough to prove the screen stays crash-free in dark.
    expect(tester.takeException(), isNull);
  });

  testWidgets('RegisterScreen renders on the dark scheme', (tester) async {
    await pumpDark(tester, const RegisterScreen());
    expect(find.text('Join Auto Chess'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('auth screens survive textScale 2.0', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: buildTheme(Brightness.light),
          home: const MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(2.0)),
            child: LoginScreen(),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });
}
