import 'package:auto_chess_mobile/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// In-memory stand-in for `flutter_secure_storage`'s platform channel.
void installFakeSecureStorage([Map<String, String>? seed]) {
  final store = Map<String, String>.of(seed ?? const {});
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

/// Pump [child] inside a themed [MaterialApp] with a fixed test surface.
Future<void> pumpScreen(
  WidgetTester tester,
  Widget child, {
  List<Override> overrides = const [],
  Size surfaceSize = const Size(390, 844),
}) async {
  tester.view.physicalSize = surfaceSize;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: buildTheme(Brightness.light),
        home: child,
      ),
    ),
  );
}

/// The four accessibility guidelines every real screen must meet
/// (ux-ui-design skill §17 / design spec §8).
Future<void> expectMeetsA11yGuidelines(WidgetTester tester) async {
  final handle = tester.ensureSemantics();
  await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
  await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
  await expectLater(tester, meetsGuideline(textContrastGuideline));
  await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
  handle.dispose();
}
