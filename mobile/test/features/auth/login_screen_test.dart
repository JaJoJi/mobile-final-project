import 'package:auto_chess_mobile/features/auth/login_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../_util.dart';

// LoginScreen predates the design system (raw colours, no AppTextField /
// AppButton), so no a11y-guideline sweep here yet — it gets restyled with
// the auth polish pass. Render / behaviour smoke only.
void main() {
  testWidgets('renders logo, two fields, sign-in and the sign-up link',
      (tester) async {
    await pumpScreen(tester, const LoginScreen());

    expect(find.text('Auto Chess'), findsOneWidget);
    expect(find.byType(TextFormField), findsNWidgets(2));
    expect(find.text('Sign in'), findsOneWidget);
    expect(find.text("Don't have an account? Sign up"), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('password field toggles visibility', (tester) async {
    await pumpScreen(tester, const LoginScreen());

    expect(find.byIcon(Icons.visibility), findsOneWidget);
    await tester.tap(find.byIcon(Icons.visibility));
    await tester.pump();
    expect(find.byIcon(Icons.visibility_off), findsOneWidget);
  });

  testWidgets('empty submit shows inline validation, not a snackbar',
      (tester) async {
    await pumpScreen(tester, const LoginScreen());

    await tester.tap(find.text('Sign in'));
    await tester.pump();

    expect(find.text('email required'), findsOneWidget);
    expect(find.text('password required'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
  });
}
