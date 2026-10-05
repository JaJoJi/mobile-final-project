import 'package:auto_chess_mobile/features/splash/launch_backdrop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final fonts = FontLoader('LaunchSarabun')
      ..addFont(rootBundle.load('assets/fonts/sarabun/Sarabun-Medium.ttf'))
      ..addFont(rootBundle.load('assets/fonts/sarabun/Sarabun-Bold.ttf'));
    await fonts.load();
  });
  for (final size in [const Size(390, 844), const Size(844, 390)]) {
    testWidgets('bootstrap design fits $size and supports reduced motion',
        (tester) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: LaunchBackdrop())),
      );
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('กำลังเตรียมสนามรบ…'), findsOneWidget);
      for (final text in [
        'เตรียมเข้าสู่สนาม',
        'ออโต้เชส',
        'กำลังเตรียมสนามรบ…',
      ]) {
        final style = tester.widget<Text>(find.text(text)).style!;
        expect(style.fontFamily, 'LaunchSarabun');
        expect(style.letterSpacing, 0);
      }
      expect(
        tester.getSize(find.byKey(const ValueKey('launch-emblem'))),
        const Size(88, 88),
      );
      expect(
        tester.getSize(find.byKey(const ValueKey('launch-progress'))).height,
        6,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(
        const MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: true),
            child: Scaffold(body: LaunchBackdrop()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(tester.takeException(), isNull);
    });
  }
}
