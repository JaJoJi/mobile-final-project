import 'package:auto_chess_mobile/core/widgets/app_button.dart';
import 'package:auto_chess_mobile/features/auth/register_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../_util.dart';

void main() {
  final createButton = find.widgetWithText(AppButton, 'สร้างบัญชี');

  testWidgets('renders three fields and the create-account button',
      (tester) async {
    await pumpScreen(tester, const RegisterScreen());

    expect(find.text('สมัครเล่นออโต้เชส'), findsOneWidget);
    expect(find.byType(TextFormField), findsNWidgets(3));
    expect(createButton, findsOneWidget);
    expect(find.text('มีบัญชีอยู่แล้ว? เข้าสู่ระบบ'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('fantasy-page-background')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty submit validates every field inline', (tester) async {
    await pumpScreen(tester, const RegisterScreen());

    await tester.tap(createButton);
    await tester.pump();

    expect(find.text('กรุณากรอกอีเมล'), findsOneWidget);
    expect(find.text('กรุณากรอกชื่อผู้ใช้'), findsOneWidget);
    expect(find.text('กรุณากรอกรหัสผ่าน'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('supports landscape and accessibility guidelines',
      (tester) async {
    await pumpScreen(
      tester,
      const RegisterScreen(),
      surfaceSize: const Size(844, 500),
    );
    await tester.pumpAndSettle();

    expect(createButton, findsOneWidget);
    expect(tester.takeException(), isNull);
    await expectMeetsA11yGuidelines(tester);
  });
}
