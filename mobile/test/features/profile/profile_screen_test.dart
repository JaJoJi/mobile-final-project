import 'dart:convert';

import 'package:auto_chess_mobile/core/api/api_client.dart';
import 'package:auto_chess_mobile/core/auth/auth_gate.dart';
import 'package:auto_chess_mobile/core/theme/app_theme.dart';
import 'package:auto_chess_mobile/features/profile/profile_screen.dart';
import 'package:auto_chess_mobile/features/profile/settings_provider.dart';
import 'package:auto_chess_mobile/features/profile/settings_tile.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.handler);
  final ResponseBody Function(RequestOptions) handler;
  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<Uint8List>? _,
    Future<void>? __,
  ) async =>
      handler(o);
  @override
  void close({bool force = false}) {}
}

ResponseBody _json(Map<String, dynamic> body, int status) =>
    ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );

void _installFakeSecureStorage() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
    (call) async => call.method == 'readAll' ? <String, String>{} : null,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<Widget> app({
    required _FakeAdapter adapter,
    double textScale = 1.0,
  }) async {
    SharedPreferences.setMockInitialValues({});
    _installFakeSecureStorage();
    final prefs = await SharedPreferences.getInstance();

    final dio = Dio(BaseOptions(baseUrl: 'http://test.local'))
      ..httpClientAdapter = adapter;

    return ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        apiClientProvider.overrideWithValue(ApiClient(dio: dio)),
      ],
      child: MaterialApp(
        theme: buildTheme(Brightness.light),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: const ProfileScreen(),
      ),
    );
  }

  final okMe = _FakeAdapter((o) {
    if (o.path == '/user/me') {
      return _json(
        {
          'id': 'u1',
          'username': 'alice',
          'email': 'alice@example.com',
          'rating': 1200,
        },
        200,
      );
    }
    return _json({}, 404);
  });

  testWidgets('shows username, email and rating', (tester) async {
    await tester.pumpWidget(await app(adapter: okMe));
    await tester.pumpAndSettle();

    expect(find.text('alice'), findsOneWidget);
    expect(find.text('alice@example.com'), findsOneWidget);
    expect(find.text('เรตติ้ง 1200'), findsOneWidget);
  });

  testWidgets('theme segmented button drives settingsProvider', (tester) async {
    late ProviderContainer container;
    await tester.pumpWidget(await app(adapter: okMe));
    await tester.pumpAndSettle();

    container = ProviderScope.containerOf(
      tester.element(find.byType(ProfileScreen)),
    );
    expect(container.read(settingsProvider).themeMode, ThemeMode.system);

    await tester.tap(find.text('มืด'));
    await tester.pumpAndSettle();

    expect(container.read(settingsProvider).themeMode, ThemeMode.dark);
  });

  testWidgets('sound switch drives settingsProvider', (tester) async {
    await tester.pumpWidget(await app(adapter: okMe));
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(ProfileScreen)),
    );
    final soundTile = find.ancestor(
      of: find.text('เสียงเอฟเฟกต์'),
      matching: find.byType(SettingsTile),
    );
    await tester.ensureVisible(soundTile);
    await tester.pumpAndSettle();
    await tester
        .tap(find.descendant(of: soundTile, matching: find.byType(Switch)));
    await tester.pumpAndSettle();

    expect(container.read(settingsProvider).soundEnabled, isFalse);
  });

  testWidgets('logout asks for confirmation', (tester) async {
    AuthGate.instance.signalSignedIn();
    await tester.pumpWidget(await app(adapter: okMe));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('ออกจากระบบ'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ออกจากระบบ'));
    await tester.pumpAndSettle();

    expect(find.text('ออกจากระบบ?'), findsOneWidget); // confirm dialog title
    await tester.tap(find.text('ยกเลิก'));
    await tester.pumpAndSettle();
    expect(AuthGate.instance.isSignedIn, isTrue); // cancelled → still signed in
  });

  testWidgets('error state offers a retry', (tester) async {
    final failMe = _FakeAdapter((_) => _json({'message': 'boom'}, 500));
    await tester.pumpWidget(await app(adapter: failMe));
    await tester.pumpAndSettle();

    expect(find.text('ลองอีกครั้ง'), findsOneWidget);
  });

  testWidgets('meets tap-target / contrast / label guidelines', (tester) async {
    await tester.pumpWidget(await app(adapter: okMe));
    await tester.pumpAndSettle();

    final handle = tester.ensureSemantics();
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    handle.dispose();
  });

  testWidgets('no overflow at 360x640 and textScale 2.0', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(await app(adapter: okMe, textScale: 2.0));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
