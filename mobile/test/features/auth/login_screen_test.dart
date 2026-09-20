import 'package:auto_chess_mobile/features/auth/login_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../_util.dart';

void main() {
  testWidgets('renders logo, two fields, sign-in and the sign-up link',
      (tester) async {
    await pumpScreen(tester, const LoginScreen());

    expect(find.text('ออโต้เชส'), findsOneWidget);
    expect(find.byType(TextFormField), findsNWidgets(2));
    expect(find.text('เข้าสู่ระบบ'), findsOneWidget);
    expect(find.text('ยังไม่มีบัญชี? สมัครสมาชิก'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('fantasy-page-background')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('password field toggles visibility', (tester) async {
    await pumpScreen(tester, const LoginScreen());

    expect(find.byIcon(Icons.visibility_off), findsOneWidget);
    await tester.tap(find.byIcon(Icons.visibility_off));
    await tester.pump();
    expect(find.byIcon(Icons.visibility), findsOneWidget);
  });

  testWidgets('empty submit shows inline validation, not a snackbar',
      (tester) async {
    await pumpScreen(tester, const LoginScreen());

    await tester.tap(find.text('เข้าสู่ระบบ'));
    await tester.pump();

    expect(find.text('กรุณากรอกอีเมล'), findsOneWidget);
    expect(find.text('กรุณากรอกรหัสผ่าน'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('supports landscape and accessibility guidelines',
      (tester) async {
    await pumpScreen(
      tester,
      const LoginScreen(),
      surfaceSize: const Size(844, 390),
    );
    await tester.pumpAndSettle();

    expect(find.text('เข้าสู่ระบบ'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await expectMeetsA11yGuidelines(tester);
  });
}
