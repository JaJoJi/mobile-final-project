import 'package:auto_chess_mobile/core/theme/app_theme.dart';
import 'package:auto_chess_mobile/features/rooms/join_room_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget app({double textScale = 1}) => MaterialApp(
        theme: buildTheme(Brightness.light),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
          ),
          child: child!,
        ),
        home: const JoinRoomScreen(),
      );

  testWidgets('shows the V2 join form and keeps submit disabled when empty',
      (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.text('เข้าร่วมห้อง'), findsNWidgets(2));
    expect(find.text('พบเพื่อนในสนามส่วนตัว'), findsOneWidget);
    expect(find.text('รหัสห้อง'), findsOneWidget);
    expect(find.text('K7M2Q9'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
  });

  testWidgets('normalizes a pasted code and shows the local joined fixture',
      (tester) async {
    await tester.pumpWidget(app());
    await tester.enterText(find.byType(TextField), ' k7m2q9 ');
    await tester.pump();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      ' k7m2q9 ',
    );
    await tester.ensureVisible(
      find.widgetWithText(FilledButton, 'เข้าร่วมห้อง'),
    );
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );
    expect(
      find.widgetWithText(FilledButton, 'เข้าร่วมห้อง').hitTestable(),
      findsOneWidget,
    );
    await tester.tap(find.widgetWithText(FilledButton, 'เข้าร่วมห้อง'));
    await tester.pumpAndSettle();

    expect(find.text('K7M2Q9'), findsOneWidget);
    expect(find.text('Astra'), findsOneWidget);
    expect(find.text('VS'), findsOneWidget);
  });

  testWidgets('shows a clear message for an unknown non-empty code',
      (tester) async {
    await tester.pumpWidget(app());
    await tester.enterText(find.byType(TextField), 'nope');
    await tester.pump();
    await tester.ensureVisible(
      find.widgetWithText(FilledButton, 'เข้าร่วมห้อง'),
    );
    await tester.tap(find.widgetWithText(FilledButton, 'เข้าร่วมห้อง'));
    await tester.pumpAndSettle();

    expect(find.text('ไม่พบห้องนี้ ลองรหัสตัวอย่าง K7M2Q9'), findsOneWidget);
  });

  testWidgets('does not overflow at 360x640 with text scale 2', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(app(textScale: 2));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
