import 'package:auto_chess_mobile/features/auth/register_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../_util.dart';

// RegisterScreen predates the design system (raw colours, no AppTextField),
// so no a11y-guideline sweep here yet — it gets restyled with the auth
// polish pass. This is a render/behaviour smoke only.
void main() {
  final createButton = find.widgetWithText(ElevatedButton, 'Create account');

  testWidgets('renders three fields and the create-account button',
      (tester) async {
    await pumpScreen(tester, const RegisterScreen());

    expect(find.text('Join Auto Chess'), findsOneWidget);
    expect(find.byType(TextFormField), findsNWidgets(3));
    expect(createButton, findsOneWidget);
    expect(find.text('Already have an account? Sign in'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty submit validates every field inline', (tester) async {
    await pumpScreen(tester, const RegisterScreen());

    await tester.tap(createButton);
    await tester.pump();

    expect(find.text('email required'), findsOneWidget);
    expect(find.text('username required'), findsOneWidget);
    expect(find.text('password required'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
  });
}
